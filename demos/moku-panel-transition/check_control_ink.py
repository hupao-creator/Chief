"""Measure the action and status seats in a production Dock --control-ink movie."""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np

from check_overview import read_frames


def check(folder):
    receipt = json.loads((folder / "observations.json").read_text())
    if not receipt["foregroundUnchanged"]:
        raise ValueError("Capture changed the foreground owner")
    reduced = receipt["reduceMotion"]
    events = {row["event"]: row["seconds"] for row in receipt["events"]}
    frames, bands = read_frames(folder)
    times = np.array([row["pts"] for row in frames])

    def interval(start, end):
        selected = (times >= start) & (times < end)
        if not selected.any():
            raise ValueError(f"No displayed frame in {start:.3f}–{end:.3f}s")
        return selected

    # Both coordinates are in window points, relative to the same band as the
    # Overview geometry checker. Use the movie's own settled icons as references.
    seat = bands[:, 14:57, 590:632].astype(float)
    stop = seat[0]
    send = seat[interval(events["same-role"] - .12, events["same-role"] + .12)].mean(axis=0)
    difference = send - stop
    if np.max(np.abs(difference)) < 70:
        raise ValueError("Missing distinct settled action glyphs")
    progress = ((seat - stop) * difference).sum(axis=(1, 2)) / (difference ** 2).sum()
    legs = {}
    for name, end in [("send", "same-role"), ("stop", "partial-send"), ("partial-send", "fold")]:
        values = progress[interval(events[name] - .035, events[end])]
        legs[name] = values.round(3).tolist()
        intermediate = np.any((values > .08) & (values < .92))
        if reduced and intermediate:
            raise ValueError(f"Reduced motion interpolated {name}: {legs[name]}")
        if not reduced and not intermediate:
            raise ValueError(f"No intermediate action ink on {name}: {legs[name]}")
        if not reduced and name == "partial-send" and not (.12 < values.max() < .98 and values[-1] < .06):
            raise ValueError(f"Action ink missed the partial return: {legs[name]}")
    editing = interval(0, events["fold"] - .05)
    if any(abs(f["width"] - 560) > 2 or abs(f["center"] - 359.5) > 2
           for f, admitted in zip(frames, editing) if admitted):
        raise ValueError("Typing or changing the action moved the shell")
    steady = progress[interval(events["same-role"], events["stop"] - .035)]
    if max(abs(steady - 1)) > .08:
        raise ValueError("Typing restarted the Send reveal")

    # Remove the slowly varying glass background. The first part of the label
    # excludes the configuration, which is free to move when the sentence fits.
    statuses = {}
    for region, left, right in [("status", 246, 337), ("configuration", 356, 415)]:
        area = bands[:, 20:50, left:right]
        ink = np.array([cv2.morphologyEx(row, cv2.MORPH_TOPHAT, np.ones((7, 7), np.uint8))
                        for row in area], dtype=float)
        for name, end in [("started", "next-dispatch"), ("failed", None)]:
            t = events[name]
            before = ink[np.flatnonzero(times < t - .045)[-1]]
            after = ink[np.flatnonzero(times < (events[end] - .045 if end else times[-1] + 1))[-1]]
            old = (before > 90) & (after < 20)
            new = (after > 90) & (before < 20)
            if min(old.sum(), new.sum()) < 10:
                raise ValueError(f"Cannot distinguish {region} letters for {name}")
            rows = ink[interval(t - .045, events[end] - .045 if end else times[-1] + 1)]
            a = rows[:, old].mean(axis=1) / before[old].mean()
            b = rows[:, new].mean(axis=1) / after[new].mean()
            key = f"{name}-{region}"
            statuses[key] = np.stack([a, b], axis=1).round(3).tolist()
            if min(a[0], b[-1]) < .8 or np.max(np.minimum(a, b)) > .16:
                raise ValueError(f"Missing or superimposed status on {name}: {statuses[key]}")
            outgoing = np.any((a > .1) & (a < .9))
            incoming = np.any((b > .1) & (b < .9))
            if reduced and (outgoing or incoming):
                raise ValueError(f"Reduced motion interpolated {name}: {statuses[key]}")
            if not reduced and not (outgoing and incoming):
                raise ValueError(f"Status skipped intermediate ink on {name}: {statuses[key]}")
    return dict(frames=len(frames), reduceMotion=reduced, actionLegs=legs, statusLegs=statuses,
                sameRoleMaxDeviation=float(max(abs(steady - 1))),
                samples=[dict(row, action=round(float(v), 3)) for row, v in zip(frames, progress)])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = check(args.folder)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Checked {result['frames']} frames")
