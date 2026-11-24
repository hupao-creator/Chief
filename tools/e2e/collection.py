"""Exercise viewport grouping, return selection, promotion and release after archive."""
import subprocess

from adapter import wait_for
from report import save


def activate(session):
    # App.init binds the control socket before LaunchServices can deliver the
    # reopen event that presents this run's isolated window.
    def ready():
        info = subprocess.run(["/usr/bin/lsappinfo", "info", "-only", "isready", str(session.app.pid)],
                              capture_output=True, text=True, timeout=5)
        return info.stdout.strip().endswith("=true")

    wait_for(ready, bool, 20)
    bundle = session.app.args[0].rsplit("/Contents/", 1)[0]
    subprocess.run(["/usr/bin/open", "-a", bundle], check=True, timeout=10)


def enable_agent(session, agent, enabled):
    state = session.runtime.state()
    settings = state["settings"]
    entry = next(value for value in settings["pluginSettings"] if value["id"] == agent + ".settings")
    entry["value"]["enabled"] = enabled
    result = session.runtime.invoke("app:update-settings", [{"settings": settings,
                                    "expectedSettingsRevision": state["settingsRevision"]}])
    if result.get("status") == "conflict":
        raise RuntimeError("isolated agent settings conflicted")


def prepare(session):
    projects = [str(path.resolve()) for path in session.peer.collection_projects]

    def catalog():
        if session.peer.failures:
            raise RuntimeError(f"report fixture failed: {session.peer.failures}")
        return [r for r in session.runtime.state()["applicationThreads"] if r["ref"]["typeId"] == "report.document"]

    reports = wait_for(catalog, lambda rows: len(rows) >= 12, 90)
    assert [sum(r["scope"] == p for r in reports) for p in projects] == [8, 4]
    assert all(r["tags"]["semanticTags"] for r in reports)
    save(session.output / "collection-catalog.json", reports)
    return sorted(reports, key=lambda r: r["createdAt"])


def journey(desktop, reports):
    output = desktop.session.output
    folders = desktop.stable(lambda s: s["page"] == "overview" and s["overview"]["filters"])["overview"]["filters"]
    directories = [next(f for f in folders if f["kind"] == "directory" and f["scope"] == str(p.resolve()))
                   for p in desktop.session.peer.collection_projects]
    library, studio = directories

    def reports_in(scope):
        return [r["ref"] for r in reports if r["scope"] == scope]

    refs = reports_in(library["scope"])
    def overview(filter_id):
        return desktop.stable(lambda s: s["page"] == "overview" and s["selectedFilterId"] == filter_id
                              and not s["overview"]["layingOut"] and s["overview"]["cards"]
                              and set(s["overview"]["mountedCardIds"]) == {c["id"] for c in s["overview"]["cards"]})

    def observe(name, visible, expected_members, filter_id=library["id"]):
        state = overview(filter_id)
        save(output / f"collection-{name}.json", state)
        cards = state["overview"]["cards"]
        groups = [c for c in cards if "members" in c]
        assert [c["members"] for c in groups] == ([expected_members] if expected_members else [])
        singles = [c["ref"] for c in cards if "members" not in c and c["ref"]["typeId"] == "report.document"]
        assert singles == [ref for ref in visible if ref not in expected_members]
        assert all(not item["eligibility"]["defaultsToCollection"] and item["eligibility"]["collected"]
                   for group in groups for item in group["memberEligibility"])
        assert state["overview"]["camera"]["maximumOffset"] == 0
        return state

    def unread_by_folder(state):
        return {f["scope"]: f["unreadCount"] for f in state["overview"]["filters"] if f["kind"] == "directory"}

    initial = observe("initial", refs, refs[:6])
    fresh = {d["scope"]: len(reports_in(d["scope"])) + 1 for d in directories}
    assert unread_by_folder(initial) == fresh
    subset = reports_in(studio["scope"])
    desktop.request({"name": "filter.select", "filterId": studio["id"]})
    assert unread_by_folder(observe("directory", subset, subset[:2], studio["id"])) == fresh
    desktop.request({"name": "filter.select", "filterId": library["id"]})
    observe("grouped", refs, refs[:6])

    def visit(qualify):
        desktop.request({"name": "thread.open", **refs[1]})
        reader = desktop.stable(lambda s: s["page"] == "thread" and s["selectedThread"] == refs[1]
                                and s["reading"]["entranceAdmitted"])
        # Reading accrues only while the isolated reader owns the key window.
        if not reader["reading"]["foreground"]:
            activate(desktop.session)
            desktop.stable(lambda s: s["selectedThread"] == refs[1] and s["reading"]["foreground"])
        if qualify:
            wait_for(desktop.request, lambda s: s["reading"]["collectionEligibility"]["lastQualifiedAt"] is not None, 50)
        desktop.request({"name": "overview.show"})

    visit(False)
    closed = observe("closed", refs, refs[:6])
    group = next(c for c in closed["overview"]["cards"] if "members" in c)
    assert group["ref"] == refs[1]
    visit(True)
    ranked = [ref for ref in refs if ref != refs[1]]
    returned = observe("return", refs, ranked[:6])
    promoted = next(c for c in returned["overview"]["cards"] if c.get("id") == refs[1]["threadId"])
    assert promoted["collectionEligibility"]["lastQualifiedAt"]
    after_read = fresh.copy()
    after_read[library["scope"]] -= 1
    assert unread_by_folder(returned) == after_read

    def archive(ref, archived):
        desktop.session.runtime.invoke("application:archive", [ref, archived])
        desktop.stable(lambda s: any(ref in c.get("members", [c.get("ref")])
                                     for c in s["overview"]["cards"]) != archived)

    archive(refs[-1], True)
    observe("one-removed", refs[:-1], ranked[:5])
    for ref in reversed(refs[3:-1]):
        archive(ref, True)
    observe("released", refs[:3], [])
    for ref in refs[3:]:
        archive(ref, False)
    assert unread_by_folder(observe("restored", refs, ranked[:6])) == after_read
