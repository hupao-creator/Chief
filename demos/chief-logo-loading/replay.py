"""Replay startup admission and the Running empty state in one native window."""
from contextlib import ExitStack
from itertools import groupby
import json
import subprocess
import sys
import time
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "tools/verification"))
sys.path.insert(0, str(repo / "tools/benchmarks"))
from native_replay import NativeReplay
from gate.ux import ui_lease


def verify_handle(directory):
    # Scan one column through the handle, well clear of the agents, text and
    # chrome. In the 2× dark recording its upper and lower outlines are bright.
    movie = directory / "window.mp4"
    stripe = subprocess.check_output([
        "ffmpeg", "-v", "error", "-sseof", "-2.2", "-i", str(movie),
        "-vf", "crop=4:240:iw/2+210:ih/2-150",
        "-enc_time_base", "demux", "-fps_mode", "passthrough", "-pix_fmt", "rgb24", "-f", "rawvideo", "-",
    ])
    row_bytes = 4 * 3
    frame_bytes = 240 * row_bytes
    samples = []
    for start in range(0, len(stripe), frame_bytes):
        frame = stripe[start:start + frame_bytes]

        def bright(y):
            return sum(frame[y * row_bytes:y * row_bytes + 3]) > 300

        edges = [next(rows) for ink, rows in groupby(range(240), bright) if ink]
        samples.append(edges)
    (directory / "handle-rows.json").write_text(json.dumps(samples))
    if not samples or any(len(edges) != 2 for edges in samples):
        raise RuntimeError(f"Missing or doubled handle outline in {movie}")
    tops = [edges[0] for edges in samples]
    travel = tops[0] - tops[-1]
    steps = [abs(a - b) for a, b in zip(tops, tops[1:])]
    if travel < 24 or max(steps, default=0) > travel / 3:
        raise RuntimeError(f"Handle skipped its travel in {movie}: {travel}px, steps {steps}")
    return f"{len(samples)} frames, handle travel {travel}px, largest step {max(steps)}px at 2×"


if __name__ == "__main__":
    evidence = Path(sys.argv[1]).resolve()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=repo))
    fixture = NativeReplay(repo, "ChiefLoadingReplay", "com.chief.replay.loading")
    try:
        fixture.compile([Path(__file__).with_name("Replay.swift")])
        with ExitStack() as stack:
            while True:
                try:
                    stack.enter_context(ui_lease())
                    break
                except FileExistsError:
                    time.sleep(0.5)
            fixture.acquire()
            for case in ("empty", "reduced", "populated", "onboarding", "error", "landing"):
                destination = evidence / case
                capture = fixture.workspace / "evidence"
                try:
                    result = fixture.run(["--" + case], timeout=60)
                    if result or not (capture / "result.txt").is_file():
                        raise RuntimeError(f"Native {case} replay did not finish. See {destination}")
                finally:
                    fixture.export(destination)
                    (destination / "revision.txt").write_text(revision + (" (dirty)" if dirty else "") + "\n")
                if case == "empty":
                    with (destination / "result.txt").open("a") as result_file:
                        result_file.write(verify_handle(destination) + "\n")
                capture.rename(fixture.workspace / case)
    finally:
        fixture.close()
