"""Run the component workload against the current worktree's SwiftPM debug build."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT))
from tools.benchmarks.gate.runner import lease
from tools.benchmarks.gate.ux import native_lease
from tools.verification.native_replay import NativeReplay


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    with lease(), native_lease():
        replay = NativeReplay(ROOT, "LazyLoadingProbe", "dev.chief.replay.lazy-loading")
        try:
            replay.compile([HERE / "Native.swift"])
            (output / "subject.json").write_text(json.dumps({
                "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "productionDiff": subprocess.check_output(["git", "diff", "HEAD", "--", "app/macos/Sources"], cwd=ROOT, text=True),
                "collectorSHA256": hashlib.sha256((HERE / "Native.swift").read_bytes()).hexdigest(),
                "executableSHA256": hashlib.sha256(replay.executable.read_bytes()).hexdigest(),
                "platform": platform.platform(), "swift": subprocess.check_output(["swift", "--version"], text=True).strip(),
            }, indent=2) + "\n")
            for sample in range(5):
                result = replay.workspace / f"sample-{sample}.json"
                if replay.run([result], launch_services=False):
                    raise RuntimeError((replay.root / "stdout.log").read_text())
                (output / result.name).write_bytes(result.read_bytes())
        finally:
            replay.close()


if __name__ == "__main__":
    main()
