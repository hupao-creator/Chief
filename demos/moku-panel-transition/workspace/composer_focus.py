"""Replay Agent and Overview input through a private native workspace."""
import argparse
from pathlib import Path
import shutil
import sys
import threading
import uuid

from capture import ROOT, Session, completed, lease, native_lease, run, save, sha256, validate, wait_for

sys.path.insert(0, str(ROOT / "tools/verification"))
from native_replay import NativeReplay


def capture(output):
    output.mkdir(parents=True, exist_ok=False)
    runtime = ROOT / ".build/e2e/chief-runtime"
    build = {"runtime": validate(runtime), "app": validate((ROOT / "app/macos/.build/debug/Chief").resolve())}
    session = Session(runtime, output, uuid.uuid4().hex, lambda event, **details: print(event, details, flush=True))
    replay = NativeReplay(ROOT, "ComposerFocus", "com.chief.replay.composer-focus")
    release = threading.Event()
    try:
        replay.compile([Path(__file__).with_name(name) for name in ("ComposerFocus.swift", "ReadingPanelClose.swift")])
        save(output / "build.json", {**build, "replaySHA256": sha256(replay.executable)})
        session.prepare()
        session.start()
        session.configure()
        session.peer.count = 2
        respond = session.peer.respond
        bodies = {session.peer.body(index) for index in (1, 2)}

        def hold_first_turn(request):
            events = respond(request)
            if not isinstance(events, list) or not any(event.get("delta") in bodies for event in events):
                return events

            def stream():
                yield from events[:-1]
                while not release.wait(.2):
                    yield {"type": "response.in_progress", "response": events[0]["response"]}
                yield events[-1]

            return stream()

        session.peer.respond = hold_first_turn
        session.runtime.invoke("moku:submit", [{"input": {"parts": [{"kind": "text",
            "text": "BENCHMARK CREATE 2 completed tasks. E2E " + session.nonce}]}}])
        wait_for(lambda: session.peer.receipts, lambda refs: len(refs) == 2, 60)
        threads = [session.peer.receipts[key]["threadId"] for key in sorted(session.peer.receipts)]
        process = session.spawn([replay.executable, session.profile, *threads], "focus")
        if process.wait(timeout=90):
            raise RuntimeError((session.root / "focus.txt").read_text()[-4000:])
        release.set()
        for thread in threads:
            completed(session, thread)
    finally:
        release.set()
        if (session.root / "focus.txt").exists():
            shutil.copy2(session.root / "focus.txt", output / "focus.txt")
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
