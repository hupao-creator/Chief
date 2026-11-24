"""Interact with real mounted controls; semantic observations are not pixels."""
import json
import math
import time

from client import Client
from report import save


class Desktop:
    def __init__(self, session):
        self.session = session
        self.client = Client(session.root / "ui.sock")

    def close(self):
        self.client.close()

    def reconnect(self):
        # Operator input may outlive the server's idle connection deadline.
        # Reconnect before a fresh observation, never retry a mutating action.
        self.client.close()
        self.client = Client(self.session.root / "ui.sock")

    def request(self, action=None):
        result = self.client.request(action)
        with (self.session.output / "ui-events.jsonl").open("a") as stream:
            stream.write(json.dumps({"atNS": time.monotonic_ns(), "action": action, "response": result}) + "\n")
        if result["pid"] != self.session.app.pid:
            raise RuntimeError("UI response came from a different process")
        if result.get("ok") is not True:
            raise AssertionError(f"UI rejected operation: {result.get('error')}")
        return result["snapshot"]

    def stable(self, predicate=lambda s: True):
        deadline, since = time.monotonic() + 30, None
        while time.monotonic() < deadline:
            state = self.request()
            if state and state["mounted"] and not state["transitioning"] and predicate(state):
                if since is None:
                    since = time.monotonic()
                if time.monotonic() - since >= .2:
                    return state
            else:
                since = None
            time.sleep(.1)
        raise TimeoutError("mounted UI postcondition did not settle; see ui-events.jsonl")

    @staticmethod
    def has_turn(state, execution, destination="current"):
        controls = state.get("reading", {}).get("controls", [])
        route = any(c["role"] == "conversation" and c["value"].get("destination") == destination
            and c["value"].get("selectedRow") == "turn:" + execution
            and c["value"].get("transitioning") is False for c in controls)
        return route and any(c["role"] == "turn" and c["value"].get("executionId") == execution
            and c["value"].get("state") == "ready" and c["value"].get("visibleRowCount", 0) > 0
            for c in controls)

    def overview_scroll(self, thread):
        def settled(state):
            overview = state["overview"]
            return (state["page"] == "overview" and state["runtimeAvailable"]
                    and "overview.scroll" in state["actions"] and not overview["layingOut"]
                    and any(card.get("ref", {}).get("threadId") == thread
                            and card["id"] in overview["mountedCardIds"] for card in overview["cards"]))

        state = self.stable(settled)
        save(self.session.output / "overview-leading.json", state)
        initial = state["overview"]["camera"]
        placements = state["overview"]["placements"]
        assert {p["id"] for p in placements} == {c["id"] for c in state["overview"]["cards"]}
        viewport = initial["viewport"]
        width = max(p["column"] + p["columns"] for p in placements) * 336 - 16
        height = max(p["row"] + p["rows"] for p in placements) * 212 - 16
        inset = 32 if viewport["width"] <= 620 else 64
        usable_width = viewport["width"] - 2 * inset
        if usable_width <= 0:
            inset, usable_width = 0, viewport["width"]
        projected_width = width * initial["scale"]
        fits = projected_width + 2 * min(16, inset) <= viewport["width"]
        maximum = 0 if fits else projected_width - usable_width
        left = (viewport["width"] - projected_width) / 2 if fits else inset
        assert math.isclose(initial["maximumOffset"], maximum, abs_tol=.01)
        assert math.isclose(initial["x"], left, abs_tol=.01) and initial["scrollOffset"] == 0
        assert initial["y"] >= 0 and initial["y"] + height * initial["scale"] <= viewport["height"] + .01
        if not self.session.peer.collection_projects:
            assert {p["id"] for p in placements} == {r["threadId"] for r in self.session.peer.receipts.values()}
            assert maximum > 0, "dense workspace did not exercise overflow"

        def scroll(distance, expected, filename):
            self.request({"name": "overview.scroll", "distance": distance})
            state = self.stable(settled)
            camera = state["overview"]["camera"]
            assert math.isclose(camera["scrollOffset"], expected, abs_tol=.01)
            assert math.isclose(camera["x"], left - expected, abs_tol=.01)
            assert camera["y"] == initial["y"] and camera["scale"] == initial["scale"]
            save(self.session.output / filename, state)

        scroll(10000, maximum, "overview-trailing.json")
        self.request({"name": "settings.open"})
        covered = self.stable(lambda s: s["page"] == "settings")
        assert "overview.scroll" not in covered["actions"]
        self.request({"name": "settings.close"})
        restored = self.stable(settled)
        save(self.session.output / "overview-uncovered.json", restored)
        assert restored["overview"]["camera"]["scrollOffset"] == maximum
        scroll(-10000, 0, "overview-start.json")

    def overview_filters(self, thread):
        created = {receipt["threadId"] for receipt in self.session.peer.receipts.values()}
        catalog = self.session.runtime.state()
        scopes = {row["id"]: row["directoryScope"] for row in catalog["threads"] if row["id"] in created}
        assert set(scopes) == created
        # The Collection fixture deliberately creates independent reports. Check
        # their published source references before expecting every task as a card.
        sources = {row["id"]: row["view"]["relatedExecutions"] for row in catalog["applicationThreads"]
                   if row["ref"]["typeId"] == "report.document" and not row["archived"]}
        assert len(sources) == (8 if self.session.peer.collection_projects else 0)
        assert all(refs == [] for refs in sources.values()), "fixture reports must not cite the prepared tasks"
        scope = scopes[thread]
        if self.session.peer.overview_project:
            untagged = created - {thread}
            assert scope == str(self.session.peer.overview_project.resolve())
            assert all(scopes[task] == "inbox" for task in untagged)
            assert all(not row["tags"] for row in catalog["threads"] if row["id"] in untagged)
        scoped = {task for task in created if scopes[task] == scope}

        def settled(status, directory_id, expected):
            def matches(state):
                overview = state["overview"]
                cards = overview["cards"]
                agents = {card["ref"]["threadId"] for card in cards if card.get("ref", {}).get("typeId") == "agent"}
                return (state["page"] == "overview" and "overview.filters.activate" in state["actions"]
                        and state["selectedFilterId"] == directory_id and overview["status"] == status
                        and set(overview["controls"]["status"]) == {"running", "all", "completed"}
                        and not overview["controls"]["semantic"] and not overview["layingOut"]
                        and set(overview["mountedCardIds"]) == {card["id"] for card in cards}
                        and agents == expected)
            return self.stable(matches)

        def activate(group, control):
            self.request({"name": "overview.filters.activate", "group": group, "id": control})

        initial = settled("all", None, created)
        top = initial["overview"]["filters"]
        directories = {item["scope"]: item["id"] for item in top if item["kind"] == "directory"}
        assert set(directories) == set(scopes.values()) - {"inbox"}
        directory = directories[scope]
        assert set(initial["overview"]["controls"]["directory"]) == {"all", *directories.values()}
        activate("status", "running")
        running = settled("running", None, set())
        assert not running["overview"]["cards"]
        activate("directory", directory)
        empty = settled("running", directory, set())
        assert not empty["overview"]["cards"]
        activate("status", "completed")
        completed = settled("completed", directory, scoped)
        activate("directory", "all")
        global_completed = settled("completed", None, created)
        activate("status", "all")
        restored = settled("all", None, created)
        save(self.session.output / "overview-filters.json", {
            "taskScopes": scopes, "reportSources": sources, "initial": initial, "running": running, "emptyDirectory": empty,
            "completedDirectory": completed, "globalCompleted": global_completed, "restored": restored})

    def read(self, thread, initial, followup):
        overview = self.stable(lambda s: s["page"] == "overview" and s["runtimeAvailable"])
        target = next(t for t in overview["threads"] if t["threadId"] == thread)
        self.request({"name": "thread.open", "threadId": thread, "typeId": target["typeId"]})
        save(self.session.output / "ui-initial.json", self.stable(lambda s: self.has_turn(s, initial)))
        # External input uses the public Runtime path. Only reader navigation and
        # the mounted result are claimed as UI coverage, never composer submission.
        latest = followup()
        # The turn and its asynchronously mounted TOC have separate admission.
        # Wait for the actual history control, not just the new content seat.
        state = self.stable(lambda s: self.has_turn(s, latest) and any(
            c["role"] == "history.open" and c["value"] == "turn:" + initial
            for c in s["reading"]["controls"]))
        save(self.session.output / "ui-current.json", state)
        control = next(c for c in state["reading"]["controls"] if c["role"] == "history.open" and c["value"] == "turn:" + initial)
        self.request({"name": "reading.control", "controlId": control["id"], "handle": control["handle"],
                      "operation": "activate", "value": None})
        save(self.session.output / "ui-history.json", self.stable(lambda s: self.has_turn(s, initial, "history")))
        self.request({"name": "navigation.back"})
        save(self.session.output / "ui-return.json", self.stable(lambda s: self.has_turn(s, latest)))
        self.request({"name": "overview.show"})
        save(self.session.output / "ui-overview.json", self.stable(lambda s: s["page"] == "overview"))

    def chief_controls(self):
        overview = self.stable(lambda s: s["page"] == "overview" and "moku.note.toggle" in s["actions"])
        assert "moku.history.toggle" not in overview["actions"]
        hidden = {t["id"] for t in self.session.runtime.state()["threads"] if t.get("moku") or t.get("mokuHistory")}
        assert hidden and hidden.isdisjoint(t["threadId"] for t in overview["threads"])
        rejected = self.client.request({"name": "moku.history.toggle"})
        assert rejected["ok"] is False and rejected["error"]["code"] == "invalid_request"
        assert rejected["snapshot"]["page"] == "overview"
        self.request({"name": "moku.note.toggle"})
        note = self.stable(lambda s: s["page"] == "overview" and s["overview"]["dock"]["noteOpen"])
        self.request({"name": "moku.input.toggle"})
        composer = self.stable(lambda s: s["page"] == "overview" and s["overview"]["dock"]["inputOpen"]
                               and not s["overview"]["dock"]["noteOpen"])
        self.request({"name": "moku.input.toggle"})
        self.stable(lambda s: not s["overview"]["dock"]["inputOpen"])
        save(self.session.output / "chief-controls.json", {"note": note, "composer": composer, "rejected": rejected})

    def settings(self):
        def wait_for_chief():
            state = self.stable(lambda s: s["page"] == "settings")
            assert state["settingsSection"] == "moku", state["settingsSection"]
            assert state["settingsSections"] == ["moku", "tag.settings", "report.settings"], state["settingsSections"]

        state = self.stable()
        if state["page"] != "overview":
            self.request({"name": "overview.show"})
            self.stable(lambda s: s["page"] == "overview")
        self.request({"name": "settings.open"})
        wait_for_chief()

        def presets(state):
            return {c["id"].removeprefix("moku.routingPreset."): c for c in state["settings"]["controls"]
                    if c["id"].startswith("moku.routingPreset.") and c["enabled"] and not c["pending"]}

        state = self.stable(lambda s: len(presets(s)) == 4)
        options = presets(state)
        expected = "performance" if options["economy"]["value"] else "economy"
        control = options[expected]
        save(self.session.output / "settings-before.json", state)
        self.request({"name": "settings.control", "controlId": control["id"], "handle": control["handle"],
                      "operation": "activate", "value": None})
        state = self.stable(lambda s: expected in presets(s) and presets(s)[expected]["value"] is True)
        save(self.session.output / "settings-edited.json", state)
        self.request({"name": "settings.close"})
        self.stable(lambda s: s["page"] == "overview")
        persisted = self.session.runtime.state()
        actual = persisted["settings"]["moku"]["routingPreset"]
        save(self.session.output / "settings-persisted.json", {"expected": expected, "actual": actual,
             "revision": persisted["settingsRevision"]})
        assert actual == expected, "mounted preset did not persist through public state:load"
        self.request({"name": "settings.open"})
        wait_for_chief()
        save(self.session.output / "settings-reopened.json",
             self.stable(lambda s: expected in presets(s) and presets(s)[expected]["value"] is True))
        self.request({"name": "settings.close"})
        self.stable(lambda s: s["page"] == "overview")
