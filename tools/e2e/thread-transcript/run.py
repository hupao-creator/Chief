"""Replay offline native protocol frames through the installed macOS thread readers."""
import argparse
from contextlib import contextmanager, ExitStack
import json
import os
import shutil
from pathlib import Path
import platform
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT))
from tools.benchmarks.gate.runner import lease
from tools.verification.native_replay import NativeReplay


@contextmanager
def replay_lease(replay=None):
    deadline = time.monotonic() + 600
    while True:
        with ExitStack() as stack:
            try:
                stack.enter_context(lease())
                if replay:
                    replay.acquire()
            except RuntimeError as error:
                if not isinstance(error.__context__, BlockingIOError) or time.monotonic() >= deadline:
                    raise
                if replay and replay.lock:
                    replay.lock.close()
                    replay.lock = None
            else:
                yield
                return
        time.sleep(2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    output = parser.parse_args().output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT)),
              "os": platform.platform(), "status": "failed"}
    replay = None
    try:
        with replay_lease():
            package = ROOT / "app/macos"
            for pin in json.loads((package / "Package.resolved").read_text())["pins"]:
                checkout = package / ".build/checkouts" / pin["identity"]
                if not checkout.is_dir():
                    raise RuntimeError(f"Offline replay requires the cached {pin['identity']} checkout")
            subprocess.run(["xcrun", "swift", "build", "--package-path", str(package),
                            "--disable-automatic-resolution", "--skip-update"], cwd=ROOT, check=True)
            replay = NativeReplay(ROOT, "ThreadTranscriptReplay", "dev.chief.replay.thread-transcript")
            data = replay.workspace / "samples"
            data.mkdir()
            subprocess.run(["./scripts/go.sh", "run", "-tags", "chief_transcript_replay",
                            "./tools/e2e/thread-transcript", str(data)], cwd=ROOT, check=True,
                           env=dict(os.environ, GOPROXY="off"))
            shutil.copytree(data, output / "samples")
            replay.compile([HERE / "Replay.swift", HERE / "ConversationReaders.swift"], extra_args=["-package-name", "macos"])
        # Leave both shared locks available while an existing graphical or
        # performance campaign finishes. All production objects are staged.
        with replay_lease(replay):
            result = replay.root / "result.json"
            if replay.run([data, result], launch_services=False):
                raise RuntimeError((replay.root / "stdout.log").read_text())
        report["samples"] = len(json.loads(result.read_text()))
        report["status"] = "passed"
    except Exception as error:
        report["error"] = str(error)[:8000]
        raise
    finally:
        if replay:
            replay.export(output)
            replay.close()
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
