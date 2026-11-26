"""Build an isolated native demo, verify its windowless replay and print the app path."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT))
from tools.benchmarks.gate.runner import lease
from tools.benchmarks.gate.ux import ui_lease
from tools.verification.native_replay import NativeReplay

with lease(), ui_lease():
    subprocess.run(["xcrun", "swift", "build", "--package-path", "app/macos", "-Xswiftc", "-enable-testing"],
                   cwd=ROOT, check=True)
    replay = NativeReplay(ROOT, "TagSpaceHaptics", "dev.chief.demo.tag-space-haptics")
    try:
        replay.compile([HERE / "Demo.swift"])
        subprocess.run([replay.executable, "--replay"], cwd=replay.workspace, timeout=30, check=True)
        folder = Path(tempfile.mkdtemp(prefix="chief-native-replay-tag-space-", dir="/private/tmp"))
        (folder / "workspace").mkdir()
        app = folder / replay.application.name
        shutil.copytree(replay.application, app)
        print(app)
    finally:
        replay.close()
