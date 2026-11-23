"""Inspect a dark, 2× 1885×1125pt Chief window from empty Landing through dispatch and Compose."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).parent / "evidence/dock-identity"))
from measure import clearance, components, eye_pairs


def measure(image, color=None):
    # The centered glass has a dark top and a bright bottom rim. Search all
    # heights, including the journey from the center to the bottom of the window.
    cap = image[:, 530:1355] < 18
    if color is not None:
        # AX keyboard focus paints a blue ring across the black cap. Include
        # the tinted glass so that this visible focus state has a silhouette.
        band = color[:, 530:1355]
        cap |= (band[:, :, 0].astype(np.int16) - band[:, :, 2] >= 9) & (image[:, 530:1355] < 70)
    caps = [box for box in components(cap)
            if 130 < box[2] < 760 and box[3] < 110 and abs(530 + box[0] + box[2] / 2 - 942.5) < 15]
    if not caps:
        raise ValueError("No centered capsule")
    x, top, width, _, _ = max(caps, key=lambda box: box[4])
    x += 530
    strip = image[top:top + 110, x + width // 4:x + 3 * width // 4].astype(np.int16)
    fall = np.median(strip[:-1] - strip[1:], axis=1)
    bottom = top + 26 + int(np.argmax(fall[26:98]))
    shell = (x, top, x + width - 1, bottom)
    # Independent full-window search also finds eyes entirely outside the glass.
    eyes = [box for _, box in eye_pairs(image > 231)]
    row = image[top - 7:bottom + 7, x:x + width]
    # The only solid 10pt square in this workload is the Stop mark.
    stops = [width - 1 - (left + (w - 1) / 2) for left, _, w, h, area in components(row > 100)
             if 8 <= w <= 12 and 8 <= h <= 12 and abs(w - h) <= 1 and area >= .88 * w * h]
    return dict(shell=shell, eyes=eyes, eyeMargins=[round(clearance(shell, box), 2) for box in eyes],
                stopInsets=stops), row


def rim_samples(pixels, center_y, edge, direction):
    # Near the horizontal diameter each scanline crosses the same outer rim.
    # Compare RGB against the adjacent exterior, including with AX focus tint.
    xs = 2 * edge + direction * np.arange(-32, 45)
    edges = []
    for y in range(center_y + 4, center_y + 12):
        line = pixels[y, xs].astype(np.int16)
        contrast = np.max(np.abs(line - np.median(line[-8:], axis=0)), axis=1)
        ink = np.flatnonzero(contrast[:-8] > 6)
        if len(ink) and 1 <= ink[-1] < len(line) - 9:
            edges.append(int(xs[ink[-1]]))
    if len(edges) < 4 or max(edges) - min(edges) > 4:
        raise ValueError("Unresolved glass rim at Stop")
    return edges


def measure_stop_rim(pixels, frame):
    """Measure the square and the center against both visible contours at 2×."""
    left, top, right, bottom = frame["shell"]
    provisional = frame["stopInsets"]
    frame["darkCapStopInsets"] = provisional
    if not provisional:
        return
    mid = top + bottom
    # Search the whole row so a misplaced Stop can still be measured.
    x = max(0, 2 * left - 24)
    gray = cv2.cvtColor(pixels[2 * top - 14:2 * bottom + 14, x:2 * right + 40], cv2.COLOR_BGR2GRAY)
    edges = rim_samples(pixels, mid, right, 1)
    leading = rim_samples(pixels, mid, left, -1)
    frame.update(rimCenterPt=float(np.median(edges) + np.median(leading)) / 4, leftRimScanlinesPx=leading)
    components_2x = [x + left + (width - 1) / 2 for left, _, width, height, area in components(gray > 100)
                     if 15 <= width <= 24 and 15 <= height <= 24 and area >= .80 * width * height]
    insets = []
    for estimate in provisional:
        matches = [center for center in components_2x if abs(center - 2 * (right - estimate)) <= 3]
        if len(matches) != 1:
            raise ValueError("Unresolved Stop center at native resolution")
        insets.append((float(np.median(edges)) - matches[0]) / 2)
    frame.update(rimScanlinesPx=edges, stopInsets=insets)


def glyph_ink(row):
    # Remove the broad glass gradient and preserve the strokes of both labels.
    top_hat = cv2.morphologyEx(row, cv2.MORPH_TOPHAT, np.ones((1, 17), np.uint8))
    return cv2.GaussianBlur(top_hat, (3, 3), .65).astype(np.float32)


def reference(ink):
    area = ink[16:59, 76:147]
    ys, xs = np.where(area > 65)
    if not xs.size:
        raise ValueError("Missing reference label")
    top, left = int(ys.min()) - 2, int(xs.min())
    glyphs = area[top:top + 17, left:left + 48]
    if glyphs.shape != (17, 48):
        raise ValueError("Incomplete reference label")
    return glyphs


def measure_status(frames, rows, pending, started):
    # Fit both glyph masks at the same moving origin. This also detects an
    # outgoing label still visible behind the incoming one at partial opacity.
    masks = [reference(rows[i]) for i in (pending, started)]
    gram = np.array([[np.sum(a * b) for b in masks] for a in masks])
    if gram[0, 1] / np.sqrt(gram[0, 0] * gram[1, 1]) > .85:
        raise ValueError("Select distinct readable pending and started labels")
    inverse = np.linalg.inv(gram)
    for frame, row in zip(frames, rows):
        region = row[11:61, 58:151]
        correlations = [cv2.matchTemplate(region, mask, cv2.TM_CCORR) for mask in masks]
        best = np.maximum(correlations[0] / np.linalg.norm(masks[0]),
                          correlations[1] / np.linalg.norm(masks[1]))
        y, x = np.unravel_index(np.argmax(best), best.shape)
        a, b = np.array([c[y, x] for c in correlations]) @ inverse
        patch = region[y:y + 17, x:x + 48]
        fit = np.linalg.norm(a * masks[0] + b * masks[1]) / max(1, np.linalg.norm(patch))
        frame.update(pending=round(float(a), 3), started=round(float(b), 3), fit=round(float(fit), 3))


def check(movie, pending, started, output):
    stamps = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", movie]))["frames"]
    if not 0 <= pending < started < len(stamps):
        raise ValueError("Supply the pending and started frame numbers in presentation order")
    capture = cv2.VideoCapture(str(movie))
    frames, rows = [], []
    for index, stamp in enumerate(stamps):
        ok, pixels = capture.read()
        if not ok or pixels.shape[:2] != (2250, 3770):
            raise ValueError(f"Expected a 3770×2250 window frame at {index}")
        color = cv2.resize(pixels, (1885, 1125), interpolation=cv2.INTER_AREA)
        gray = cv2.cvtColor(color, cv2.COLOR_BGR2GRAY)
        try:
            frame, row = measure(gray, color)
        except ValueError as error:
            raise ValueError(f"Frame {index}: {error}") from error
        try:
            measure_stop_rim(pixels, frame)
        except ValueError as error:
            frame.update(stopMeasurementError=str(error), stopInsets=[])
        frames.append(dict(frame=index, pts=float(stamp["best_effort_timestamp_time"]), **frame))
        # Retain just the status region for the second pass.
        rows.append(glyph_ink(row[:, :155]))
    if capture.read()[0]:
        raise ValueError("Unstamped movie frame")
    capture.release()
    measure_status(frames, rows, pending, started)

    errors = {}
    missing = [f["frame"] for f in frames if "stopMeasurementError" in f]
    if missing:
        errors["unresolvedStop"] = missing
    if not (frames[0]["shell"][1] < 600 and frames[-1]["shell"][1] > 1000 and
            any(650 < f["shell"][1] < 980 for f in frames)):
        errors["missingLandingDescent"] = True
    unresolved = [f["frame"] for f in frames if not f["eyes"]]
    margins = [v for f in frames for v in f["eyeMargins"]]
    stops = [v for f in frames for v in f["stopInsets"]]
    for message, offending in (
        ("offCenter", [f for f in frames if abs(f.get("rimCenterPt", (f["shell"][0] + f["shell"][2]) / 2) - 942) > 2]),
        ("escapedOrDuplicateEyes", [f for f in frames if len(f["eyes"]) > 1 or any(v < -2 for v in f["eyeMargins"])]),
        ("misplacedOrDuplicateStop", [f for f in frames if len(f["stopInsets"]) > 1 or
                                     any(not 20 <= v <= 31 for v in f["stopInsets"])]),
        ("superimposedStatus", [f for f in frames if min(f["pending"], f["started"]) > .12 and f["fit"] > .90]),
    ):
        if offending:
            errors[message] = [f["frame"] for f in offending]
    # The running replay must visibly exercise each Stop seat and both labels.
    if not stops or min(stops) > 24 or max(stops) < 27:
        errors["missingStopSeat"] = True
    if any(sum(f[label] > .75 and f["fit"] > .90 for f in frames) < 3 for label in ("pending", "started")):
        errors["missingStatus"] = True
    if len(unresolved) > .05 * len(frames) or not margins:
        errors["insufficientEyeCoverage"] = True
    result = dict(frames=len(frames), finalPTS=frames[-1]["pts"], unresolvedEyes=unresolved,
                  leastEyeMargin=min(margins, default=None), stopRange=[min(stops, default=None), max(stops, default=None)],
                  referenceFrames=[pending, started], errors=errors)
    output.write_text(json.dumps(dict(result=result, samples=frames)) + "\n")
    print(json.dumps(result, indent=2))
    return not errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("movie", type=Path)
    parser.add_argument("pending", type=int, help="zero-based frame showing only the pending status")
    parser.add_argument("started", type=int, help="zero-based frame showing only the started status")
    parser.add_argument("output", type=Path, help="JSON report with one sample per encoded frame")
    args = parser.parse_args()
    cv2.setNumThreads(1)
    sys.exit(0 if check(args.movie, args.pending, args.started, args.output) else 1)
