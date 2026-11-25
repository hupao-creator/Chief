"""Replay the native workspace and measure Chief Bar openings with Release modules."""
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
sys.path.insert(0, str(repo / "tools/e2e"))
from build import source_digest
from report import sha256
from native_replay import NativeReplay
from gate.runner import lease
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
scenario.add_argument("--note-click", action="store_true", help="run Note and scroll interactions entirely at actual size")
scenario.add_argument("--conversation-opening", action="store_true", help="record Chief Bar opening and verify the native reading position")
scenario.add_argument("--conversation-performance", action="store_true", help="measure five Chief Bar openings against a full cached page using Release modules")
parser.add_argument("--profile-opening", action="store_true", help="sample the main thread during the first measured opening")
scenario.add_argument("--note-link", action="store_true", help="follow Chief Note execution links across and within tag spaces")
scenario.add_argument("--tag-states", action="store_true", help="check untagged running work and select every assigned tag")
scenario.add_argument("--tag-read", action="store_true", help="check tag read receipts with window-local pointer input")
scenario.add_argument("--unread-filter", action="store_true", help="exercise the native Unread preset and mark-as-read receipts")
scenario.add_argument("--status-only", action="store_true", help="run the mounted folder and Inbox rail scenario, including full screen")
scenario.add_argument("--completed-card", action="store_true", help="capture the completed Inbox card in both languages")
parser.add_argument("--header-glass", action="store_true", help="capture and measure the production directory row over gray")
parser.add_argument("--rail-hover", action="store_true", help="capture the mounted semantic rail during hover")
args = parser.parse_args()
if args.profile_opening and not args.conversation_performance:
    parser.error("--profile-opening requires --conversation-performance")
if (args.header_glass or args.rail_hover) and (args.unread_filter or args.tag_read or args.tag_states or args.status_only or args.completed_card or args.note_click or args.note_link or args.conversation_opening or args.conversation_performance):
    parser.error("choose dedicated chrome captures or the workspace scenario")
if (args.unread_filter or args.tag_read or args.tag_states or args.note_link or args.status_only or args.completed_card or args.conversation_opening or args.conversation_performance or args.header_glass or args.rail_hover) and args.keyboard:
    parser.error("--keyboard requires the card interaction scenario")
with lease() if args.conversation_performance else nullcontext(), native_lease():
    args.output.mkdir(parents=True, exist_ok=False)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    changed = subprocess.check_output(["git", "status", "--porcelain", "--", "app/macos", "demos/moku-landing"],
                                      cwd=repo, text=True).splitlines()
    (args.output / "source.json").write_text(json.dumps({"revision": revision, "sourceChanges": changed,
        "macOS": platform.mac_ver()[0], "architecture": platform.machine()}, indent=2) + "\n")
    if args.conversation_performance:
        build_command = ["xcrun", "swift", "build", "--package-path", "app/macos", "-c", "release", "-Xswiftc", "-enable-testing"]
        production = source_digest()
        subprocess.run(build_command, cwd=repo, check=True)
        if source_digest() != production:
            raise RuntimeError("Production sources changed during the benchmark build")
    # Keep AppKit's saved window state separate across consecutive replay runs.
    replay = NativeReplay(repo, "NestedHeaderReplay", f"com.chief.nested-header-replay.{uuid4().hex}",
                          configuration="release" if args.conversation_performance else "debug")
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
            fixtures = [source / name for name in ("NestedHeaderReplay.swift", "FilterFacePixels.swift", "ConversationOpeningMeasurement.swift")]
            if args.conversation_performance:
                collectors = [*fixtures, Path(__file__), replay.isolation_source, repo / "tools/verification/native_replay.py"]
                identity = {p.name: sha256(p) for p in collectors}
            replay.compile(fixtures,
                           extra_args=["-O", "-g"] if args.conversation_performance else [])
            if args.conversation_performance:
                if any(sha256(p) != identity[p.name] for p in collectors):
                    raise RuntimeError("Collector sources changed during the benchmark build")
                (args.output / "build.json").write_text(json.dumps({"command": build_command, "productionSourceSHA256": production,
                    "executableSHA256": sha256(replay.executable), "collectorSHA256": identity,
                    "swift": subprocess.check_output(["xcrun", "swift", "--version"], text=True).strip(),
                    "cpu": subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()},
                    indent=2) + "\n")
        arguments = ["--capture"] if args.capture or args.completed_card else []
        if args.note_link:
            arguments.append("--note-link")
        if args.note_click:
            arguments.append("--note-click")
        if args.conversation_opening:
            arguments.append("--conversation-opening")
        if args.tag_states:
            arguments.append("--tag-states")
        if args.tag_read:
            arguments.append("--tag-read")
        if args.unread_filter:
            arguments.append("--unread-filter")
        if args.conversation_performance:
            arguments.append("--conversation-performance")
        if args.profile_opening:
            arguments.append("--profile-opening")
        if args.status_only:
            arguments.append("--status-only")
        if args.completed_card:
            arguments.append("--completed-card")
        if args.keyboard:
            arguments.append("--keyboard")
        with keyboard_client(replay, args.output) if args.keyboard else nullcontext():
            # The combined visit also runs the reminder, card fitting, status rail and Landing scenarios.
            timeout = 75 if args.status_only or args.completed_card else 60
            status = replay.run(arguments, timeout=150 if args.note_click else timeout)
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
if args.tag_states:
    sys.exit(status or int(not (args.output / "tag-states.json").is_file()))
if args.tag_read:
    sys.exit(status or int(not (args.output / "tag-read.json").is_file()))
if args.unread_filter:
    sys.exit(status or int(not (args.output / "unread-filter.json").is_file()))
if args.note_link:
    sys.exit(status or int(not (args.output / "note-links.json").is_file()))
if args.completed_card:
    sys.exit(status or int(not (args.output / "overview-completed-card.json").is_file()))
if args.conversation_opening:
    receipt = args.output / "conversation-opening.json"
    passed = receipt.is_file() and json.loads(receipt.read_text())["failures"] == []
    sys.exit(status or int(not passed))
if args.conversation_performance:
    passed = all((args.output / f"opening-{i}.json").is_file() for i in range(1, 6))
    if args.profile_opening:
        profile = args.output / "opening.sample.txt"
        passed = passed and profile.is_file() and "com.apple.main-thread" in profile.read_text()
    sys.exit(status or int(not passed))
if args.status_only:
    sys.exit(status or int(not (args.output / "overview-status.json").is_file()))
receipts = ["overview-scroll.json", "overview-fit.json"]
receipts += ["overview-status.json", "overview-note-click.json", "landing-note-click.json", "reminder-note-ownership.json"] if args.note_click else ["nested-header.json", "collection-fit.json"]
if args.keyboard:
    receipts.append("overview-keyboard.json")
sys.exit(status or int(not all((args.output / name).is_file() for name in receipts)))
