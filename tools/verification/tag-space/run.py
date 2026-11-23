"""Build or run a retained Release probe in a private, nonactivating native window."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT))
from tools.benchmarks.gate.runner import lease
from tools.benchmarks.gate.ux import native_lease
from tools.verification.native_replay import NativeReplay

NAME = "TagSpaceProbe"
COLLECTOR = HERE / "main.swift"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def production_sha():
    digest = hashlib.sha256()
    package = ROOT / "app/macos"
    files = [package / "Package.swift", package / "Package.resolved"]
    files += sorted(p for p in (package / "Sources").rglob("*") if p.is_file())
    for path in files:
        digest.update(str(path.relative_to(ROOT)).encode() + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def build(directory, source=COLLECTOR):
    directory.mkdir(parents=True, exist_ok=False)
    production = production_sha()
    collector = digest(source)
    subprocess.run(["xcrun", "swift", "build", "--package-path", "app/macos", "-c", "release",
                    "-Xswiftc", "-enable-testing"], cwd=ROOT, check=True)
    replay = NativeReplay(ROOT, NAME, "dev.chief.replay.tag-space", configuration="release")
    try:
        replay.compile([source], extra_args=["-O", "-g"])
        if production_sha() != production or digest(source) != collector:
            raise ValueError("Production or collector source changed during compilation")
        shutil.copytree(replay.application, directory / replay.application.name)
        manifest = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                    "productionDiff": subprocess.check_output(["git", "diff", "HEAD", "--", "app/macos/Sources"], cwd=ROOT, text=True),
                    "productionSHA256": production, "collectorSHA256": collector, "executableSHA256": digest(replay.executable),
                    "toolchain": subprocess.check_output(["xcrun", "swift", "--version"], text=True).strip()}
        (directory / "build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    finally:
        replay.close()


def measure(directory, output, source=COLLECTOR):
    manifest = json.loads((directory / "build.json").read_text())
    if output.exists():
        raise ValueError("Sample already exists: " + str(output))
    with tempfile.TemporaryDirectory(prefix="chief-native-replay-") as temp:
        root = Path(temp)
        work = root / "workspace"
        work.mkdir()
        app = root / (NAME + ".app")
        shutil.copytree(directory / app.name, app)
        executable = app / "Contents/MacOS" / NAME
        if digest(executable) != manifest["executableSHA256"] or digest(source) != manifest["collectorSHA256"]:
            raise ValueError("Subject binary or collector source changed")
        result = work / "result.json"
        subprocess.run([executable, result], cwd=work, timeout=100, check=True)
        sample = json.loads(result.read_text())
        sample["build"] = manifest
        with output.open("x") as stream:
            stream.write(json.dumps(sample, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--collector", type=Path, default=COLLECTOR,
                        help="Swift probe source, also checked against the manifest at measurement time")
    sub = parser.add_subparsers(dest="mode", required=True)
    sub.add_parser("build").add_argument("directory", type=Path)
    run = sub.add_parser("measure")
    run.add_argument("directory", type=Path)
    run.add_argument("output", type=Path)
    args = parser.parse_args()
    with lease(), native_lease():
        if args.mode == "build":
            build(args.directory.resolve(), args.collector.resolve())
        else:
            measure(args.directory.resolve(), args.output.resolve(), args.collector.resolve())
