"""Link and replay the current Debug workspace in its production nested reading host."""
from contextlib import contextmanager, nullcontext
from pathlib import Path
import argparse
import json
import platform
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
parser.add_argument("--capture", action="store_true", help="save images of the wide, narrow and four-column layouts")
parser.add_argument("--keyboard", action="store_true", help="focus a card with system Accessibility and check arrow keys and Return")
scenario = parser.add_mutually_exclusive_group()
scenario.add_argument("--note-swipe", action="store_true", help="run Note and scroll interactions entirely at actual size")
scenario.add_argument("--note-link", action="store_true", help="follow Chief Note execution links across and within tag spaces")
scenario.add_argument("--status-only", action="store_true", help="run only the mounted status-filter and idle illustration scenario")
parser.add_argument("--header-glass", action="store_true", help="capture and measure the production directory row over gray")
parser.add_argument("--rail-hover", action="store_true", help="capture the mounted semantic rail during hover")
args = parser.parse_args()
if (args.header_glass or args.rail_hover) and (args.status_only or args.note_swipe or args.note_link):
    parser.error("choose dedicated chrome captures or the workspace scenario")
if (args.note_link or args.status_only or args.header_glass or args.rail_hover) and args.keyboard:
    parser.error("--keyboard requires the card interaction scenario")
with native_lease():
    args.output.mkdir(parents=True, exist_ok=False)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    changed = subprocess.check_output(["git", "status", "--porcelain", "--", "app/macos", "demos/moku-landing"],
                                      cwd=repo, text=True).splitlines()
    (args.output / "source.json").write_text(json.dumps({"revision": revision, "sourceChanges": changed,
        "macOS": platform.mac_ver()[0], "architecture": platform.machine()}, indent=2) + "\n")
    # Keep AppKit's saved window state separate across consecutive replay runs.
    replay = NativeReplay(repo, "NestedHeaderReplay", f"com.chief.nested-header-replay.{uuid4().hex}")
    try:
        if args.header_glass or args.rail_hover:
            fixtures = [source / "OverviewChromeFixtureApp.swift"]
            flags = []
            if args.header_glass:
                fixtures.extend([source / "HeaderGlassReplay.swift", source / "FilterFacePixels.swift"])
                flags.append("-DHEADER_GLASS")
            if args.rail_hover:
                fixtures.append(source / "RailHoverReplay.swift")
                flags.append("-DRAIL_HOVER")
            replay.compile(fixtures, extra_args=flags)
        else:
            replay.compile([source / "NestedHeaderReplay.swift", source / "FilterFacePixels.swift"])
        arguments = ["--capture"] if args.capture else []
        if args.note_link:
            arguments.append("--note-link")
        if args.note_swipe:
            arguments.append("--note-swipe")
        if args.status_only:
            arguments.append("--status-only")
        if args.keyboard:
            arguments.append("--keyboard")
        with keyboard_client(replay, args.output) if args.keyboard else nullcontext():
            status = replay.run(arguments, timeout=75 if args.note_swipe or args.status_only else 60)
    finally:
        try:
            replay.export(args.output)
        finally:
            replay.close()
# LaunchServices owns the foreground launch. The app writes each receipt
# after its corresponding input and geometry assertions have passed.
if args.header_glass or args.rail_hover:
    receipts = (["header-glass.json"] if args.header_glass else []) + (["rail-hover.json"] if args.rail_hover else [])
    passed = all((args.output / receipt).is_file() and
                 json.loads((args.output / receipt).read_text()).get("status") == "passed" for receipt in receipts)
    sys.exit(status or int(not passed))
if args.note_link:
    sys.exit(status or int(not (args.output / "note-links.json").is_file()))
if args.status_only:
    sys.exit(status or int(not (args.output / "overview-status.json").is_file()))
receipts = ["overview-scroll.json", "overview-fit.json"]
receipts += ["overview-status.json", "overview-note-swipe.json", "landing-note-swipe.json", "reminder-note-ownership.json"] if args.note_swipe else ["nested-header.json", "collection-fit.json"]
if args.keyboard:
    receipts.append("overview-keyboard.json")
sys.exit(status or int(not all((args.output / name).is_file() for name in receipts)))
