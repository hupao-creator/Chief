"""Replay startup admission and the Running empty state in one native window."""
from contextlib import ExitStack
import sys
import time
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "tools/verification"))
sys.path.insert(0, str(repo / "tools/benchmarks"))
from native_replay import NativeReplay
from gate.ux import ui_lease

if __name__ == "__main__":
    evidence = Path(sys.argv[1]).resolve()
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
            try:
                result = fixture.run([], timeout=60)
                if result or not (fixture.workspace / "evidence/result.txt").is_file():
                    raise RuntimeError("Native replay did not finish. See " + str(evidence))
            finally:
                fixture.export(evidence)
    finally:
        fixture.close()
