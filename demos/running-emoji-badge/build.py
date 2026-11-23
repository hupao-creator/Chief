"""Build the standalone badge comparison using this checkout's native components."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import time

source = Path(__file__).resolve().parent
repo = source.parents[1]
sys.path.insert(0, str(repo / "tools/verification"))
from native_replay import NativeReplay

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--skip-build", action="store_true", help="Reuse current native modules")
parser.add_argument("--capture", action="store_true", help="Record the mounted window switching states")
parser.add_argument("--open", action="store_true", help="Launch the interactive app")
options = parser.parse_args()
if not options.skip_build:
    subprocess.run(["xcrun", "swift", "build", "--package-path", str(repo / "app/macos"),
                    "--product", "Chief"], check=True)

output = repo / ".build/running-emoji-badge"
output.mkdir(exist_ok=True, parents=True)
replay = NativeReplay(repo, "ThreadBadgeDemo", "com.chief.demo.running-emoji-badge")
try:
    replay.compile([source / name for name in ("Badge.swift", "BadgeFinish.swift", "Comparison.swift", "Recording.swift", "main.swift")],
                   extra_args=["-Xlinker", "-dead_strip"])
    application = output / replay.application.name
    subprocess.run(["ditto", str(replay.application), str(application)], check=True)
    if options.capture:
        print("Waiting for the native replay session…", flush=True)
        while True:
            try:
                replay.acquire()
                break
            except RuntimeError as error:
                if not isinstance(error.__context__, BlockingIOError):
                    raise
                replay.lock.close()
                time.sleep(1)
        status = replay.run(["--capture"], timeout=40)
        if status:
            raise RuntimeError((replay.root / "stderr.log").read_text())
        shutil.copy2(replay.workspace / "preview.mp4", output / "preview.mp4")
finally:
    replay.close()
print(application, flush=True)
if options.open:
    subprocess.run(["open", "-n", str(application)], check=True)
