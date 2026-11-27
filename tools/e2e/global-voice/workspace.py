"""Exercise the signed Chief.app with a fresh profile and macOS mouse events scoped to its foreground window."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
from gate.ux import ui_lease
sys.path.insert(0, str(ROOT / "tools/e2e"))
from report import sha256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    args = parser.parse_args()
    bundle = args.app.resolve(strict=True)
    binary = bundle / "Contents/MacOS/Chief"
    runtime = bundle / "Contents/MacOS/chief-runtime"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
    contents = bundle / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    build = json.loads((contents / "Resources/build-provenance.json").read_text())
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if (info["CFBundleIdentifier"] != "com.mokusei.desktop" or build.get("channel") != "production"
            or build.get("sourceCommit") != revision):
        parser.error("Build the production app from this checkout with make pack before replaying it.")
    report = {"revision": build["sourceCommit"], "sourceDirty": build["sourceDirty"], "buildProvenance": build,
              "driverDirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT)),
              "executableSHA256": sha256(binary), "runtimeSHA256": sha256(runtime),
              "frameworkSHA256": sha256(contents / "Frameworks/LiveKitWebRTC.framework/LiveKitWebRTC"),
              "steps": [], "passed": False}
    with tempfile.TemporaryDirectory(prefix="chief-voice-window-") as work, ui_lease():
        root = Path(work)
        driver = root / "voice-window-driver"
        subprocess.run(["xcrun", "swiftc", str(Path(__file__).with_suffix(".swift")), "-o", str(driver)], check=True)
        profile = root / "profile"
        profile.mkdir(mode=0o700)
        (profile / "desktop-preferences.json").write_text(json.dumps({"onboardingCompleted": True}))
        app = subprocess.Popen([str(binary), "--data-dir", str(profile)], cwd=root,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 45
            while not (profile / "runtime/connection.json").is_file() and app.poll() is None and time.monotonic() < deadline:
                time.sleep(0.1)
            result = subprocess.run([str(driver), str(app.pid), str(bundle)], capture_output=True, text=True, timeout=205)
            report["steps"] = [json.loads(line) for line in result.stdout.splitlines()]
            report["passed"] = result.returncode == 0 and [s.get("step") for s in report["steps"]] == [
                "heldBar", "listening", "muted", "openedSettings", "overviewWhileMuted", "unmuted", "ended"]
            if result.stderr:
                print(result.stderr, file=sys.stderr)
        finally:
            if app.poll() is None:
                app.terminate()
                try:
                    app.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    app.kill()
                    app.wait()
            # A SIGTERM can bypass the SwiftUI Quit command. The isolated
            # profile still identifies its runtime until it has drained.
            subprocess.run([str(runtime), "stop", "--data-dir", str(profile)], check=True,
                           stdout=subprocess.DEVNULL, timeout=45)
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
