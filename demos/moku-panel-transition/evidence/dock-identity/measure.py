"""Measure the Dock in the 2x dark workspace captures from this study."""

import argparse
import csv
import json
import math
import subprocess
from pathlib import Path

import cv2
import numpy as np


def components(mask):
    stats = cv2.connectedComponentsWithStats(mask.astype("uint8"), connectivity=8)[2]
    return [tuple(map(int, row)) for row in stats[1:]]


def glass_bounds(frame):
    height, width = frame.shape[:2]
    left, right = int(width * .20), int(width * .97)
    top = height - 105
    gray = cv2.cvtColor(frame[top:, left:right], cv2.COLOR_BGR2GRAY)
    # The cap is dark even at the point of maximum vertical travel. Use the
    # bright bottom rim between the rounded ends for the other vertical edge.
    for level in (15, 18, 21, 24, 27):
        caps = [box for box in components(gray < level) if 85 < box[2] < 590 and 4 < box[3] < 65]
        if caps:
            break
    if not caps:
        return None
    x, y, width, _, _ = max(caps, key=lambda box: box[4])
    strip = gray[:, x + width // 4:x + 3 * width // 4].astype(np.int16)
    # A rim is a shared edge across columns. Taking the difference first
    # keeps the notification text baseline from registering as the rim.
    fall = np.median(strip[:-1] - strip[1:], axis=1)
    start, end = y + 27, min(y + 70, len(fall))
    if end <= start:
        return None
    rim = start + int(np.argmax(fall[start:end]))
    return x + left, y + top, x + left + width - 1, rim + top


def eye_pairs(bright, scale=1):
    # A nearly edge-on face can be only two raster lines high at either
    # resolution. Size, spacing and isolation otherwise stay in points.
    parts = [(x, y, w, h, area) for x, y, w, h, area in components(bright)
             if 2 <= w / scale <= 17 and 2 <= h <= 27 * scale
             and 6 <= area / scale**2 <= 300 and area > .47 * w * h]
    for i, (x, y, w, h, area) in enumerate(parts):
        for xx, yy, ww, hh, other_area in parts[i + 1:]:
            separation = abs(xx + ww / 2 - x - w / 2)
            if not (9 <= separation / scale <= 23 and abs(yy + hh / 2 - y - h / 2) <= 3 * scale
                    and .66 < hh / h < 1.5 and .48 < other_area / area < 2.1):
                continue
            x0, x1 = min(x, xx), max(x + w, xx + ww)
            y0, y1 = min(y, yy), max(y + h, yy + hh)
            # The two eyes are isolated. Most title and transcript glyphs have
            # neighboring text in this ring. Review remaining candidates on film.
            region = bright[max(0, y0 - 6 * scale):y1 + 6 * scale, max(0, x0 - 11 * scale):x1 + 11 * scale]
            if region.sum() - area - other_area <= 4 * scale**2 and (h >= w * .9 or h <= 5 * scale):
                yield "eyes", (x0, y0, x1 - 1, y1 - 1)


def marks(frame, scale=1):
    blue, green, red = cv2.split(frame)
    neutral = (red > 155) & (green > 155) & (blue > 155) & (cv2.absdiff(red, blue) < 30)
    yield from eye_pairs(neutral, scale)
    purple = (blue > 110) & (cv2.subtract(blue, red) > 48) & (cv2.subtract(blue, green) > 50)
    for x, y, width, height, area in components(purple):
        if 16 <= width / scale <= 28 and 2 <= height <= 29 * scale and area > .51 * width * height:
            yield "logo", (x, y, x + width - 1, y + height - 1)


def clearance(shell, ink):
    left, top, right, bottom = shell
    radius = (bottom - top) / 2
    mid_y = (top + bottom) / 2
    # Signed inward distance for the least-contained corner of the ink box.
    return min(radius - math.hypot(max(0, left + radius - x, x - right + radius), y - mid_y)
               for x in (ink[0], ink[2]) for y in (ink[1], ink[3]))


def measure(video, output, reference):
    probe = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
                                     "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", video])
    stamps = json.loads(probe)["frames"]
    capture = cv2.VideoCapture(str(video))
    with output.open("w", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(["frame", "pts_s", "glass_left", "glass_top", "glass_right", "glass_bottom",
                         "candidate", "ink_left", "ink_top", "ink_right", "ink_bottom", "clearance"])
        for index, stamp in enumerate(stamps):
            pts = stamp["best_effort_timestamp_time"]
            if reference and float(pts) > 7.15:
                break  # The system recording UI covers the remaining reference frames.
            ok, frame = capture.read()
            if not ok:
                raise ValueError(f"Missing video frame {index}")
            expected = (2304, 4096) if reference else (2250, 3770)
            if frame.shape[:2] != expected:
                raise ValueError(f"Expected {expected} capture, got {frame.shape[:2]}")
            frame = cv2.resize(frame, None, fx=.5, fy=.5, interpolation=cv2.INTER_AREA)
            if reference:
                frame = frame[:1125, 101:1986]
            shell = glass_bounds(frame)
            candidates = list(marks(frame)) or [("unresolved", None)]
            for kind, ink in candidates:
                margin = round(clearance(shell, ink), 2) if shell and ink else None
                writer.writerow([index, pts, *(shell or [None] * 4), kind, *(ink or [None] * 4), margin])
    capture.release()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path)
    parser.add_argument("csv", type=Path)
    parser.add_argument("--reference", action="store_true", help="crop the user's full-display recording")
    args = parser.parse_args()
    cv2.setNumThreads(1)
    measure(args.video, args.csv, args.reference)
