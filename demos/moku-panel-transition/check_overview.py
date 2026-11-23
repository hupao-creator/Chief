"""Measure the capsule and Stop in a 720 × 260pt Overview window replay."""
import argparse
import itertools
import json
import subprocess
from pathlib import Path

import cv2
import numpy as np


# Use one ink threshold for the square and its exclusion from the text seat.
# During a fade the entire Stop can be dimmer than the settled glyph.
CONTROL_INK = 140


def read_frames(folder):
    movie = str(folder / "window.mp4")
    info = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
                                    "frame=best_effort_timestamp_time", "-of", "json", movie])
    # Use movie presentation timestamps for evidence. Assign consecutive output
    # timestamps to the raw decoder so it emits each variable-rate frame once.
    pixels = subprocess.check_output(["ffmpeg", "-loglevel", "error", "-i", movie, "-vf",
        "scale=720:260,format=gray,setpts=N/60/TB", "-enc_time_base", "1:1000000",
        "-fps_mode", "passthrough", "-f", "rawvideo", "-"])
    frames = json.loads(info)["frames"]
    size = 720 * 260
    if len(pixels) != len(frames) * size:
        raise ValueError("Movie timestamps and decoded frames differ")
    images = np.frombuffer(pixels, dtype=np.uint8).reshape(-1, 260, 720)
    return [measure(float(frame["best_effort_timestamp_time"]), image.tobytes())
            for frame, image in zip(frames, images)], images[:, 172:242]


def measure(pts, image):
    # The middle band crosses the full dark silhouette in both seats.
    rows = [image[y * 720:(y + 1) * 720] for y in range(198, 219)]
    dark = [x for x in range(720) if any(row[x] < 96 for row in rows)]
    if not dark:
        raise ValueError(f"Missing capsule at {pts}s")
    left, right = dark[0], dark[-1]
    # A fading square can occupy only seven pixels on five scanlines. Also
    # require a filled two-dimensional mark: strokes in a moving dispatch
    # label can have the same horizontal run length on separate scanlines.
    band = np.frombuffer(image, np.uint8).reshape(260, 720)[190:225, 376:right - 6]
    stop = stop_center(band, pts)
    return {"pts": pts, "width": right - left + 1, "center": (left + right) / 2, "stopInset": right - stop if stop is not None else None}


def stop_center(band, pts, scale=1):
    boxes = cv2.connectedComponentsWithStats((band > CONTROL_INK).astype("uint8"))[2][1:] if band.size else []
    stops = [376 + (x + w / 2) / scale - .5 for x, _, w, h, area in boxes
             if 7 * scale <= w <= 12 * scale and 5 * scale <= h <= 12 * scale
             and abs(w - h) <= 2 * scale and area >= .85 * w * h]
    if len(stops) > 1:
        raise ValueError(f"Multiple Stop marks at {pts}s")
    return stops[0] if stops else None


def eye_margin(band, scale=1):
    # Search the full panel. The white eye cores are brighter than even the
    # plain backdrop, so an escaped pair is still counted outside the dark shell.
    components = cv2.connectedComponentsWithStats((band > 245).astype("uint8"))[2][1:]
    eyes = [(x, y, w, h, area) for x, y, w, h, area in components
            if 3 * scale <= w <= 14 * scale and 2 * scale <= h <= 23 * scale and area >= .45 * w * h]
    margins = []
    for i, (x, y, w, h, area) in enumerate(eyes):
        for xx, yy, ww, hh, other in eyes[i + 1:]:
            if not (10 * scale <= abs(x - xx) <= 23 * scale and abs(y - yy) <= 4 * scale
                    and abs(h - hh) <= 3 * scale and .65 <= other / area <= 1.55):
                continue
            for edge_y in (min(y, yy), max(y + h, yy + hh) - 1):
                dark = np.flatnonzero(band[edge_y] < 150)
                if not dark.size:
                    raise ValueError("Eyes visible on a scanline outside the capsule")
                margins.append(float(min(min(x, xx) - dark[0], dark[-1] - max(x + w - 1, xx + ww - 1))) / scale)
    return min(margins, default=None)


def measure_native_ink(folder, frames):
    # A downsample can remove the white cores of a closing blink. Apply the
    # same contrast, point dimensions, fill ratio and edge tests to the
    # original 2x pixels before classifying that displayed frame as unresolved.
    # At partial opacity the same downsample can erase a filled Stop corner.
    eyes, stops = [], []
    movie = cv2.VideoCapture(str(folder / "window.mp4"))
    try:
        for index, frame in enumerate(frames):
            ok, pixels = movie.read()
            if not ok or pixels.shape[:2] != (520, 1440):
                raise ValueError(f"Missing native-scale frame {index}")
            if frame["eyeMargin"] is None:
                band = cv2.cvtColor(pixels[344:484], cv2.COLOR_BGR2GRAY)
                frame["eyeMargin"] = eye_margin(band, scale=2)
                if frame["eyeMargin"] is not None:
                    eyes.append(index)
            if frame["stopInset"] is None:
                right = round(frame["center"] + (frame["width"] - 1) / 2)
                band = cv2.cvtColor(pixels[380:450], cv2.COLOR_BGR2GRAY)[:, 752:2 * (right - 6)]
                stop = stop_center(band, frame["pts"], scale=2)
                if stop is not None:
                    frame["stopInset"] = right - stop
                    stops.append(index)
        if movie.read()[0]:
            raise ValueError("Unexpected additional native-scale frame")
    finally:
        movie.release()
    return eyes, stops


def check_rows(frames, bands):
    # Sample the model name and the placeholder from their settled seats. Search
    # the whole moving row for each independently, including during a crossfade.
    parked = [i for i, f in enumerate(frames) if f["width"] == 400]
    if not parked:
        raise ValueError("Missing settled dispatch")
    model = bands[parked[len(parked) // 2]][25:44, 336:399]
    prompt = bands[-1][25:44, 170:214]
    if min(model.std(), prompt.std()) < 15:
        raise ValueError("Unreadable dispatch or editor reference")
    def locate(band, glyphs):
        region = band[15:54]
        match = cv2.matchTemplate(region, glyphs, cv2.TM_CCOEFF_NORMED)
        _, score, _, (x, y) = cv2.minMaxLoc(match)
        sample = region[y:y + glyphs.shape[0], x:x + glyphs.shape[1]]
        return score > .72 and sample.std() > .12 * glyphs.std()
    dispatch_frames = editor_frames = 0
    for f, band in zip(frames, bands):
        dispatch, editor = locate(band, model), locate(band, prompt)
        dispatch_frames += int(dispatch)
        editor_frames += int(editor)
        if dispatch and editor:
            raise ValueError(f"Dispatch and editor both visible at {f}")
        if dispatch:
            right = round(f["center"] + (f["width"] - 1) / 2)
            seat = band[25:45, right - 45:right - 9].copy()
            if f["stopInset"] is not None:
                mark = round(45 - f["stopInset"])
                seat[:, max(0, mark - 6):max(0, mark + 7)] = 0
            if (seat > CONTROL_INK).sum() >= 5:
                raise ValueError(f"Dispatch ink in trailing control seat at {f}")
    if min(dispatch_frames, editor_frames) < 3:
        raise ValueError("Insufficient readable dispatch or editor frames")
    return dict(dispatchFrames=dispatch_frames, editorFrames=editor_frames)


def check(folder):
    receipt = json.loads((folder / "observations.json").read_text())
    scene = receipt["running"]
    expected_inputs = [True, False, True, False, True, False, True] if scene else [True, False, True]
    if receipt["inputChanges"] != expected_inputs:
        raise ValueError("Overview replay did not complete the expected input changes")
    frames, bands = read_frames(folder)
    for f, band in zip(frames, bands):
        f["eyeMargin"] = eye_margin(band)
    native_eyes, native_stops = measure_native_ink(folder, frames)
    def phase(frame):
        if frame["width"] < 174:
            return "compact"
        return "open" if frame["width"] > 554 else "travel"
    phases = [(kind, list(group)) for kind, group in itertools.groupby(frames, phase)]
    expected = ["compact", "travel", "open", "travel", "compact", "travel", "open"]
    if scene:
        expected += ["travel", "open", "travel", "compact", "travel", "open"]
    if [kind for kind, _ in phases] != expected:
        raise ValueError(f"Missing or out-of-order input transitions: {[p for p, _ in phases]}")

    # Both widths share the 720pt fixture's bottom-center anchor. Check every
    # frame, including compact-width frames sliding back from the open left edge.
    worst = max(frames, key=lambda f: abs(f["center"] - 359.5))
    for kind, group in phases:
        if kind == "travel" and len({f["width"] for f in group}) < 3:
            raise ValueError("Insufficient intermediate widths")
        located = sum(f["eyeMargin"] is not None for f in group)
        if located < len(group) * 2 / 3:
            raise ValueError(f"Too few measurable eye pairs in {kind} at {group[0]} ({located}/{len(group)})")
    margins = [f for f in frames if f["eyeMargin"] is not None]
    least = min(margins, key=lambda f: f["eyeMargin"])
    if least["eyeMargin"] < -2:
        raise ValueError(f"Eyes outside the capsule at {least}")
    step, jump = max(((abs(b["width"] - a["width"]), b) for a, b in zip(frames, frames[1:])),
                     key=lambda pair: pair[0])
    if step >= (560 - 168) / 2:
        raise ValueError(f"Capsule skipped at least half its travel in one frame at {jump}")
    if abs(worst["center"] - 359.5) > 2:
        raise ValueError(f"Capsule left the Overview center at {worst}")
    result = dict(locale=receipt["locale"], frames=len(frames), nativeScaleEyeFrames=native_eyes, nativeScaleStopFrames=native_stops, worstCenterFrame=worst,
                  measuredEyes=len(margins), leastEyeMarginFrame=least, largestWidthStep=step,
                  phases=[dict(phase=kind, first=group[0]["pts"], last=group[-1]["pts"],
                               distinctWidths=len({f["width"] for f in group}),
                               visibleStopFrames=sum(f["stopInset"] is not None for f in group))
                          for kind, group in phases])
    if scene:
        reversal = phases[7][1]
        if min(f["width"] for f in reversal) >= 520:
            raise ValueError("No visible partial fold before reopening")
        stops = [f for f in frames if f["stopInset"] is not None]
        if not stops:
            raise ValueError("Running Chief never displayed Stop")
        nearest = min(stops, key=lambda f: f["stopInset"])
        farthest = max(stops, key=lambda f: f["stopInset"])
        # The centers are 22pt and 29pt from the trailing edge. Allow two
        # points for the optical silhouette and rounding of the square.
        errors = []
        if nearest["stopInset"] < 20 or farthest["stopInset"] > 31:
            errors.append("Stop left its trailing seats")
        try:
            result.update(check_rows(frames, bands))
        except ValueError as error:
            errors.append(str(error))
        return dict(result, nearestStopFrame=nearest, farthestStopFrame=farthest, errors=errors)

    # Read the visible seats from the rendered endpoints, allowing two
    # points for the antialiased silhouette and square center in the movie.
    def settled_inset(phase_index, width):
        values = [f["stopInset"] for f in phases[phase_index][1]
                  if f["width"] == width and f["stopInset"] is not None]
        if not values:
            raise ValueError(f"No settled Stop at {width}pt")
        return sorted(values)[len(values) // 2]
    compact = settled_inset(0, 168)
    expanded = settled_inset(2, 560)
    if not (abs(compact - 22) <= 2 and abs(expanded - 29) <= 2):
        raise ValueError(f"Stop outside its trailing seats: {compact}, {expanded}")
    for index, (kind, group) in enumerate(phases):
        if kind != "travel":
            continue
        for frame in group:
            inset = frame["stopInset"]
            if inset is None and index == 3:
                continue  # Outside press retires hover ink on the return.
            if inset is None or not compact - 2 <= inset <= expanded + 2:
                raise ValueError(f"Stop left its trailing seats ({compact}, {expanded}) at {frame}")
    return dict(result, compactInset=compact, expandedInset=expanded)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    result = check(parser.parse_args().capture)
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(result.get("errors")))
