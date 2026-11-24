"""Compare the projected ink of both faces in the 2× Report window movies."""
import argparse
import csv
import itertools
import json
import math
from pathlib import Path
import subprocess
import sys

import cv2

DEMO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DEMO / "evidence/dock-identity"))
from measure import components, marks


def edge_eyes(glass, eyes):
    # Only search the last measured eye footprint. At 2× an antialiased eye
    # can occupy one or two dim rows while retaining its horizontal span.
    left, top, width, height = (eyes[k] for k in ("inkLeft", "inkTop", "inkWidth", "inkHeight"))
    x0, y0 = max(0, left - 4), max(0, top + height // 2 - 6)
    patch = glass[y0:top + height // 2 + 7, x0:left + width + 4]
    if not patch.size:
        return None
    lo, hi = patch.min(axis=2), patch.max(axis=2)
    parts = sorted(components((lo > 65) & (hi - lo < 30)))
    if len(parts) != 2:
        return None
    (x, y, w, h, _), (xx, yy, ww, hh, _) = parts
    # Require two isolated, substantial strokes over the same outer edges,
    # with the spacing of eyes and a shared, nearly edge-on baseline.
    if not (all(4 <= width_px <= 34 and height_px <= 4 and area > .45 * width_px * height_px
                for _, _, width_px, height_px, area in parts)
            and 18 <= xx + ww / 2 - x - w / 2 <= 46
            and abs(y + h / 2 - yy - hh / 2) <= 2
            and abs(x0 + x - left) <= 4 and abs(x0 + xx + ww - left - width) <= 4):
        return None
    return x0 + x, y0 + min(y, yy), x0 + xx + ww - 1, y0 + max(y + h, yy + hh) - 1


def record_ink(row, face, bounds, method):
    left, top, right, bottom = bounds
    row.update(face=face, height=(bottom - top + 1) / 2, inkLeft=left, inkTop=top,
               inkWidth=right - left + 1, inkHeight=bottom - top + 1, detection=method)


def read_frames(directory):
    movie = directory / "window.mp4"
    stamps = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
        "frame=best_effort_timestamp_time", "-of", "json", movie]))["frames"]
    capture = cv2.VideoCapture(str(movie))
    rows = []
    unresolved_glass = None
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
            # Keep both backing pixels per point; downsampling can give two
            # equally thin eyes unequal heights at the edge of the turn.
            glass = image[y:y + 108, x:x + w]
            ink = list(marks(glass, scale=2))
            if len(ink) > 1:
                raise ValueError(f"Multiple visible marks at frame {index}: {ink}")
            face, bounds = ink[0] if ink else ("unresolved", (0, 0, -1, -1))
            row = dict(frame=index, pts=float(stamp["best_effort_timestamp_time"]), left=x, top=y, width=w)
            record_ink(row, face, bounds, "mark" if ink else "unresolved")
            if unresolved_glass is not None and len(rows) >= 2:
                previous, missing = rows[-2:]
                if ({previous["face"], face} == {"eyes", "logo"}
                        and max(missing["pts"] - previous["pts"], row["pts"] - missing["pts"]) <= 2 / 60):
                    eyes = row if face == "eyes" else previous
                    bounds = edge_eyes(unresolved_glass, eyes)
                    if bounds:
                        record_ink(missing, "eyes", bounds, "edge pair")
            rows.append(row)
            unresolved_glass = None if ink else glass.copy()
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
    last_outgoing = next(r for r in reversed(rows[:cut]) if r["face"] == before)
    seam = [last_outgoing["frame"], rows[cut]["frame"]]
    # At exactly 90° the face can vanish for a sample. Longer unmeasured
    # intervals cannot establish continuity across the handoff.
    continuous = seam[1] - seam[0] <= 2 and edge - last_outgoing["pts"] <= 2 / 60
    legs = []
    crossings = []
    for name, part in [(before, rows[:cut]), (after, rows[cut:])]:
        visible = [r for r in part if abs(r["pts"] - edge) < .34 and r["face"] == name]
        full = max(r["height"] for r in visible)
        ordered = visible if name == after else list(reversed(visible))
        end = next(i for i, r in enumerate(ordered) if r["height"] >= full * .94)
        tilted = ordered[:end]
        heights = [r["height"] for r in tilted]
        # At 45° the projected face is about 71% of its upright height.
        # Bracket the crossing with actual tilted frames from this face.
        threshold = full * math.cos(math.pi / 4)
        bracket = []
        intermediate = "observed" if any(.45 * full < h < .8 * full for h in heights) else None
        for thin, wide in zip(tilted, ordered[1:end + 1]):
            interval = abs(wide["pts"] - thin["pts"])
            if (thin["height"] < threshold <= wide["height"] and interval <= 2 / 60
                    and abs(wide["frame"] - thin["frame"]) == 1):
                fraction = (threshold - thin["height"]) / (wide["height"] - thin["height"])
                crossings.append(thin["pts"] + fraction * (wide["pts"] - thin["pts"]))
                bracket = [thin["frame"], wide["frame"]]
                # One exposure interval can span the entire intermediate band.
                # Require two tilted observations and a physically possible
                # angular step. The 420ms cubic's steepest slope is 1.5/.36.
                if not intermediate and wide["height"] < .94 * full:
                    step = math.asin(wide["height"] / full) - math.asin(thin["height"] / full)
                    if step <= (math.pi * 1.5 / (.36 * .420)) * interval:
                        intermediate = "bracketed"
                break
        elapsed = abs(ordered[end]["pts"] - ordered[0]["pts"])
        legs.append(dict(face=name, fullHeightPt=full, edgeToFullMS=round(1000 * elapsed),
                         frames=[r["frame"] for r in tilted], heightsPt=heights, crossingFrames=bracket,
                         intermediate=intermediate, passed=min(heights, default=full) <= .45 * full
                         and intermediate is not None and bool(bracket)))
    # The 420ms reading curve traverses 45°–135° in 64ms. Allow one
    # capture frame per crossing for rasterization and frame sampling.
    middle = crossings[1] - crossings[0] if len(crossings) == 2 else None
    return dict(edgePTS=edge, seamFrames=seam, seamContinuous=continuous, legs=legs, middle90MS=round(1000 * middle) if middle is not None else None,
                passed=continuous and all(leg["passed"] for leg in legs) and middle is not None and abs(middle - .064) <= 2 / 60)


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
    # The mark finishes face-on before the editor expands and stays upright
    # through the settled hold preceding Close.
    expanded = [r for r in opened if r["width"] >= opened[-1]["width"] - 2]
    aligned = all(r["face"] == "logo" and r["height"] >= 22 for r in expanded)
    closing = compare(closed, "logo", "eyes")
    edge_row = next(r for r in closed if r["pts"] == closing["edgePTS"])
    compact = closed[-1]["width"]
    folding = [r for r in closed if compact + 4 < r["width"] < closed[0]["width"] - 4]
    upright_fold = bool(folding) and all(r["face"] == "logo" and r["height"] >= 22 for r in folding)
    turn_frames = [frame for leg in closing["legs"] for frame in leg["frames"]]
    turn = [r for r in closed if turn_frames and min(turn_frames) <= r["frame"] <= max(turn_frames)]
    source_center = closed[0]["left"] + closed[0]["width"] / 2
    stationary = bool(turn) and all(abs(r["width"] - compact) <= 4 and abs(r["left"] + r["width"] / 2 - source_center) <= 4
                                    and abs(r["top"] - edge_row["top"]) <= 4 for r in turn)
    reverse = segment(4, 6)
    sequence = faces(reverse)
    eyes = [r for r in reverse if r["face"] == "eyes"]
    reversed_midturn = sequence == ["logo", "eyes", "logo"] and eyes[0]["height"] < max(r["height"] for r in eyes) > eyes[-1]["height"]
    asymmetry = max(abs(a["edgeToFullMS"] - b["edgeToFullMS"])
                    for a, b in zip(opening["legs"], reversed(closing["legs"])))
    return dict(passed=opening["passed"] and aligned and closing["passed"] and upright_fold and stationary and reversed_midturn and asymmetry <= 85,
                expandedLogoUpright=aligned, uprightFold=upright_fold, stationaryTurn=stationary,
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
