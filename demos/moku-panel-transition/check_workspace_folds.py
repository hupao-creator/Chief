"""Measure Chief input folds and reading-column returns in a dark workspace recording."""
import argparse
import csv
import itertools
import json
from pathlib import Path
import subprocess

import cv2
import numpy as np


def measure(movie, output, band, *, include_columns=False):
    stamps = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", movie]))["frames"]
    capture = cv2.VideoCapture(str(movie))
    samples = []
    for index, stamp in enumerate(stamps):
        ok, image = capture.read()
        if not ok:
            raise ValueError(f"Missing decoded frame {index}")
        height, width = image.shape[:2]
        x = width // 32 if include_columns else width // 4
        top, bottom = band or (height - 200, height - 40)
        strip = cv2.cvtColor(image[top:bottom, x:width - x], cv2.COLOR_BGR2GRAY)
        boxes = cv2.connectedComponentsWithStats((strip < 18).astype("uint8"))[2][1:]
        caps = [(left + x, w, top + y) for left, y, w, h, area in boxes
                if width * .035 < w < width * .4 and 5 < h < 140 and area > w * 4]
        if len(caps) != 1:
            raise ValueError(f"Expected a single dark glass cap in frame {index}, found {caps}")
        left, w, cap_top = map(int, caps[0])
        samples.append((index, float(stamp["best_effort_timestamp_time"]), left, w, left + (w - 1) / 2, cap_top))
    if not samples or capture.read()[0]:
        raise ValueError("Unmatched movie timestamps")
    capture.release()
    with output.open("w") as f:
        writer = csv.writer(f)
        writer.writerow(["frame", "pts", "leftPx", "widthPx", "centerPx", "topPx"])
        writer.writerows(samples)
    return samples, width


def check(movie, output, band, cycles, reversal):
    samples, _ = measure(movie, output, band)
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


def column_return(widths, centers, tops, compact, resting, resting_top, pixels_per_point):
    widths, centers = np.asarray(widths), np.asarray(centers)
    tops = np.asarray(tops, dtype=float)
    tolerance = 2 * pixels_per_point
    opened, source = widths[0], centers[0]
    folding = widths > compact + tolerance
    middle_widths = widths[folding & (widths < opened - tolerance)]
    travelling = centers[(~folding) & (centers < source - tolerance) & (centers > resting + tolerance)]
    # Check every compact frame too. A bar can snap small, slide back to its
    # source, then reach the correct endpoint without leaving the two columns.
    rebound = centers - np.minimum.accumulate(centers)
    worst = int(rebound.argmax())
    drift = max(abs(centers[folding] - source), default=0)
    width_step = max(abs(np.diff(widths)), default=0)
    errors = []
    if source <= resting + tolerance or abs(centers[-1] - resting) > tolerance or abs(widths[-1] - compact) > tolerance:
        errors.append("missing right-column or workspace-center endpoint")
    if len(set(middle_widths)) < 3 or width_step >= (opened - compact) / 2:
        errors.append("missing continuous fold")
    if max(widths - np.minimum.accumulate(widths)) > tolerance or drift > tolerance:
        errors.append("shell regrew or left the column during the fold")
    if rebound[worst] > tolerance or len(set(travelling)) < 3:
        errors.append("compact shell did not travel directly to center")
    # At this window size the reading seat is 16pt lower than Overview.
    # Demand an actual corner frame, then measure each locked axis all the
    # way to its endpoint. Diagonal motion also has monotone x and y.
    reading_top = resting_top + 16 * pixels_per_point
    arrived = np.flatnonzero((~folding) & (abs(centers - centers[-1]) <= 1))
    corner = None
    if len(arrived):
        turn = int(arrived[0])
        glide_tops = tops[:turn + 1][~folding[:turn + 1]]
        lift = tops[turn:]
        source_top = glide_tops[0]
        drift_y = float(max(abs(glide_tops - source_top)))
        drift_x = float(max(abs(centers[turn:] - resting)))
        middle = lift[(lift > resting_top + tolerance) & (lift < reading_top - tolerance)]
        lifting = np.flatnonzero(abs(lift - source_top) > tolerance)
        corner = dict(frame=turn, x=float(centers[turn]), top=float(tops[turn]),
                      sourceX=float(source), sourceTop=float(source_top), targetX=float(resting), targetTop=float(resting_top),
                      firstLiftFrame=turn + int(lifting[0]) if len(lifting) else None,
                      glideDriftYPx=drift_y, liftDriftXPx=drift_x, intermediateHeights=len(set(middle)))
        if (abs(source_top - reading_top) > tolerance or drift_y > tolerance or drift_x > tolerance
                or max(lift - np.minimum.accumulate(lift)) > tolerance):
            errors.append("bar left the reading height before arrival or left center during the lift")
        if len(set(middle)) < 3 or abs(tops[-1] - resting_top) > tolerance:
            errors.append("missing centered vertical lift")
    else:
        errors.append("missing horizontal-to-vertical corner")
    return dict(frames=len(widths), openWidthPx=int(opened), compactWidthPx=int(compact),
                intermediateWidths=len(set(middle_widths)), maxWidthStepPx=int(width_step),
                maxFoldCenterDriftPx=float(drift), maxRightwardReversalPx=float(rebound[worst]),
                reversalFrame=worst, corner=corner, errors=errors)


def check_column_return(movie, output, band):
    samples, width = measure(movie, output, band, include_columns=True)
    widths = [r[3] for r in samples]
    # The dark cap sits just inside the 168pt resting capsule.
    return column_return(widths, [r[4] for r in samples], [r[5] for r in samples],
                         widths[-1], (width - 1) / 2, samples[-1][5], widths[-1] / 168)


def check_report_send(movie, output, band):
    samples, width = measure(movie, output, band, include_columns=True)
    _, _, _, start_width, start_center, start_top = samples[0]
    centers = [r[4] for r in samples]
    errors = []
    if start_center <= width / 2 or start_width <= width / 5:
        errors.append("capture must start with the expanded right-column editor")
    # One encoded pixel of antialiased cap edge can change without layout travel.
    if any(abs(row[4] - start_center) > 1 or abs(row[5] - start_top) > 1
           or abs(row[3] - start_width) > 2 for row in samples):
        errors.append("editor left its submitted column or folded during the page turn")
    return dict(frames=len(samples), centerRangePx=[min(centers), max(centers)],
                topRangePx=[min(r[5] for r in samples), max(r[5] for r in samples)],
                widthRangePx=[min(r[3] for r in samples), max(r[3] for r in samples)], errors=errors)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("movie", type=Path)
    parser.add_argument("output", type=Path, help="CSV with every encoded frame")
    parser.add_argument("--band", nargs=2, type=int, metavar=("TOP", "BOTTOM"),
                        help="vertical search bounds in original pixels for a screen recording")
    parser.add_argument("--cycles", type=int, default=2)
    parser.add_argument("--reversal", action="store_true")
    scenario = parser.add_mutually_exclusive_group()
    scenario.add_argument("--report-send", action="store_true", help="a finished Report execution turning to its successor")
    scenario.add_argument("--column-return", action="store_true",
                        help="one Close from a settled right-column editor to a centered compact Dock")
    args = parser.parse_args()
    cv2.setNumThreads(1)
    if args.column_return:
        result = check_column_return(args.movie, args.output, args.band)
    elif args.report_send:
        result = check_report_send(args.movie, args.output, args.band)
    else:
        result = check(args.movie, args.output, args.band, args.cycles, args.reversal)
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(result["errors"]))
