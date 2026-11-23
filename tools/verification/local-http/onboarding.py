"""Time both independent-role saves over production HTTP in disposable profiles."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

from run import Client, wait_for

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from benchmarks.gate.runner import lease
from benchmarks.gate.ux import ui_lease


IDS = ("codex", "claude", "pi", "opencode")
ROLES = ("tag.settings", "report.settings")
PEER = Path(__file__).with_name("peer.py")


def record(**fields):
    print(json.dumps(fields, separators=(",", ":")), flush=True)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_state(client):
    return client.invoke("readback", "state:load")


def save(client, role, state, value):
    settings = state["settings"]
    entry = next(p for p in settings["pluginSettings"] if p["id"] == role)
    entry["value"] = value
    result = client.invoke(role, "app:update-settings", {
        "settings": settings, "expectedSettingsRevision": state["settingsRevision"],
    })
    if result["status"] != "saved" or result["settingsRevision"] != state["settingsRevision"] + 1:
        raise ValueError(f"{role} did not advance the revision exactly once")
    committed = load_state(client)
    if committed["settings"] != result["settings"] or committed["settingsRevision"] != result["settingsRevision"]:
        raise ValueError(f"{role} was not durable at response time")
    if next(p for p in committed["settings"]["pluginSettings"] if p["id"] == role)["value"] != value:
        raise ValueError(f"{role} changed submitted fields")
    return committed


def present(client, name, harness, **scope):
    result = client.invoke(name, "harness:settings-presentation", {
        "scope": "global", "harnessId": harness, **scope,
    })
    if result.get("executionSnapshotError") or not result["value"].get("models"):
        raise ValueError(f"{name} did not supply a model catalog")


def workload(client, mode, retained):
    if not retained:
        with ThreadPoolExecutor(max_workers=4) as workers:
            jobs = [workers.submit(present, client, "chief-entry-" + harness, harness, executionOwner="moku") for harness in IDS]
            for job in jobs:
                job.result()
    state = load_state(client)
    moku = state["settings"]["moku"]
    if set(moku["executionHarnesses"]) != set(IDS):
        raise ValueError("Chief does not have all four execution profiles")
    saved = {}
    for role in ROLES:
        original = next(p["value"] for p in state["settings"]["pluginSettings"] if p["id"] == role)
        if original["mode"] != "inherit":
            raise ValueError(f"{role} did not start inherited")
        source = original.get("independent", {
            "harnessPreference": moku["hostHarnessPreference"], "harnesses": moku["executionHarnesses"],
        })
        record(kind="configuration", role=role, selectedHarness=source["harnessPreference"],
               profileCount=len(source["harnesses"]))
        if mode == "candidate":
            present(client, role + "-entry", source["harnessPreference"], applicationSettings=role,
                    previewIndependent=True)
        state = save(client, role, state, {"mode": "override", **source})
        saved[role] = source
    if not retained:
        for role, source in saved.items():
            state = save(client, role, state, {"mode": "inherit", "independent": source})


def session(args, root, retained):
    profile = root / "profile"
    path = profile / "runtime/connection.json"
    env = {"HOME": str(root), "CFFIXED_USER_HOME": str(root), "TMPDIR": str(root / "tmp"),
           "PATH": ":".join([str(root / "bin"), *map(str, args.cli_dir), "/usr/bin", "/bin"]),
           "CHIEF_HEADLESS": "1", "SHELL": "/bin/sh",
           "OPENAI_API_KEY": "fixture-only", "ANTHROPIC_API_KEY": "fixture-only",
           "OPENCODE_DISABLE_AUTOUPDATE": "true", "OPENCODE_DISABLE_MODELS_FETCH": "true",
           "CHIEF_ONBOARDING_FIXTURE_DELAY": str(args.claude_delay)}
    process = subprocess.Popen(
        ["/usr/bin/sandbox-exec", "-f", root / "sandbox.sb", args.binary, "serve", "--data-dir", profile],
        cwd=root, env=env, stdout=subprocess.DEVNULL,
    )
    try:
        wait_for(lambda: path.is_file() or process.poll() is not None, timeout=60)
        if process.poll() is not None:
            raise RuntimeError(f"runtime startup exited with {process.returncode}")
        discovery = json.loads(path.read_text())
        if discovery["pid"] != process.pid or Path(discovery["dataDir"]).resolve() != profile:
            raise ValueError("discovery belongs to another instance")
        workload(Client(discovery, record), args.mode, retained)
    finally:
        if process.poll() is None:
            process.terminate()
            if process.wait(timeout=30) != 0:
                raise RuntimeError("runtime failed to close")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=lambda path: Path(path).resolve())
    parser.add_argument("--revision", required=True, help="revision reported for the given binary")
    parser.add_argument("--mode", choices=("baseline", "candidate"), required=True)
    parser.add_argument("--cli-dir", type=lambda path: Path(path).resolve(), action="append", required=True)
    claude = parser.add_mutually_exclusive_group()
    claude.add_argument("--native-claude", type=lambda path: Path(path).resolve())
    claude.add_argument("--claude-delay", type=float, default=0, help="synthetic seconds per fixture get_settings")
    args = parser.parse_args()
    if not 0 <= args.claude_delay <= 10:
        parser.error("Claude fixture delay must be between 0 and 10 seconds")
    record(kind="provenance", mode=args.mode, revision=args.revision, runtimeSHA256=digest(args.binary),
           collectorSHA256=digest(__file__), clientSHA256=digest(Path(__file__).with_name("run.py")),
           claudeSHA256=digest(args.native_claude or PEER), nativeClaude=bool(args.native_claude),
           claudeDelaySeconds=args.claude_delay, platform=platform.platform(), python=platform.python_version())
    with lease(), ui_lease(), tempfile.TemporaryDirectory(prefix="chief-onboarding-save-") as directory:
        root = Path(directory).resolve()
        (root / "bin").mkdir()
        (root / "tmp").mkdir()
        claude_path = root / "bin/claude"
        if args.native_claude:
            claude_path.symlink_to(args.native_claude)
        else:
            claude_path.write_bytes(b"#!" + os.fsencode(sys.executable) + b"\n" + PEER.read_bytes())
            claude_path.chmod(0o700)
        # Strip the invoking environment and deny external network and persistent writes.
        (root / "sandbox.sb").write_text(f'''(version 1)
(allow default)
(deny network*)
(allow network-inbound (local ip "localhost:*"))
(allow network-bind (local ip "localhost:*"))
(allow network-outbound (remote ip "localhost:*"))
(deny file-write*)
(allow file-write* (subpath "{root}") (literal "/dev/null"))
''')
        for retained in (False, True):
            record(kind="phase", profile="retained-after-restart" if retained else "first-override")
            session(args, root, retained)


if __name__ == "__main__":
    main()
