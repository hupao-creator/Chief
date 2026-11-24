"""Compare the projected ink of both faces in the 2× Report window movies."""
import argparse
import csv
import itertools
import json
from pathlib import Path
import subprocess
import sys

import cv2

DEMO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEMO / "evidence/dock-identity"))
from measure import components, marks


def read_frames(directory):
    movie = directory / "window.mp4"
    stamps = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
        "frame=best_effort_timestamp_time", "-of", "json", movie]))["frames"]
    capture = cv2.VideoCapture(str(movie))
    rows = []
    try:
        for index, stamp in enumerate(stamps):
            ok, image = capture.read()
            if not ok or image.shape[:2] != (1640, 2560):
                raise ValueError(f"Missing 1280 × 820 pt window at frame {index}")
            strip = cv2.cvtColor(image[1410:1625], cv2.COLOR_BGR2GRAY)
            caps = [(x, y + 1410, w) for x, y, w, h, area in components(strip < 18)
                    if 276 < w < 1160 and h > 8 and area > w * 5]
            if len(caps) != 1:
                raise ValueError(f"Ambiguous glass at frame {index}: {caps}")
            x, y, w = caps[0]
            region = cv2.resize(image[y:y + 108, x:x + w], None, fx=.5, fy=.5, interpolation=cv2.INTER_AREA)
            ink = list(marks(region))
            if len(ink) > 1:
                raise ValueError(f"Multiple visible marks at frame {index}: {ink}")
            face, bounds = ink[0] if ink else ("unresolved", (0, 0, -1, -1))
            rows.append(dict(frame=index, pts=float(stamp["best_effort_timestamp_time"]), left=x, top=y,
                             width=w, face=face, height=bounds[3] - bounds[1] + 1))
        if capture.read()[0]:
            raise ValueError("Missing movie timestamps")
    finally:
        capture.release()
    with (directory / "frames.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0], lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    return rows


def faces(rows):
    return [key for key, _ in itertools.groupby(r["face"] for r in rows if r["face"] != "unresolved")]


def compare(rows, before, after):
    if faces(rows) != [before, after]:
        raise ValueError(f"Unexpected face order: {faces(rows)}")
    cut = next(i for i, r in enumerate(rows) if r["face"] == after)
    # Measure heights against the nearby full face. Focus and idle eyes have
    # different contours. Exclude travel and late idle blinks from calibration.
    edge = rows[cut]["pts"]
    legs = []
    for name, part in [(before, rows[:cut]), (after, rows[cut:])]:
        visible = [r for r in part if abs(r["pts"] - edge) < .34 and r["face"] == name]
        full = max(r["height"] for r in visible)
        ordered = visible if name == after else list(reversed(visible))
        end = next(i for i, r in enumerate(ordered) if r["height"] >= full * .94)
        tilted = ordered[:end]
        heights = [r["height"] for r in tilted]
        # Require both a thin and intermediate projection, and enough distinct
        # samples/time to distinguish a turning face from an endpoint swap.
        elapsed = abs(ordered[end]["pts"] - ordered[0]["pts"])
        legs.append(dict(face=name, fullHeightPt=full, edgeToFullMS=round(1000 * elapsed),
                         frames=[r["frame"] for r in tilted], heightsPt=heights,
                         passed=len(set(heights)) >= 4 and elapsed >= .09 and min(heights, default=full) <= .45 * full
                         and any(.45 * full < h < .8 * full for h in heights)))
    return dict(edgePTS=edge, legs=legs, passed=all(leg["passed"] for leg in legs))


def check(directory, reduced):
    events = json.loads((directory / "events.json").read_text())
    rows = read_frames(directory)
    def segment(first, last):
        return [r for r in rows if events[first]["seconds"] <= r["pts"] < events[last]["seconds"]]
    opened, closed = segment(0, 1), segment(1, 2)
    if reduced:
        widths = [r["width"] for r in opened + closed]
        passed = (faces(opened) == ["eyes", "logo"] and faces(closed) == ["logo", "eyes"]
                  and all(w < 345 or w > 995 for w in widths)
                  and all(r["height"] >= 22 for r in opened + closed if r["face"] == "logo"))
        return dict(passed=passed, widthsPx=sorted(set(widths)))
    opening = compare(opened, "eyes", "logo")
    closing = compare(closed, "logo", "eyes")
    edge_row = next(r for r in closed if r["pts"] == closing["edgePTS"])
    folding = closed[-1]["width"] + 4 < edge_row["width"] < closed[0]["width"] - 4
    reverse = segment(4, 6)
    sequence = faces(reverse)
    eyes = [r for r in reverse if r["face"] == "eyes"]
    reversed_midturn = sequence == ["logo", "eyes", "logo"] and eyes[0]["height"] < max(r["height"] for r in eyes) > eyes[-1]["height"]
    asymmetry = max(abs(a["edgeToFullMS"] - b["edgeToFullMS"])
                    for a, b in zip(opening["legs"], reversed(closing["legs"])))
    return dict(passed=opening["passed"] and closing["passed"] and folding and reversed_midturn and asymmetry <= 85,
                opening=opening, closing=closing, closingEdgeWidthPx=edge_row["width"], maxLegDifferenceMS=asymmetry,
                interruptedSequence=sequence, interruptedEyeHeightsPt=[r["height"] for r in eyes])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--reduced", action="store_true")
    args = parser.parse_args()
    cv2.setNumThreads(1)
    result = check(args.directory, args.reduced)
    (args.directory / "check.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    sys.exit(0 if result["passed"] else 1)
