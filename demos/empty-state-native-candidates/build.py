"""Build Chief Empty States as a standalone macOS app. Build never launches it."""
import argparse
from pathlib import Path
import subprocess
import sys

source = Path(__file__).resolve().parent
repo = source.parents[1]
sys.path.insert(0, str(repo / "tools/verification"))
from native_replay import NativeReplay

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--skip-build", action="store_true", help="Use this checkout's already-built Chief modules")
options = parser.parse_args()

if not options.skip_build:
    subprocess.run(
        ["xcrun", "swift", "build", "--package-path", str(repo / "app/macos"), "--product", "Chief"],
        check=True,
    )

output = repo / ".build/empty-state-native-candidates"
output.mkdir(parents=True, exist_ok=True)
replay = NativeReplay(repo, "Chief Empty States", "com.chief.demo.empty-states")
try:
    replay.compile(
        [source / name for name in ("Scenarios.swift", "Candidates.swift", "Demo.swift", "Entry.swift")],
        extra_args=["-Xlinker", "-dead_strip"],
    )
    application = output / replay.application.name
    subprocess.run(["ditto", str(replay.application), str(application)], check=True)
except subprocess.CalledProcessError as error:
    raise SystemExit(error.returncode) from None
finally:
    replay.close()
print(application)
