"""Check every displayed frame of the 720 × 260 pt --directory-removal replay."""
import sys
from pathlib import Path

import cv2
import numpy as np


def check(folder):
    movie = cv2.VideoCapture(str(folder / "window.mp4"))
    templates = {}
    tops, arrow_contrast = [], []
    max_drift = 0
    try:
        while True:
            ok, pixels = movie.read()
            if not ok:
                break
            gray = cv2.cvtColor(pixels, cv2.COLOR_BGR2GRAY)
            if gray.shape != (520, 1440):
                raise ValueError("Expected the replay's native 2× window recording")
            frame = len(tops)
            # Sample the glass away from the chip, editor text and controls.
            shell = np.flatnonzero(gray[:, 900] < 96)
            if not shell.size:
                raise ValueError(f"Missing glass in frame {frame}")
            tops.append(int(shell[0]) / 2)
            for name, x in [("Send", 1222), ("plus", 286)]:
                y = 414
                left, top = x - 24, y - 130
                # Remove the glass gradient from the glyph, especially where
                # the disabled arrow fades into the lighter collapsed glass.
                region = gray[top:y + 90, left:x + 26]
                ink = cv2.morphologyEx(region, cv2.MORPH_TOPHAT, np.ones((11, 11), np.uint8))
                reference_x, reference_y = x - 12 - left, y - 12 - top
                if frame == 0:
                    templates[name] = ink[reference_y:reference_y + 26, reference_x:reference_x + 26].copy()
                    if templates[name].std() < 10:
                        raise ValueError(f"Missing initial {name} glyph")
                scores = cv2.matchTemplate(ink, templates[name], cv2.TM_CCOEFF_NORMED)
                _, score, _, (gx, gy) = cv2.minMaxLoc(scores)
                dx, dy = (gx - reference_x) / 2, (gy - reference_y) / 2
                if score < 0.85:
                    raise ValueError(f"Cannot locate a complete {name} in frame {frame}, correlation {score:.2f}")
                max_drift = max(max_drift, abs(dx), abs(dy))
                if max_drift > 1:
                    raise ValueError(f"{name} displaced by ({dx}, {dy}) pt in frame {frame}")
                if name == "Send":
                    arrow_contrast.append(ink[gy:gy + 26, gx:gx + 26].std())
        if len(tops) != int(movie.get(cv2.CAP_PROP_FRAME_COUNT)) or len(tops) < 2:
            raise ValueError("Incomplete directory removal recording")
    finally:
        movie.release()
    # A single directory strip reserves 9 + 28 + 6 pt. The disabled Send
    # remains visible at the same seat after removal in an idle Overview.
    if abs(tops[-1] - tops[0] - 43) > 1 or len(set(tops)) < 4 or min(np.diff(tops)) < -1:
        raise ValueError(f"Unexpected capsule contraction: {tops}")
    if not 0.15 < arrow_contrast[-1] / arrow_contrast[0] < 0.55:
        raise ValueError("Expected Send to dim after removal")
    print(f"{len(tops)} frames, {tops[-1] - tops[0]} pt contraction, max glyph drift {max_drift} pt")


if __name__ == "__main__":
    check(Path(sys.argv[1]))
