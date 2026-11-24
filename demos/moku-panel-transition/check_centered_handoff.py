"""Check one completed Codex card visit and Close in the dark 2× workspace replay."""
import argparse
import csv
import itertools
import json
from pathlib import Path
import sys

import cv2

sys.path.insert(0, str(Path(__file__).parent / "evidence/dock-identity"))
from measure import measure


def check(positions):
    with positions.open() as stream:
        rows = list(csv.DictReader(stream))
    # This workload has just one identity. Multiple candidates need inspection,
    # since choosing the nearest one would conceal ink outside the capsule.
    frames = [int(r["frame"]) for r in rows]
    if not frames or frames != list(range(len(rows))):
        raise ValueError("Missing or ambiguous frame in the full-window measurements")
    if any(not r["glass_left"] or not r["glass_bottom"] for r in rows):
        raise ValueError("Missing capsule silhouette")

    widths = [int(r["glass_right"]) - int(r["glass_left"]) + 1 for r in rows]
    # Split at the widest reader frame, independently of the mark being tested.
    peak = widths.index(max(widths))
    results = {}
    for direction, leg, span, roles in [
        ("open", rows[:peak + 1], widths[:peak + 1], ["eyes", "logo"]),
        ("return", rows[peak:], widths[peak:], ["logo", "eyes"]),
    ]:
        visible = [r for r in leg if r["candidate"] != "unresolved"]
        sequence = [role for role, _ in itertools.groupby(r["candidate"] for r in visible)]
        escaped = [int(r["frame"]) for r in visible if float(r["clearance"]) < -2]
        # The round logo foreshortens during the flip. Its full face is square.
        # Measuring the logo also distinguishes a real flip from blinking eyes.
        logos = [r for r in visible if r["candidate"] == "logo"]
        tilted = [int(r["frame"]) for r in logos
                  if int(r["ink_bottom"]) - int(r["ink_top"]) < .8 * (int(r["ink_right"]) - int(r["ink_left"]))]
        # Measure visible cap widths, clear of the rounded endpoints of the
        # 168pt compact shell and the 560pt reader. Both legs must actually move.
        intermediate = len({width for width in span if 170 < width < 535})
        results[direction] = dict(
            sequence=sequence, escapedFrames=escaped, tiltedLogoFrames=tilted,
            unresolvedFrames=[int(r["frame"]) for r in leg if r["candidate"] == "unresolved"],
            minimumClearancePt=min((float(r["clearance"]) for r in visible), default=None),
            intermediateWidths=intermediate,
            passed=sequence == roles and bool(tilted) == (direction == "return") and not escaped and intermediate >= 3,
        )
    compact = all(150 <= width <= 168 for width in (widths[0], widths[-1]))
    expanded = 540 <= widths[peak] <= 560
    return dict(frames=len(rows), peakFrame=peak, endpointWidthsPt=[widths[0], widths[peak], widths[-1]],
                legs=results, passed=compact and expanded and all(leg["passed"] for leg in results.values()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("movie", type=Path)
    parser.add_argument("positions", type=Path, help="output CSV with every measured frame")
    args = parser.parse_args()
    cv2.setNumThreads(1)
    measure(args.movie, args.positions, reference=False)
    result = check(args.positions)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["passed"] else 1)
