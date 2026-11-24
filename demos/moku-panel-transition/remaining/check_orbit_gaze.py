"""Measure dot and eye centres in each composited orbit-gaze window frame."""
import argparse
import csv
import json
from pathlib import Path
import subprocess

import cv2
import numpy as np


def centers(mask, min_width, max_width, min_height, max_height, min_area):
    boxes = cv2.connectedComponentsWithStats(mask.astype("uint8"))[2][1:]
    return [(x + w / 2, y + h / 2) for x, y, w, h, area in boxes
            if min_width <= w <= max_width and min_height <= h <= max_height and area >= min_area]


def positions(directory):
    movie = directory / "window.mp4"
    stamps = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
        "frame=best_effort_timestamp_time", "-of", "json", movie]))["frames"]
    capture = cv2.VideoCapture(str(movie))
    rows = []
    try:
        for frame, stamp in enumerate(stamps):
            ok, image = capture.read()
            if not ok or image.shape[:2] != (1280, 1640):
                raise ValueError(f"Missing 2× window at frame {frame}")
            ink = image[1090:1240, 610:1030].astype("int16")
            dots = centers(ink.max(2) - ink.min(2) > 18, 4, 15, 4, 15, 14)
            eyes = centers(image[1140:1206, 718:920].min(2) > 185, 5, 30, 2, 60, 10)
            dot_x, dot_y = np.mean(dots, axis=0) + (610, 1090) if dots else (None, None)
            eye_x, eye_y = np.mean(eyes, axis=0) + (718, 1140) if eyes else (None, None)
            rows.append(dict(frame=frame, pts=float(stamp["best_effort_timestamp_time"]), dots=len(dots),
                             dotX=dot_x, dotY=dot_y, eyes=len(eyes), eyeX=eye_x, eyeY=eye_y))
        if capture.read()[0]:
            raise ValueError("Missing frame timestamps")
    finally:
        capture.release()
    with (directory / "positions.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=rows[0], lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    return rows


def check(directory):
    rows = positions(directory)
    events = {r["action"]: r["seconds"] for r in json.loads((directory / "events.json").read_text())}

    def between(start, end):
        return [r for r in rows if start < r["pts"] < end]

    result = {}
    # Recordings with a relay mark the start of each pursuit interval.
    # Earlier recordings started a lap at entry and at each reversal.
    for label, marker, entry, end in [
            ("first lap", "first lap", "start", "pause"), ("resumed", "resume", "resume", "retire"),
            ("reversed", "reversed lap", "reverse fade", "open editor"),
            ("folded", "folded lap", "close editor again", "finish")]:
        start = events[marker] + .1 if marker in events else events[entry] + .65
        group = between(start, events[end] - .08)
        visible = [r for r in group if r["eyes"] == 2 and r["dots"] == 3]
        correlation = [float(np.corrcoef([r["dot" + axis] for r in visible],
                                         [r["eye" + axis] for r in visible])[0, 1]) for axis in ("X", "Y")]
        result[label] = dict(frames=len(group), resolved=len(visible), correlation=correlation,
                             passed=len(visible) >= max(12, .85 * len(group)) and all(value > .8 for value in correlation))
    paused = between(events["pause"] + .16, events["resume"] - .06)
    coords = [(r["dotX"], r["dotY"], r["eyeX"], r["eyeY"]) for r in paused if r["dots"] == 3 and r["eyes"] == 2]
    result["paused"] = dict(frames=len(paused), passed=len(coords) == len(paused) >= 5 and float(np.ptp(coords, axis=0).max()) <= 1)
    for label, start, end in [("editor", events["open editor"] + .45, events["close editor"]),
                              ("reopened", events["reopen editor"] + .13, events["close editor again"]),
                              ("idle", events["finish"] + .65, rows[-1]["pts"])]:
        group = between(start, end - .05)
        result[label] = dict(frames=len(group), passed=bool(group) and all(r["dots"] == 0 for r in group))
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    cv2.setNumThreads(1)
    result = check(args.directory)
    (args.directory / "gaze.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))
    raise SystemExit(0 if all(part["passed"] for part in result.values()) else 1)
