"""Track both filters against their resting ink in a 2× tag-return movie."""
import argparse
import csv
import json
from pathlib import Path
import subprocess

import numpy as np


def track(movie, crop, width, height, axis, seat):
    # One projection retains horizontal travel in the rail, the other vertical
    # travel in the header. Centering the reference removes a uniform backdrop.
    data = subprocess.check_output(["ffmpeg", "-v", "error", "-i", movie, "-vf", f"crop={crop}",
                                    "-enc_time_base", "demux", "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "gray", "-"])
    frames = np.frombuffer(data, dtype=np.uint8).reshape(-1, height, width).mean(axis=axis)
    lo, hi = seat
    reference = frames[0, lo:hi]
    ink = reference - reference.mean()
    if np.ptp(reference) < 20:
        raise ValueError("Missing reference label in the opening Overview")
    offsets = range(-36, 6)
    strength = np.stack([frames[:, lo + dx:hi + dx] @ ink for dx in offsets], axis=1) / (ink @ ink)
    best = strength.argmax(axis=1)
    return strength[np.arange(len(frames)), best], (best + offsets.start) / 2


def measure(directory):
    movie = directory / "window.mp4"
    info = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
        "stream=width,height:frame=best_effort_timestamp_time", "-of", "json", movie]))
    if info["streams"] != [{"width": 2560, "height": 1640}]:
        raise ValueError("Expected the 1280 × 820 pt replay window at 2×")
    timestamps = [float(f["best_effort_timestamp_time"]) for f in info["frames"]]
    left, dx = track(movie, "130:52:0:794", 130, 52, 1, (42, 94))
    top, dy = track(movie, "160:126:1224:0", 160, 126, 2, (63, 95))
    if len(timestamps) != len(left) or len(left) != len(top):
        raise ValueError("Decoded frames do not match presentation timestamps")
    rows = list(zip(timestamps, left, dx, top, dy))
    with (directory / "filter-frames.csv").open("w", newline="") as out:
        writer = csv.writer(out)
        writer.writerow(["seconds", "leftContrast", "leftOffsetPt", "topContrast", "topOffsetPt"])
        writer.writerows(rows)
    return rows


def check(directory, reduced):
    rows = measure(directory)
    events = json.loads((directory / "events.json").read_text())
    actions = [e["action"] for e in events]
    if actions != ["open", "close", "overview", "open", "close", "reopen", "close", "overview"]:
        raise ValueError(f"Unexpected Report visit sequence: {actions}")

    def between(start, end):
        return [row for row in rows if start <= row[0] < end]

    def positions(leg):
        return [(dx, dy) for _, left, dx, top, dy in leg if min(left, top) >= .10]

    def travel(samples, direction):
        # Require distinct intermediate positions in order along both axes.
        # This rejects a simultaneous fade at the destination as well as a snap.
        middle = [(dx, dy) for dx, dy in samples if max(dx, dy) <= -1]
        if (len(set(middle)) < 3 or any(abs(dx - dy) > 2 for dx, dy in samples)
                or min(direction * (b - a) for a, b in zip(middle[0], middle[-1])) < 2):
            raise ValueError(f"Missing coordinated travel: {samples}")
        for before, after in zip(samples, samples[1:]):
            if any(direction * (b - a) < -1 for a, b in zip(before, after)):
                raise ValueError(f"Filter changed direction during travel: {before}, {after}")

    if not reduced:
        for start, end in [(0, 1), (3, 4)]:
            travel(positions(between(events[start]["seconds"], events[end]["seconds"])), -1)
    for start, end in [(1, 2), (6, 7)]:
        leg = between(events[start]["seconds"], events[end]["seconds"])
        for threshold in [.25, .50, .85]:
            crossing = [next((r[0] for r in leg if r[i] >= threshold), None) for i in (1, 3)]
            if None in crossing or abs(crossing[0] - crossing[1]) > .040:
                raise ValueError(f"Filter reveals separated at {threshold}: {crossing}")
        if not reduced:
            travel(positions(leg), 1)
    interrupted = positions(between(events[4]["seconds"], events[6]["seconds"]))
    if not interrupted:
        raise ValueError("The interrupted return contained no visible filters")
    if reduced:
        if any(max(abs(x), abs(y)) > 1 for x, y in positions(rows)):
            raise ValueError("Filters moved with Reduce Motion enabled")
    else:
        # The action clock timestamps input submission. Find the reversal on the
        # display clock so compositor latency cannot assign a frame to the wrong leg.
        turn = max(range(len(interrupted)), key=lambda i: sum(interrupted[i]))
        if max(interrupted[turn]) >= -1:
            raise ValueError("Filters reached their seats before reversing")
        travel(interrupted[:turn + 1], 1)
        travel(interrupted[turn:], -1)
    for index in [2, 7]:
        end = events[index]["seconds"]
        settled = between(end + .15, end + .40)
        if not settled or any(min(left, top) < .85 or max(abs(dx), abs(dy)) > 1
                              for _, left, dx, top, dy in settled):
            raise ValueError(f"Filters missed their original seats after event {index}")
    covered = between(events[5]["seconds"] + .45, events[6]["seconds"])
    if not covered or any(max(left, top) > .08 for _, left, _, top, _ in covered):
        raise ValueError("Filters stayed visible under the reopened Report")
    print(f"Verified both returns, interrupted return and original seats across {len(rows)} native frames")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--reduced", action="store_true")
    args = parser.parse_args()
    check(args.directory, args.reduced)
