"""Replay Settings reset against a temporary legacy Alpha profile and real Git checkout."""
import hashlib
import json
import platform
from pathlib import Path
import socket
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools/verification"), str(ROOT / "tools/benchmarks")]
from native_replay import NativeReplay
from gate.runner import lease
from gate.ux import native_lease
from report import sha256


def check_maintenance(work, runtime, env):
    profile = work / "recovery"
    profile.mkdir(mode=0o700)
    token = profile / "chief-factory-reset.json"
    draft = profile / "client-command-journal.json"
    draft.write_text("pending")
    command = [runtime, "finish-factory-reset", "--data-dir", profile]

    def rejected(reason):
        result = subprocess.run(command, cwd=work, env=env, capture_output=True, text=True)
        if result.returncode == 0 or reason not in result.stderr or draft.read_text() != "pending":
            raise AssertionError(f"unexpected maintenance outcome: {result}")

    rejected("no such file")
    token.write_text(json.dumps({"version": 1, "dataDir": str(work / "other"), "epoch": "retired"}))
    token.chmod(0o600)
    rejected("does not match")
    token.write_text(json.dumps({"version": 1, "dataDir": str(profile), "epoch": "retired"}))
    identity = hashlib.sha256(str(profile).encode()).digest()
    with socket.socket() as owner:
        owner.bind(("127.0.0.1", 20000 + int.from_bytes(identity[:4], "big") % 40000))
        owner.listen()
        rejected("ownership")
    outside = work / "external-cache"
    outside.mkdir()
    sentinel = outside / "state.json"
    sentinel.write_text("external")
    alias = profile / "client-reading-cache"
    alias.symlink_to(outside, target_is_directory=True)
    rejected("real profile directory")
    assert sentinel.read_text() == "external" and token.exists()
    alias.unlink()
    bucket = profile / "transfers" / str(uuid.uuid4())
    bucket.mkdir(parents=True)
    (bucket / "upload").write_text("staged")
    extra = bucket / "project-notes"
    extra.write_text("user work")
    rejected("unexpected contents")
    assert (bucket / "upload").read_text() == "staged" and token.exists()
    extra.rename(work / "preserved-notes")
    subprocess.run(command, cwd=work, env=env, check=True)
    assert not token.exists() and not draft.exists() and sentinel.read_text() == "external"
    assert not bucket.exists() and (work / "preserved-notes").read_text() == "user work"


def run(output):
    output.mkdir(parents=True, exist_ok=False)
    with lease(), native_lease():
        subprocess.run(["xcrun", "swift", "build", "--package-path", "app/macos", "--product", "Chief"], cwd=ROOT, check=True)
        replay = NativeReplay(ROOT, "FactoryResetReplay", "com.chief.e2e." + uuid.uuid4().hex)
        work = replay.workspace
        profile = work / "profile"
        home = work / "home"
        runtime = work / "chief-runtime"
        home.mkdir()
        env = {"HOME": str(home), "CFFIXED_USER_HOME": str(home), "CHIEF_HEADLESS": "1",
               "PATH": "/usr/bin:/bin", "TMPDIR": str(work), "LANG": "en_US.UTF-8", "CODEX_HOME": str(home / ".codex")}
        try:
            subprocess.run([ROOT / "scripts/go.sh", "build", "-o", runtime, "./cmd/chief-runtime"], cwd=ROOT, check=True)
            check_maintenance(work, runtime, env)
            replay.compile([*sorted((ROOT / "app/macos/Sources/App").glob("*.swift")),
                            Path(__file__).with_name("FactoryResetReplay.swift")], ["-DCHIEF_WORKSPACE_LIFECYCLE_REPLAY"])
            profile.mkdir(mode=0o700)
            (profile / "mokusei-go-state-v1").mkdir()
            (profile / "desktop-preferences.json").write_text('{"onboardingCompleted":true}')
            draft = profile / "client-drafts" / ("a" * 64 + ".json")
            draft.parent.mkdir()
            draft.write_text('{"version":2,"scope":"reset-replay","attachmentIDs":[],"value":"unsent"}')
            repo, checkout = work / "project", work / ".project-chief-worktrees/keep"
            def git(*args):
                subprocess.run(["git", "-C", repo, *args], cwd=work, env=env, check=True, stdout=subprocess.DEVNULL)
            repo.mkdir()
            git("init", "--quiet")
            git("-c", "user.name=Replay", "-c", "user.email=test@invalid", "commit", "--allow-empty", "-qm", "fixture")
            git("worktree", "add", "--detach", checkout)
            identity = hashlib.sha256(str(profile).encode()).hexdigest()
            workspace = home / ".Chief/profiles" / identity / "runtime-workspace"
            kept = [workspace / "moku-workspace/user.txt", workspace / "tmp-workspaces/thread-example/user.txt", repo / "user.txt", checkout / "uncommitted.txt", home / ".codex/auth.json",
                    profile / "downloads/user-file", profile / "unrelated/file", profile / "chief-go-state-v1/inactive"]
            for file in kept:
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text("keep")
            isolated = profile / "mokusei-go-state-v1/harnesses/codex/application-tools-only" / ("thread-" + "a" * 64)
            isolated.mkdir(parents=True)
            (isolated / "account-link").symlink_to(home / ".codex", target_is_directory=True)
            code = replay.run(["--data-dir", profile, "--runtime", runtime], timeout=125, launch_environment=env)
            if code != 0 or not (work / "passed").exists():
                raise RuntimeError("Factory reset replay failed; inspect stdout.log and stderr.log")
            assert not draft.exists() and not isolated.exists() and all(file.read_text() == "keep" for file in kept)
            registered = subprocess.check_output(["git", "-C", repo, "worktree", "list", "--porcelain"], env=env, text=True)
            assert f"worktree {checkout}\n" in registered
            assert (checkout / ".git").is_file()
            receipt = {
                "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "status": "passed", "input": "mounted AppKit window events and sheet buttons",
                "os": platform.mac_ver()[0], "architecture": platform.machine(),
                "trackedChanges": subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).splitlines(),
                "runtimeSHA256": sha256(runtime),
                "replaySHA256": sha256(replay.executable),
                "rejected": ["missing confirmation", "other profile", "ownership conflict", "symlinked cache directory", "unexpected transfer contents"],
                "profile": str(profile), "preserved": [str(p.relative_to(work)) for p in kept]}
        finally:
            try:
                if runtime.exists() and profile.exists():
                    subprocess.run([runtime, "stop", "--data-dir", profile], env=env, cwd=work, timeout=50, check=True)
            finally:
                replay.export(output)
                replay.close()
        (output / "factory-reset.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    run(Path(sys.argv[1]).resolve())
