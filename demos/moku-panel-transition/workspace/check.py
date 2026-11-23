"""Check all movies and native outcomes from one capture.py campaign."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

DEMO = Path(__file__).resolve().parent.parent


def read(path):
    return json.loads(path.read_text())


def check(directory, pending, started):
    build = read(directory / "build.json")
    results = {}
    for name, args in [
        ("overview", ["check_workspace_folds.py", directory / "overview/window.mp4",
                      directory / "overview.csv", "--reversal"]),
        ("execution-return", ["check_workspace_folds.py", directory / "execution-return/window.mp4",
                              directory / "execution-return.csv", "--column-return"]),
        ("mounted-overview", ["check_overview.py", directory / "overview-zh-Hans-motion-scene"]),
        ("agent", ["check_frames.py", directory / "agent-entrance"]),
        ("first-card", ["check_landing_handoff.py", directory / "first-card/window.mp4",
                        str(pending), str(started), directory / "first-card-samples.json"]),
        *((f"reader-{i}", ["check_centered_handoff.py", directory / f"reader-{i}/window.mp4",
                           directory / f"reader-{i}.csv"]) for i in range(2)),
    ]:
        with (directory / (name + "-check.json")).open("w") as output, (directory / (name + "-check.stderr")).open("w") as errors:
            run = subprocess.run([sys.executable, DEMO / args[0], *args[1:]], stdout=output, stderr=errors)
        results[name] = run.returncode == 0
    onboarding = directory / "onboarding"
    report = read(onboarding / "report.json")
    after = read(directory / "stop-result.json")
    results["stop"] = (after["before"]["status"] == "running" and after["after"]["status"] == "interrupted"
                       and after["before"]["executionId"] == after["after"]["executionId"])
    events = [json.loads(line) for line in (directory / "events.jsonl").read_text().splitlines()]
    results["input-isolation"] = {e["mismatch"] for e in events if e["event"] == "input-rejected"} == {
        "windowID", "runtimePID", "nonce", "focus"}
    results["workspace-cleanup"] = read(directory / "cleanup.json")["ok"]
    results["onboarding"] = (report["validity"] == "valid" and any(
        row["id"] == "E2E-ONBOARDING-001" and row["status"] == "passed" for row in report["scenarios"]))
    results["same-build"] = (read(onboarding / "ui-artifact.json") == build["app"]
                             and read(onboarding / "artifact.json") == build["runtime"]
                             and read(directory / "operator-bundle.json")["executableSHA256"] == build["app"]["sha256"])
    (directory / "checks.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))
    return all(results.values())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("pending", type=int, help="first-card frame showing the pending dispatch label")
    parser.add_argument("started", type=int, help="first-card frame showing the started Thread label")
    args = parser.parse_args()
    raise SystemExit(0 if check(args.directory, args.pending, args.started) else 1)
