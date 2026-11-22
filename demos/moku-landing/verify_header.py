"""Link and replay the current Debug workspace in its production nested reading host."""
from contextlib import contextmanager, nullcontext
from pathlib import Path
import argparse
import subprocess
import sys
from uuid import uuid4

source = Path(__file__).resolve().parent
repo = source.parents[1]
sys.path.insert(0, str(repo / "tools/verification"))
sys.path.insert(0, str(repo / "tools/benchmarks"))
from native_replay import NativeReplay
from gate.ux import native_lease


@contextmanager
def keyboard_client(replay, output):
    client = replay.root / "FocusReplayCard"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", source / "FocusReplayCard.swift", "-o", client], check=True)
    with (output / "keyboard-focus.log").open("w") as log:
        helper = subprocess.Popen([client, replay.workspace, replay.executable], stdout=log, stderr=subprocess.STDOUT)
        try:
            yield
        finally:
            if helper.poll() is None:
                helper.terminate()
            helper.wait()


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--capture", action="store_true", help="capture the own window at menu and maximum zoom")
parser.add_argument("--keyboard", action="store_true", help="focus a card with system Accessibility and check arrow keys and Return")
args = parser.parse_args()
with native_lease():
    args.output.mkdir(parents=True, exist_ok=False)
    # Keep AppKit's saved window state separate across consecutive replay runs.
    replay = NativeReplay(repo, "NestedHeaderReplay", f"com.chief.nested-header-replay.{uuid4().hex}")
    try:
        replay.compile([source / "NestedHeaderReplay.swift"])
        arguments = ["--capture"] if args.capture else []
        if args.keyboard:
            arguments.append("--keyboard")
        with keyboard_client(replay, args.output) if args.keyboard else nullcontext():
            status = replay.run(arguments, timeout=60)
    finally:
        try:
            replay.export(args.output)
        finally:
            replay.close()
# LaunchServices owns the foreground launch. The app writes each receipt
# after its corresponding input and geometry assertions have passed.
receipts = ["overview-scroll.json", "overview-fit.json"]
if args.keyboard:
    receipts.append("overview-keyboard.json")
sys.exit(status or int(not all((args.output / name).is_file() for name in receipts)))
