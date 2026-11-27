"""Build the standalone Chief Voice Mode prototype from this checkout."""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

source = Path(__file__).resolve().parent
repo = source.parents[1]
sys.path.insert(0, str(repo / "tools/verification"))
from native_replay import NativeReplay
sys.path.insert(0, str(repo / "tools/benchmarks"))
from gate.ux import native_lease

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--skip-build", action="store_true", help="Reuse current debug Chief modules")
mode = parser.add_mutually_exclusive_group()
mode.add_argument("--open", action="store_true", help="Launch the demo")
mode.add_argument("--replay", action="store_true", help="Exercise the mounted controls and capture this window")
options = parser.parse_args()
output = repo / ".build/global-voice-mode"
output.mkdir(parents=True, exist_ok=True)
with native_lease():
    driver_revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=repo))
    if not options.skip_build:
        subprocess.run(["xcrun", "swift", "build", "--package-path", str(repo / "app/macos"),
                        "--product", "Chief", "-Xswiftc", "-enable-testing"], check=True)
    with closing(NativeReplay(repo, "Chief Voice Mode", "com.chief.demo.global-voice-mode")) as replay:
        resources = replay.application / "Contents/Resources"
        shutil.copy2(source / "reply.m4a", resources)
        shutil.copy2(repo / "app/macos/build/AppIcon.icns", resources)
        plist = replay.application / "Contents/Info.plist"
        info = plistlib.loads(plist.read_bytes())
        info["CFBundleIconFile"] = "AppIcon"
        plist.write_bytes(plistlib.dumps(info))
        replay.compile(sorted(source.glob("*.swift")),
                       extra_args=["-O", "-Xlinker", "-dead_strip", "-Xlinker", "-S", "-Xlinker", "-x"])
        application = output / replay.application.name
        subprocess.run(["ditto", str(replay.application), str(application)], check=True)
        if options.replay:
            # A normal demo can already be open. LaunchServices resolves a reopen
            # by bundle ID, so give only the temporary replay its own identity.
            info["CFBundleIdentifier"] += ".replay"
            plist.write_bytes(plistlib.dumps(info))
            subprocess.run(["codesign", "--force", "--sign", "-", str(replay.application)], check=True)
            captured = replay.workspace / "evidence"
            evidence = output / "evidence"
            if subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip() != driver_revision:
                raise SystemExit("Checkout changed during the demo build.")
            dirty = dirty or bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=repo))
            status = None
            try:
                status = replay.run(["--replay", captured], timeout=70)
            finally:
                # Only a receipt from this attempt certifies the displayed frames.
                for name in ("passed.txt", "overview.png", "overview-alternate.png", "listening.png",
                             "voice-glass.mp4", "draft.png", "reply.png", "muted.png", "task.png", "restored-failure.png"):
                    (evidence / name).unlink(missing_ok=True)
                replay.export(evidence)
                shipped = application / replay.executable.relative_to(replay.application)
                report = {"revision": None if options.skip_build else driver_revision, "driverRevision": driver_revision,
                          "reusedProductionObjects": options.skip_build, "dirty": dirty,
                          "passed": status == 0 and (captured / "passed.txt").is_file(),
                          "replayBundleID": info["CFBundleIdentifier"],
                          "executableSHA256": hashlib.sha256(replay.executable.read_bytes()).hexdigest(),
                          "applicationExecutableSHA256": hashlib.sha256(shipped.read_bytes()).hexdigest()}
                (evidence / "result.json").write_text(json.dumps(report, indent=2) + "\n")
            if status or not (captured / "passed.txt").is_file():
                raise SystemExit((replay.root / "stderr.log").read_text() or "No replay pass receipt")
print(application, flush=True)
if options.open:
    subprocess.run(["open", "-n", str(application)], check=True)
