"""Measure current production geometry without starting a window or a glass trial."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

source = Path(__file__).resolve().parent
repo = source.parents[2]
sys.path.insert(0, str(repo))
from tools.benchmarks.gate.runner import lease
from tools.benchmarks.gate.ux import native_lease
from tools.verification.native_replay import NativeReplay


def main():
    output = repo / ".build/overview-glass"
    output.mkdir(parents=True, exist_ok=True)
    command = ["xcrun", "swift", "build", "--package-path", "app/macos", "--product", "Chief",
               "-c", "release", "--force-resolved-versions", "-Xswiftc", "-enable-testing"]
    with lease(), native_lease():
        subprocess.run(command, cwd=repo, check=True)
        replay = NativeReplay(repo, "GeometryProbe", "dev.chief.overview-geometry", configuration="release")
        try:
            probe = source / "geometry.swift"
            replay.compile([probe], ["-O"])
            result = subprocess.check_output([replay.executable], cwd=replay.workspace)
            manifest = {
                "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
                "productionStatus": subprocess.check_output(["git", "status", "--porcelain", "--", "app/macos"], cwd=repo, text=True),
                "command": command, "toolchain": subprocess.check_output(["xcrun", "swift", "--version"], text=True),
                "sourceSHA256": hashlib.sha256(probe.read_bytes()).hexdigest(),
                "executableSHA256": hashlib.sha256(replay.executable.read_bytes()).hexdigest(),
                "linkedObjectSHA256": [hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in replay.objects],
            }
            (output / "geometry.json").write_bytes(result)
            (output / "geometry-build.json").write_text(json.dumps(manifest, indent=2) + "\n")
            print(result.decode(), end="")
        finally:
            replay.close()


if __name__ == "__main__":
    main()
