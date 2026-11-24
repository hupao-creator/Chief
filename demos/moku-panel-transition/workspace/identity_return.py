"""Record a running Agent's panel Close and an interrupted return in a private workspace."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import threading
import uuid

from capture import DEMO, ROOT, Session, completed, lease, native_lease, run, save, send, sha256, thread_state, validate, wait_for

sys.path.insert(0, str(ROOT / "tools/verification"))
from native_replay import NativeReplay


def capture(output):
    output.mkdir(parents=True, exist_ok=False)
    runtime = ROOT / ".build/e2e/chief-runtime"
    build = {"runtime": validate(runtime), "app": validate((ROOT / "app/macos/.build/debug/Chief").resolve())}
    release = threading.Event()
    started = threading.Event()

    def log(event, **details):
        with (output / "events.jsonl").open("a") as stream:
            print(json.dumps({"event": event, **details}), file=stream)

    session = Session(runtime, output, uuid.uuid4().hex, log)
    replay = NativeReplay(ROOT, "IdentityReturn", "com.chief.replay.identity-return")
    try:
        replay.compile([Path(__file__).with_name("ReadingPanelClose.swift"), Path(__file__).with_name("IdentityReturn.swift"), DEMO / "CollapseCapture.swift"])
        save(output / "build.json", {**build, "captureHostSHA256": sha256(replay.executable)})
        session.prepare()
        session.start()
        session.configure()
        peer = session.peer
        peer.count = 1
        respond = peer.respond

        def hold_followup(request):
            events = respond(request)
            if not isinstance(events, list) or not any(e.get("delta") == peer.followup_body() for e in events):
                return events

            def stream():
                yield from events[:-1]
                started.set()
                while not release.wait(.2):
                    yield {"type": "response.in_progress", "response": events[0]["response"]}
                yield events[-1]
            return stream()

        peer.respond = hold_followup
        session.runtime.invoke("moku:submit", [{"input": {"parts": [{"kind": "text",
            "text": "BENCHMARK CREATE 1 completed task. E2E " + session.nonce}]}}])
        wait_for(lambda: peer.receipts, lambda refs: len(refs) == 1, 60)
        thread = peer.receipts["bench_create_01"]["threadId"]
        first = completed(session, thread)["observation"]["latestExecution"]["executionId"]
        successor = send(session, thread, first, "BENCH ITEM 01: E2E FOLLOWUP " + session.nonce)
        if not started.wait(30):
            raise RuntimeError("The follow-up stream did not start")
        process = session.spawn([replay.executable, session.profile, thread], "identity-return")
        status = process.wait(timeout=90)
        held = thread_state(session, thread)["observation"]["latestExecution"]
        save(output / "held-execution.json", {"executionId": held["executionId"], "status": held["status"]})
        if status:
            raise RuntimeError((session.root / "identity-return.txt").read_text()[-3000:])
        if held["executionId"] != successor["executionId"] or held["status"] != "running":
            raise RuntimeError("The right-column follow-up ended or changed during capture")
        release.set()
        result = completed(session, thread, successor["executionId"])["observation"]["latestExecution"]
        save(output / "execution.json", {"followup": successor["executionId"], "after": result["status"]})
    finally:
        release.set()
        for name in ("close", "reverse"):
            directory = replay.application.parent / name
            if directory.is_dir():
                shutil.copytree(directory, output / name)
        cleanup = session.close()
        save(output / "cleanup.json", cleanup)
        replay.close()
        if not cleanup["ok"] and sys.exc_info()[0] is None:
            raise RuntimeError(f"Isolated replay cleanup failed: {cleanup}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    with lease(), native_lease():
        run(sys.executable, ROOT / "tools/e2e/build.py", "--go", "./scripts/go.sh", "--with-app")
        capture(args.output.resolve())
