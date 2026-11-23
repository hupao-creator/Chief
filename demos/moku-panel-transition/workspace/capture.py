"""Record the joint Chief bar regression on one build in isolated macOS windows."""
import argparse
from contextlib import contextmanager
import json
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
import uuid

HERE = Path(__file__).resolve().parent
DEMO = HERE.parent
ROOT = DEMO.parents[1]
sys.path[:0] = [str(ROOT / "tools/e2e"), str(ROOT / "tools/benchmarks"), str(ROOT / "tools/native-interaction"), str(ROOT)]
from adapter import wait_for
from build import validate
from collection import activate
from desktop import Desktop
from gate.runner import lease
from gate.ux import native_lease
from lifecycle import Session
from operator_input import bundle
from provider import declared_tools, find_tool
from report import save, sha256
from run import completed, send, thread_state
from tools.benchmarks.build import build as build_collector


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), cwd=ROOT, check=True, **kwargs)


@contextmanager
def movie(driver, target, directory):
    directory.mkdir()
    with (directory / "capture.log").open("w") as log:
        recorder = subprocess.Popen([driver, target, "record", directory], stdout=log, stderr=log)
        try:
            wait_for(lambda: (directory / "ready.json").exists() or recorder.poll() is not None, bool, 15)
            if recorder.poll() is not None:
                raise RuntimeError(f"Window capture failed in {directory}")
            time.sleep(.4)
            yield
            time.sleep(.6)
        finally:
            (directory / "stop").touch()
            try:
                if recorder.wait(timeout=12):
                    raise RuntimeError(f"Window capture failed in {directory}")
            except subprocess.TimeoutExpired:
                recorder.kill()
                recorder.wait()
                raise


def workspace(session, app, driver, collector, output):
    release = threading.Event()
    session.prepare()
    epoch = session.start()
    session.configure()
    session.peer.count = 2
    respond = session.peer.respond

    def held_response(request):
        events = respond(request)
        hold_chief = find_tool(declared_tools(request), "create_thread") and len(session.peer.receipts) >= 2
        hold_followup = isinstance(events, list) and any(e.get("delta") == session.peer.followup_body() for e in events)
        if not (hold_chief or hold_followup):
            return events

        def stream():
            # Let the Execution sidecard display the reply while its run is
            # still active. Only the terminal event waits for the return.
            split = len(events) - 1 if hold_followup else 1
            yield from events[:split]
            while not release.wait(.12):
                yield {"type": "response.in_progress", "response": events[0]["response"]}
            yield from events[split:]
        return stream()

    session.peer.respond = held_response
    exe = bundle(app, session)
    session.app = session.spawn([exe, "--runtime", session.binary, "--data-dir", session.profile,
        "--automation-socket", session.root / "ui.sock", "--benchmark-scenario", "overview"], "app")
    pid = session.app.pid
    wait_for(lambda: (session.root / "ui.sock").exists(), bool, 40)
    activate(session)
    desktop = Desktop(session)

    target = output / "input-target.json"

    def inspect(label):
        ax = json.loads(run(collector, "inspect", pid, capture_output=True).stdout)
        assert ax["process"]["pid"] == pid and ax["windowID"] == window_id and ax["active"] and not ax["axTruncated"]
        save(output / (label + ".json"), ax)
        return ax["accessibility"]

    def item(rows, identifier):
        return next(r for r in rows if r.get("AXIdentifier") == identifier)

    def act(action, *args):
        assert session.app.poll() is None and session.process.poll() is None
        run(driver, target, action, *args, timeout=8)
        session.event("input", action=action, arguments=list(args))

    def point(action, row):
        b = row["bounds"]
        label = [row.get("AXIdentifier") or row["AXDescription"]] if action in {"press", "focus"} else []
        act(action, b["x"] + b["width"] / 2, b["y"] + b["height"] / 2, *label)

    def stable(predicate):
        desktop.reconnect()
        return desktop.stable(predicate)

    def submit():
        session.runtime.invoke("moku:submit", [{"input": {"parts": [{"kind": "text",
            "text": f"BENCHMARK CREATE 2 completed tasks. E2E {session.peer.nonce}"}]}}])

    def chief():
        return next(t for t in session.runtime.state()["threads"] if t.get("moku"))

    overview = lambda s: s["page"] == "overview" and not s["overview"]["dock"]["inputOpen"]
    try:
        stable(lambda s: s["runtimeAvailable"])
        bounds = dict(x=100, y=26, width=1885, height=1125)
        def initial_window():
            # SwiftUI can finish mounting before ScreenCaptureKit lists its first window.
            probe = subprocess.run([collector, "inspect", str(pid)], capture_output=True, text=True, timeout=8)
            if probe.returncode:
                (output / "initial-inspect.stderr").write_text(probe.stderr)
                return None
            return json.loads(probe.stdout)
        prepared = wait_for(initial_window, bool, 10)
        assert prepared["active"] and prepared["process"]["pid"] == pid
        window_id = prepared["windowID"]
        save(target, dict(pid=pid, windowID=window_id, bounds=bounds, nonce=session.nonce,
                          profile=session.profile.as_uri(), executable=exe.resolve().as_uri(),
                          runtimePID=session.process.pid, epoch=epoch))
        act("prepare")
        assert next(r for r in inspect("prepared") if r.get("AXIdentifier") == "workspace")["bounds"] == bounds
        with movie(driver, target, output / "first-card"):
            submit()
            wait_for(lambda: session.peer.receipts, lambda v: len(v) == 2, 60)
            stable(overview)
            rows = inspect("dispatch")
            assert item(rows, "moku-dispatch-status")
            point("press", item(rows, "moku-open-input"))
            stable(lambda s: s["overview"]["dock"]["inputOpen"])
            time.sleep(.7)
            rows = inspect("dispatch-editor")
            assert item(rows, "moku-stop") and all(r.get("AXIdentifier") != "moku-dispatch-status" for r in rows)
            act("compose")
            time.sleep(.7)
            # The model folds before SwiftUI republishes the compact AX controls.
            # Keep recording through the handoff and wait for their actual seats.
            compact = wait_for(lambda: inspect("compact"), lambda rows: {
                "moku-open-input", "moku-stop"
            } <= {r.get("AXIdentifier") for r in rows}, 5)
            point("hover", item(compact, "moku-open-input"))
            point("focus", item(compact, "moku-stop"))
            time.sleep(.5)
            act("compose")
            time.sleep(.75)
            act("reverse")
            time.sleep(.75)
            stop = item(inspect("stop"), "moku-stop")
            before = chief()["observation"]["latestExecution"]
            assert session.peer.nonce in before["summary"] and before["status"] == "running"
            point("press", stop)
            after = wait_for(chief, lambda t: t["observation"]["latestExecution"]["status"] == "interrupted", 8)
            assert before["executionId"] == after["observation"]["latestExecution"]["executionId"]
            save(output / "stop-result.json", dict(before=before, after=after["observation"]["latestExecution"]))
        release.set()
        for receipt in session.peer.receipts.values():
            completed(session, receipt["threadId"])
        act("escape")
        state = stable(overview)
        card = max(state["overview"]["placements"], key=lambda p: p["column"])["id"]
        release.clear()
        submit()
        wait_for(chief, lambda t: bool(t.get("cancellationId")), 8)
        with movie(driver, target, output / "overview"):
            for closer in ["escape", "outside"]:
                point("click", item(inspect("before-" + closer), "moku-open-input"))
                time.sleep(.75)
                stable(lambda s: s["overview"]["dock"]["inputOpen"])
                if closer == "escape":
                    act("escape")
                else:
                    act("click", 650, 850)
                time.sleep(.7)
                stable(overview)
            act("compose")
            time.sleep(.7)
            act("reverse")
            time.sleep(.7)
            act("compose")
            time.sleep(.7)
        stable(overview)
        release.set()
        for i in range(2):
            rows = inspect(f"before-reader-{i}")
            with movie(driver, target, output / f"reader-{i}"):
                point("click", item(rows, "overview-card-" + card))
                stable(lambda s: s["page"] == "thread" and s["overview"]["dock"]["inputOpen"])
                time.sleep(.65)
                rows = inspect(f"reader-open-{i}")
                dock = item(rows, "moku-capsule")["bounds"]
                assert dock["width"] == 560 and abs(dock["x"] + 280 - 1042.5) < 2
                point("click", next(r for r in rows if r.get("AXDescription") in ["关闭 Thread", "Close thread"]))
                stable(overview)
                time.sleep(.65)
        # A completed result in main and its running successor in Execution
        # place the editor beneath the right column in the real workspace.
        previous = completed(session, card)["observation"]["latestExecution"]["executionId"]
        release.clear()
        successor = send(session, card, previous, "BENCH ITEM 01: E2E FOLLOWUP " + session.nonce)
        point("click", item(inspect("before-execution"), "overview-card-" + card))
        stable(lambda s: s["page"] == "thread" and s["overview"]["dock"]["inputOpen"])
        time.sleep(.65)
        rows = inspect("execution-open")
        dock = item(rows, "moku-capsule")["bounds"]
        assert dock["x"] > bounds["x"] + bounds["width"] / 2 and dock["width"] > 168
        active = thread_state(session, card)["observation"]["latestExecution"]
        assert active["executionId"] == successor["executionId"] and active["status"] == "running"
        with movie(driver, target, output / "execution-return"):
            point("click", next(r for r in rows if r.get("AXDescription") in ["关闭 Thread", "Close thread"]))
            stable(overview)
            time.sleep(.65)
        resting = item(inspect("execution-resting"), "moku-capsule")["bounds"]
        assert resting["width"] == 168 and abs(resting["x"] + 84 - (bounds["x"] + bounds["width"] / 2)) < 2
        release.set()
        finished = completed(session, card, successor["executionId"])["observation"]["latestExecution"]
        save(output / "execution-return-result.json", dict(thread=card, before=active, after=finished))
        # No input is posted by a probe. Exercise the same checks used before
        # each event, including the foreground loss after withdrawing this app.
        recorded = json.loads(target.read_text())
        for key, value in [("windowID", 0), ("runtimePID", -1), ("nonce", "wrong-bundle")]:
            mismatch = output / (key + "-mismatch.json")
            save(mismatch, {**recorded, key: value})
            check = subprocess.run([driver, mismatch, "probe"], capture_output=True, text=True)
            assert check.returncode == 1 and check.stderr.strip(), "an unrelated target was accepted"
            session.event("input-rejected", mismatch=key, reason=check.stderr.strip())
        act("withdraw")
        wait_for(lambda: subprocess.run([driver, target, "probe"], capture_output=True, text=True),
                 lambda probe: probe.returncode == 1 and "lost focus" in probe.stderr, 4)
        session.event("input-rejected", mismatch="focus")
    finally:
        release.set()
        desktop.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    output = parser.parse_args().output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    runtime = ROOT / ".build/e2e/chief-runtime"
    app = (ROOT / "app/macos/.build/debug/Chief").resolve()
    with lease(), native_lease():
        run(sys.executable, ROOT / "tools/e2e/build.py", "--go", "./scripts/go.sh", "--with-app")
        build = dict(app=validate(app), runtime=validate(runtime))
        run(sys.executable, DEMO / "build.py", "--skip-build")
        preview = Path((ROOT / ".build/moku-panel-evidence/app-path.txt").read_text())
        executable = preview / "Contents/MacOS/MokuPanelPreview"
        driver = output / "window-replay"
        run("xcrun", "swiftc", "-parse-as-library", HERE / "WindowReplay.swift", "-o", driver)
        collector = build_collector(output / "tools") / "collector"
        save(output / "build.json", dict(**build, previewSHA256=sha256(executable),
            driverSHA256=sha256(driver), collectorSHA256=sha256(collector)))
        for name, folder in [("overview", "overview-zh-Hans-motion-scene"), ("agent-entrance", "agent-entrance")]:
            run(executable, "--capture-" + name, timeout=140)
            shutil.move(preview.parent / folder, output / folder)
        def event(phase, **values):
            with (output / "events.jsonl").open("a") as stream:
                print(json.dumps(dict(event=phase, uptime=time.monotonic(), **values)), file=stream)
        session = Session(runtime, output, uuid.uuid4().hex, event)
        try:
            workspace(session, app, driver, collector, output)
        finally:
            cleanup = session.close()
            save(output / "cleanup.json", cleanup)
            assert cleanup["ok"], cleanup
    # The first-run journey owns the same desktop and performance leases itself.
    run(sys.executable, ROOT / "tools/e2e/run.py", "run", "--suite", "onboarding", "--runtime", runtime,
        "--app", app, "--output", output / "onboarding", "--desktop-lease", "/private/tmp/mokusei-ui-verification.lock",
        "--desktop-owner", "chief-bar-motion")


if __name__ == "__main__":
    main()
