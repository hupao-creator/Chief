"""Reopen the normal Chief window against an isolated, populated profile."""
import json

from adapter import wait_for
from collection import activate, enable_agent
from report import save


def launch(session, app):
    socket = session.root / "ui.sock"
    session.app = session.spawn([app, "--runtime", session.binary, "--data-dir", session.profile,
                                 "--automation-socket", socket], "app")
    wait_for(socket.exists, bool, 40)
    activate(session)


def journey(desktop, app, send, thread_state):
    session = desktop.session
    preferences = session.profile / "desktop-preferences.json"
    review, plan, ship, inbox = (session.peer.receipts[f"bench_create_{i:02}"]["threadId"] for i in range(1, 5))
    project = {review, plan, ship}
    scope = str(session.peer.overview_project.resolve())
    evidence = {"projectScope": scope, "projectThreads": sorted(project), "inboxThread": inbox, "stages": {}}

    def record(stage, snapshot):
        evidence["stages"][stage] = {"pid": session.app.pid, "snapshot": snapshot,
                                    "preference": json.loads(preferences.read_text())["overviewSelection"]}
        save(session.output / "overview-spaces.json", evidence)

    def capture(stage, scope, kind, expected, *, first=False, tag=None, top_count=None, status="all"):
        def ready(state):
            overview = state["overview"]
            if state["page"] != "overview" or not overview["filters"]:
                return False
            top = overview["filters"]
            if first:
                assert top[0]["scope"] == scope and top[0]["kind"] == kind, top
            candidates = top + [child for folder in top for child in folder["children"]]
            selected = next(f for f in candidates if f["scope"] == scope and f["kind"] == kind
                            and (tag is None or f["tag"] == tag))
            # Compare on the first observable nonempty Overview, before waiting
            # for the canvas and asynchronous button registrations to settle.
            assert state["selectedFilterId"] == selected["id"], state
            assert overview["status"] == status
            rail_id = selected["id"] if kind == "semantic" else None
            if scope == "inbox" or status == "running":
                rail_id = status
            assert overview["selectedRailId"] == rail_id
            assert {card["ref"]["threadId"] for card in overview["cards"]} == expected, overview
            status_buttons = {"running", "all", "completed"} if scope == "inbox" else {"running"}
            return (selected["id"] in overview["controls"][kind] and set(overview["controls"]["status"]) == status_buttons
                    and not overview["layingOut"]
                    and set(overview["mountedCardIds"]) == expected
                    and (top_count is None or len(top) == top_count))

        snapshot = desktop.stable(ready)
        record(stage, snapshot)
        saved = evidence["stages"][stage]["preference"]
        assert saved["scope"] == scope and saved["kind"] == kind
        assert bool(saved.get("runningTag")) == (scope != "inbox" and status == "running")
        if tag is not None:
            assert saved["tag"] == tag
        return snapshot

    def choose(filter):
        desktop.request({"name": "overview.filters.activate", "group": filter["kind"], "id": filter["id"]})

    def stop():
        desktop.close()
        session.stop(session.app, "app")
        (session.root / "ui.sock").unlink(missing_ok=True)

    def reopen():
        old_pid = session.app.pid
        launch(session, app)
        assert session.app.pid != old_pid
        desktop.reconnect()

    def archive(thread, archived):
        session.runtime.invoke("thread:set-archived", [thread, archived])

    initial = capture("firstLaunch", scope, "directory", project, first=True)
    folder, inbox_tag = initial["overview"]["filters"]
    assert inbox_tag["scope"] == "inbox" and inbox_tag["kind"] == "semantic"
    assert folder["children"][0]["tag"] == "Plan work"
    namesake = next(child for child in folder["children"] if child["tag"] == folder["tag"])
    choose(namesake)
    capture("folderNamesake", scope, "semantic", {ship}, tag=folder["tag"])
    choose(folder)
    capture("namesakeToFolder", scope, "directory", project)

    desktop.request({"name": "overview.filters.activate", "group": "status", "id": "running"})
    capture("emptyRunning", scope, "directory", set(), status="running")
    stop()
    reopen()
    capture("runningRelaunch", scope, "directory", set(), status="running")
    choose(inbox_tag)
    capture("inboxAfterRunning", "inbox", "semantic", {inbox}, tag=inbox_tag["tag"])
    choose(folder)
    capture("runningFolderReentry", scope, "directory", set(), status="running")
    choose(folder)
    capture("runningToFolder", scope, "directory", project)

    # Reopen with the desktop preference fields that predate the built-in tag.
    stop()
    legacy = json.loads(preferences.read_text())
    del legacy["overviewRunningDirectories"]
    preferences.write_text(json.dumps(legacy))
    reopen()
    capture("legacyFolderRelaunch", scope, "directory", project)
    choose(inbox_tag)
    capture("inboxFirstEntry", "inbox", "semantic", {inbox}, tag=inbox_tag["tag"])
    choose(folder)
    capture("firstFolderEntry", scope, "semantic", {plan}, tag="Plan work")
    choose(next(tag for tag in folder["children"] if tag["tag"] == "Review work"))
    capture("leftTag", scope, "semantic", {review}, tag="Review work")
    stop()
    reopen()
    capture("leftTagRelaunch", scope, "semantic", {review}, tag="Review work")
    choose(folder)
    capture("folderExpanded", scope, "directory", project)
    choose(inbox_tag)
    capture("inbox", "inbox", "semantic", {inbox}, tag=inbox_tag["tag"])
    choose(folder)
    capture("folderReentry", scope, "semantic", {review}, tag="Review work")
    choose(inbox_tag)
    capture("inboxBeforeRelaunch", "inbox", "semantic", {inbox}, tag=inbox_tag["tag"])
    stop()
    reopen()
    capture("inboxRelaunch", "inbox", "semantic", {inbox}, tag=inbox_tag["tag"])
    archive(review, True)
    desktop.stable(lambda state: any(f["id"] == folder["id"] and f["count"] == 2
                                     for f in state["overview"]["filters"]))
    choose(folder)
    capture("unavailableFolderTag", scope, "semantic", {plan}, tag="Plan work")
    choose(inbox_tag)
    capture("inboxBeforeEmpty", "inbox", "semantic", {inbox}, tag=inbox_tag["tag"])

    stop()
    for thread in (plan, ship, inbox):
        archive(thread, True)
    reopen()
    empty = desktop.stable(lambda state: state["runtimeAvailable"] and not state["overview"]["filters"])
    assert empty["selectedFilterId"] is None and not empty["overview"]["cards"]
    record("emptyRelaunch", empty)
    assert evidence["stages"]["emptyRelaunch"]["preference"] == evidence["stages"]["inboxBeforeEmpty"]["preference"]
    archive(inbox, False)
    def untagged_view(cards):
        return desktop.stable(lambda state: state["page"] == "overview" and state["runtimeAvailable"]
                              and state["selectedFilterId"] is None and not state["overview"]["filters"]
                              and state["overview"]["status"] == "running" and not state["overview"]["layingOut"]
                              and set(state["overview"]["mountedCardIds"]) == cards)
    restored_inbox = thread_state(session, inbox)
    assert not restored_inbox["tags"] and not restored_inbox.get("archived")
    record("noRunning", untagged_view(set()))
    previous = restored_inbox["observation"]["latestExecution"]["executionId"]
    prompt = f"BENCH ITEM 04: E2E FOLLOWUP {session.nonce} E2E STOP {session.nonce}"
    run = send(session, inbox, previous, prompt)["executionId"]
    wait_for(lambda: session.peer.holds, bool, 30)
    active = thread_state(session, inbox)
    assert not active["tags"] and active["observation"]["latestExecution"]["executionId"] == run
    assert active["observation"]["latestExecution"]["status"] == "running"
    record("runningBeforeTag", untagged_view({inbox}))
    enable_agent(session, "tag", True)
    capture("tagArrived", "inbox", "semantic", {inbox}, tag=inbox_tag["tag"])
    tagged = thread_state(session, inbox)
    assert tagged["tags"] == [inbox_tag["tag"]]
    assert tagged["observation"]["latestExecution"]["executionId"] == run
    assert tagged["observation"]["latestExecution"]["status"] == "running"
    session.runtime.invoke("thread:interrupt", [{"threadId": inbox, "expectedCancellationId": tagged["cancellationId"]}])
    wait_for(lambda: thread_state(session, inbox), lambda r: r["observation"]["latestExecution"]["status"] == "interrupted")
    for thread in sorted(project):
        archive(thread, False)
    wait_for(session.runtime.state, lambda state: project <= {
        row["id"] for row in state["threads"] if row.get("tags")})
    enable_agent(session, "tag", False)
    restored = capture("moreSpacesArrived", "inbox", "semantic", {inbox}, tag=inbox_tag["tag"], top_count=2)
    assert restored["overview"]["filters"][0]["id"] == folder["id"]

    stop()
    cached = json.loads((session.profile / "client-reading-cache/state.json").read_text())["value"]
    assert any(row["id"] == inbox and row.get("tags") and not row.get("archived") for row in cached["threads"])
    archive(inbox, True)
    live = session.runtime.state()
    assert next(row for row in live["threads"] if row["id"] == inbox)["archived"] is True
    evidence["fallbackCatalog"] = {"cachedRevision": cached["revision"], "runtimeRevision": live["revision"]}
    reopen()
    capture("unavailableRelaunch", scope, "directory", project, first=True)

    def fork(thread):
        return session.runtime.invoke("thread:fork", [{"threadId": thread, "request": {}}])["threadId"]

    # A fork inherits its source's tag but has its own first assignment.
    review_tag = next(tag for tag in folder["children"] if tag["tag"] == "Review work")
    desktop.request({"name": "settings.open"})
    desktop.stable(lambda state: state["page"] == "settings")
    inherited = fork(review)
    covered = desktop.stable(lambda state: state["page"] == "settings" and state["selectedFilterId"] == review_tag["id"])
    record("taggedForkBehindSettings", covered)
    desktop.request({"name": "settings.close"})
    capture("taggedFork", scope, "semantic", {inherited, review}, tag="Review work")

    # Restore clears the inherited label. Reopen while it is unassigned, then
    # reclassify it alongside two never-tagged forks in one assign_threads call.
    archive(inherited, True)
    archive(inherited, False)
    first, second = fork(inherited), fork(inherited)
    assigned = {inherited: "Review work", first: folder["tag"], second: "Plan work"}
    peer = session.peer
    peer.tag_names.update(assigned)
    peer.tagged_ids.update(assigned)
    choose(folder)
    capture("unassignedForks", scope, "directory", project)
    stop()
    reopen()
    capture("beforeFirstAssignments", scope, "directory", project, first=True)
    enable_agent(session, "tag", True)
    classified = wait_for(session.runtime.state, lambda state: {
        row["id"]: row["tags"][0] for row in state["threads"] if row["id"] in assigned and row["tags"]
    } == assigned)
    winner = next(row for row in classified["threads"] if row["id"] in (first, second))
    tag = winner["tags"][0]
    expected = {row["id"] for row in classified["threads"] if row["id"] in project | assigned.keys()
                and tag in row["tags"]}
    desktop.stable(lambda state: set(state["overview"]["mountedCardIds"]) == expected)
    capture("firstAssignmentsInBatch", scope, "semantic", expected, tag=tag)
    enable_agent(session, "tag", False)

    # Give the same three tasks fresh classifications after an App restart.
    # A manual folder choice survives all three updates.
    choose(folder)
    for thread in assigned:
        archive(thread, True)
        archive(thread, False)
    desktop.stable(lambda state: set(state["overview"]["mountedCardIds"]) == project)
    stop()
    reopen()
    capture("clearedTagsRelaunch", scope, "directory", project)
    enable_agent(session, "tag", True)
    wait_for(session.runtime.state, lambda state: assigned.keys() <= {
        row["id"] for row in state["threads"] if row["tags"]})
    all_threads = project | assigned.keys()
    desktop.stable(lambda state: set(state["overview"]["mountedCardIds"]) == all_threads)
    capture("reclassificationKeepsFolder", scope, "directory", all_threads)

    archive(inbox, False)
    desktop.stable(lambda state: any(f["id"] == inbox_tag["id"] for f in state["overview"]["filters"]))
    reader = {"threadId": plan, "typeId": "agent"}
    desktop.request({"name": "thread.open", **reader})
    desktop.stable(lambda state: state["selectedThread"] == reader and state["reading"]["entranceAdmitted"])
    inbox_fork = fork(inbox)
    covered = desktop.stable(lambda state: state["page"] == "thread" and state["selectedThread"] == reader
                             and state["selectedFilterId"] == inbox_tag["id"])
    record("inboxAssignmentBehindReader", covered)
    desktop.request({"name": "overview.show"})
    capture("readerReturnsToInboxTag", "inbox", "semantic", {inbox, inbox_fork}, tag=inbox_tag["tag"])
