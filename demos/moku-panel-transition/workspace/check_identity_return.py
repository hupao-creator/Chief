"""Measure the bar and both faces in the full 4096×2450 Close and reversal recordings."""
import argparse
import csv
import itertools
import json
from pathlib import Path
import sys

import cv2

DEMO = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(DEMO), str(DEMO / "evidence/dock-identity")]
from check_workspace_folds import column_return, measure
from measure import marks


def inspect(movie, output):
    samples, width = measure(movie, output / "positions.csv", (2120, 2310), include_columns=True)
    capture = cv2.VideoCapture(str(movie))
    rows = []
    errors = []
    try:
        for index, pts, left, span, center, top in samples:
            ok, frame = capture.read()
            if not ok or frame.shape[:2] != (2450, 4096):
                raise ValueError(f"Frame {index} is missing or differs from the reference size")
            # Include a margin outside the independently measured glass. Measure
            # the mark in points with the reference's 1.8 movie pixels per point.
            scale = 1.8
            region = frame[top - 10:top + 104, left - 28:left + span + 28]
            region = cv2.resize(region, None, fx=1 / scale, fy=1 / scale, interpolation=cv2.INTER_AREA)
            ink = list(marks(region))
            row = dict(frame=index, pts=pts, width=span, center=center, top=top, face="unresolved",
                       inkLeft=None, inkTop=None, inkWidth=None, inkHeight=None)
            if len(ink) > 1:
                row["face"] = "+".join(kind for kind, _ in ink)
                errors.append(f"More than one visible face in frame {index}: {ink}")
            elif ink:
                kind, (x0, y0, x1, y1) = ink[0]
                row.update(face=kind, inkLeft=round(left - 28 + scale * x0, 1), inkTop=round(top - 10 + scale * y0, 1),
                           inkWidth=x1 - x0 + 1, inkHeight=y1 - y0 + 1)
                if min(scale * x0 - 28, span + 28 - scale * (x1 + 1)) < -2:
                    errors.append(f"Visible {kind} left the capsule in frame {index}")
            rows.append(row)
    finally:
        capture.release()
    with (output / "identity.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    return rows, width, errors


def sequence(rows):
    return [name for name, _ in itertools.groupby(r["face"] for r in rows if r["face"] != "unresolved")]


def close_leg(rows, width):
    compact, opened = rows[-1]["width"], rows[0]["width"]
    path = column_return([r["width"] for r in rows], [r["center"] for r in rows], [r["top"] for r in rows],
                         compact, (width - 1) / 2, rows[-1]["top"], 1.8)
    folding = [r for r in rows if compact + 4 < r["width"] < opened - 4]
    tilted = [r["frame"] for r in folding if r["face"] == "logo" and r["inkHeight"] < .8 * r["inkWidth"]]
    eyes = [r for r in folding if r["face"] == "eyes"]
    eye_height = max((r["inkHeight"] for r in rows if r["face"] == "eyes"), default=0)
    revealing = [r["frame"] for r in eyes if r["inkHeight"] < .8 * eye_height]
    first_eyes = next((r for r in rows if r["face"] == "eyes"), None)
    passed = (not path["errors"] and sequence(rows) == ["logo", "eyes"] and bool(tilted) and bool(revealing)
              and first_eyes == eyes[0] and abs(eyes[0]["center"] - rows[0]["center"]) <= 4)
    return dict(passed=passed, tiltedLogoDuringFold=tilted, revealingEyesDuringFold=revealing,
                firstEyes=first_eyes, pathFirstFrame=rows[0]["frame"], path=path)


def reversal(rows, width):
    # Find the second wide plateau from the shell alone. Both appearances of
    # the logo and eyes on either side of the interruption must be on film.
    opened = rows[0]["width"]
    moving = next(i for i, r in enumerate(rows) if r["width"] < opened - 20)
    # Split at the settled editor. Its last few expanding pixels still belong
    # to the interrupted leg and must be checked in that direction.
    reopened = next(i for i in range(moving + 1, len(rows) - 2)
                    if all(abs(r["width"] - opened) <= 1 for r in rows[i:i + 3]))
    final_close = close_leg(rows[reopened:], width)
    turn = min(range(moving, reopened), key=lambda i: rows[i]["width"])
    before, after = rows[:turn + 1], rows[turn:reopened + 1]
    faces = sequence(rows[:reopened + 1])
    eyes = [r["frame"] for r in rows[:reopened + 1] if r["face"] == "eyes"]
    tilted = [r["frame"] for r in rows[:reopened + 1] if r["face"] == "logo" and r["inkHeight"] < .8 * r["inkWidth"]]
    fold_only = bool(eyes and tilted and tilted[-1] < eyes[0])
    contracted = [r["width"] for r in before]
    expanded = [r["width"] for r in after]
    column_drift = max(abs(r["center"] - rows[0]["center"]) for r in rows[:reopened + 1])
    passed = (faces == ["logo", "eyes", "logo"] and fold_only and column_drift <= 4
              and len(set(contracted)) >= 4 and len(set(expanded)) >= 4
              and max(b - a for a, b in zip(contracted, contracted[1:])) <= 4
              and max(a - b for a, b in zip(expanded, expanded[1:])) <= 4
              and final_close["passed"])
    return dict(passed=passed, facesBeforeReopened=faces, maxColumnDriftBeforeReopenedPx=column_drift, narrowestFrame=rows[turn],
                tiltedLogoBeforeReopened=tilted, finalClose=final_close)


def check(movie, output, reverse):
    rows, width, errors = inspect(movie, output)
    result = reversal(rows, width) if reverse else close_leg(rows, width)
    result["frameErrors"] = errors
    result["passed"] = result["passed"] and not errors
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("movie", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--reverse", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    cv2.setNumThreads(1)
    result = check(args.movie, args.output, args.reverse)
    (args.output / "check.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["passed"] else 1)
