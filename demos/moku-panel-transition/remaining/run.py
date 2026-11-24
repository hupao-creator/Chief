"""Run the nonactivating Chief Bar replay against this checkout's native modules."""
import argparse
from contextlib import contextmanager, ExitStack
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT))
from tools.benchmarks.gate.runner import lease
from tools.benchmarks.gate.ux import native_lease
from tools.verification.native_replay import NativeReplay

BASE = "9b61af09226e12e0c414273cf077154815e01e0a"
SCENE = "app/macos/Sources/Host/MokuScene"


def git(*arguments):
    return subprocess.check_output(["git", *arguments], cwd=ROOT)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


@contextmanager
def exclusive():
    deadline = time.monotonic() + 600
    while True:
        with ExitStack() as locks:
            try:
                locks.enter_context(lease())
                locks.enter_context(native_lease())
            except (RuntimeError, FileExistsError, BlockingIOError) as error:
                if isinstance(error, RuntimeError) and not isinstance(error.__cause__, BlockingIOError):
                    raise
                if time.monotonic() >= deadline:
                    raise
            else:
                yield
                return
        time.sleep(2)


def reference(replay):
    # Compile the original controller and eyes independently. Seeking changes
    # only the replay clock; production geometry and rasterization stay intact.
    paths = []
    for name in ("NativeMokuCapsuleBlink", "NativeMokuRunningGeometry", "NativeMokuCharacterMotion"):
        source = git("show", f"{BASE}:{SCENE}/{name}.swift").decode()
        for symbol in ("NativeMokuRunningGeometry", "NativeMokuBlinkingEyes", "NativeMokuCapsuleBlinkTiming", "NativeMokuBlinkLayers",
                       "NativeMokuCharacterPose", "NativeMokuCharacterMotion", "NativeMokuCharacterSeat",
                       "NativeMokuCharacterSurface", "NativeMokuCharacterCanvas"):
            source = source.replace(symbol, symbol.replace("NativeMoku", "Reference"))
        if name.endswith("Motion"):
            start = source.index("struct NativeMokuCharacterInput")
            source = source[:start] + source[source.index("struct ReferenceCharacterPose", start):]
            source += """
extension ReferenceCharacterMotion {
    func seek(milliseconds: Double) {
        clock = transitionAt + milliseconds
        pose = sample(at: clock)
        visibilityChanged()
        link?.isPaused = true
    }
}
"""
        path = replay.root / ("Reference" + name + ".swift")
        path.write_text("@testable import ChiefUI\n" + source)
        paths.append(path)
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("cases", nargs="+", choices=["eyes", "routes", "routes-reduced", "tool-feedback", "orbit-fade", "orbit-gaze", "routes-offscreen", "timers", "timers-reduced", "tag-unread"])
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    with exclusive():
        subprocess.run(["xcrun", "swift", "build", "--package-path", "app/macos", "--product", "Chief",
                        "--only-use-versions-from-resolved-file"], cwd=ROOT, check=True)
        replay = NativeReplay(ROOT, "ChiefBarRemainingReplay", "dev.chief.replay.bar-remaining")
        try:
            sources = sorted(HERE.glob("*.swift")) + [HERE.parent / "ReplayButtons.swift", HERE.parent / "CollapseCapture.swift"] + reference(replay)
            replay.compile(sources)
            meta = {"revision": git("rev-parse", "HEAD").decode().strip(),
                    "baseline": git("rev-parse", BASE).decode().strip(), "os": platform.mac_ver()[0],
                    "osBuild": subprocess.check_output(["sw_vers", "-buildVersion"], text=True).strip(),
                    "architecture": platform.machine(), "sdk": subprocess.check_output(["xcrun", "--show-sdk-version"], text=True).strip(),
                    "sourceDiffSHA256": hashlib.sha256(git("diff", "HEAD", "--", "app/macos/Sources")).hexdigest(),
                    "executableSHA256": digest(replay.executable), "collector": {p.name: digest(p) for p in [*sources, Path(__file__)]}}
            (args.output / "source.json").write_text(json.dumps(meta, indent=2) + "\n")
            failed = []
            for case in args.cases:
                try:
                    status = replay.run(["--" + case], launch_services=False, timeout=130)
                finally:
                    replay.export(args.output / case)
                if (replay.workspace / "evidence").is_dir():
                    (replay.workspace / "evidence").rename(replay.root / (case + "-artifacts"))
                if status:
                    failed.append(f"{case} exited {status}: " + (replay.root / "stdout.log").read_text()[-1000:])
            if failed:
                raise RuntimeError("\n".join(failed))
        finally:
            replay.close()


if __name__ == "__main__":
    main()
