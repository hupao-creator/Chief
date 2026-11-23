"""Measure every frame of repeated Chief input toggles in a dark Overview window."""
import argparse
import csv
import itertools
import json
from pathlib import Path
import subprocess

import cv2
import numpy as np


def check(movie, output, band, cycles, reversal):
    stamps = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", movie]))["frames"]
    capture = cv2.VideoCapture(str(movie))
    samples = []
    for index, stamp in enumerate(stamps):
        ok, image = capture.read()
        if not ok:
            raise ValueError(f"Missing decoded frame {index}")
        height, width = image.shape[:2]
        x = width // 4
        top, bottom = band or (height - 200, height - 40)
        strip = cv2.cvtColor(image[top:bottom, x:width - x], cv2.COLOR_BGR2GRAY)
        boxes = cv2.connectedComponentsWithStats((strip < 18).astype("uint8"))[2][1:]
        caps = [(left + x, w) for left, y, w, h, area in boxes
                if width * .035 < w < width * .4 and 5 < h < 140 and area > w * 4]
        if len(caps) != 1:
            raise ValueError(f"Expected a single dark glass cap in frame {index}, found {caps}")
        left, w = map(int, caps[0])
        samples.append((index, float(stamp["best_effort_timestamp_time"]), left, w, left + (w - 1) / 2))
    if not samples or capture.read()[0]:
        raise ValueError("Unmatched movie timestamps")
    capture.release()
    with output.open("w") as f:
        writer = csv.writer(f)
        writer.writerow(["frame", "pts", "leftPx", "widthPx", "centerPx"])
        writer.writerows(samples)

    # Calibrate with the initial 168pt shell. Its optical cap falls just
    # inside the glass rim. The 560pt editor gives an independent endpoint.
    idle = samples[0][3]
    scale = idle / 168
    center = samples[0][4]
    def phase(row):
        w = row[3] / scale
        return "idle" if w < 175 else "open" if w > 550 else "moving"
    legs = [(name, list(rows)) for name, rows in itertools.groupby(samples, phase)]
    expected = ["idle"] + ["moving", "open", "moving", "idle"] * cycles
    if reversal:
        expected += ["moving", "open", "moving", "open", "moving", "idle"]
    errors = []
    names = [label for label, _ in legs]
    # An optional trailing dispatch has its own 400pt seat.
    if names != expected and not (names == expected + ["moving"] and 380 < samples[-1][3] / scale < 420):
        errors.append("unexpected phase sequence")
    worst = max(samples, key=lambda r: abs(r[4] - center))
    if abs(worst[4] - center) > 2 * scale:
        errors.append("shell left center")
    steps = np.abs(np.diff([r[3] for r in samples]))
    jump = int(steps.argmax()) + 1
    if steps[jump - 1] >= (560 - 168) * scale / 2:
        errors.append("single-frame width jump")
    for i, (name, rows) in enumerate(legs):
        if name != "moving":
            continue
        widths = np.array([r[3] for r in rows])
        if len(set(widths)) < 3:
            errors.append(f"insufficient intermediate widths at {rows[0][0]}")
        # Include the boundary samples on both sides, so a first-frame
        # collapse followed by a re-expansion is also a failed fold.
        if 0 < i < len(legs) - 1:
            before, after = legs[i-1], legs[i+1]
            travel = np.r_[before[1][-1][3], widths, after[1][0][3]]
            if before[0] == after[0] == "open":
                low = int(travel.argmin())
                down, up = travel[:low + 1], travel[low:]
                if min(travel) >= 520 * scale or min(len(set(down)), len(set(up))) < 3:
                    errors.append("missing reversal")
                if (max(down - np.minimum.accumulate(down)) > 2 * scale or
                        max(np.maximum.accumulate(up) - up) > 2 * scale):
                    errors.append("extra reversal")
                continue
            signed = travel if before[0] == "idle" else -travel
            if np.max(np.maximum.accumulate(signed) - signed) > 2 * scale:
                errors.append(f"width reversed at {rows[0][0]}")
    return dict(frames=len(samples), phases=names, worstCenterFrame=worst[0],
                maxCenterDriftPt=round(abs(worst[4] - center) / scale, 2),
                maxWidthStepPt=round(steps[jump - 1] / scale, 2), jumpFrame=jump,
                errors=errors)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("movie", type=Path)
    parser.add_argument("output", type=Path, help="CSV with every encoded frame")
    parser.add_argument("--band", nargs=2, type=int, metavar=("TOP", "BOTTOM"),
                        help="vertical search bounds in original pixels for a screen recording")
    parser.add_argument("--cycles", type=int, default=2)
    parser.add_argument("--reversal", action="store_true")
    args = parser.parse_args()
    cv2.setNumThreads(1)
    result = check(args.movie, args.output, args.band, args.cycles, args.reversal)
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(result["errors"]))
