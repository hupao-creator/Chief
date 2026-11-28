"""Exercise moku:submit -> create_thread -> native agy ACP with loopback model peers."""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "benchmarks"))
from adapter import Runtime, UI, wait_for
from gate.runner import lease
from provider import Provider, declared_tools, find_tool
from reading.public import content
from gemini import Gemini
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lease import DesktopLease


class Coordinator(Provider):
    def __init__(self, root):
        super().__init__(root, 1)
        self.terminals = set()
        self.project = root / "replay-project"
        self.project.mkdir()

    def respond(self, request):
        create = find_tool(declared_tools(request), "create_thread")
        if create and not self.receipts and "BENCHMARK CREATE" in json.dumps(request["input"]):
            context = json.dumps(request["input"])
            check("Published create_thread options" in context and self.target_model in context,
                  "the coordinator did not receive the AGY model in dispatch context")
        if create:
            for item in request["input"]:
                for part in item.get("content", []):
                    if not isinstance(part, dict):
                        continue
                    _, marker, body = part.get("text", "").partition("Chief Agent Thread terminal event:\n")
                    if marker:
                        event, _ = json.JSONDecoder().raw_decode(body.lstrip())
                        turn = event["observation"]["latestExecution"]
                        self.terminals.add((event["threadId"], turn["executionId"], turn["status"]))
        return super().respond(request)

    def wait_terminal(self, thread_id, turn):
        def received():
            with self.lock:
                check(not self.failures, "coordinator peer failed: " + str(self.failures))
                return (thread_id, turn["executionId"], turn["status"]) in self.terminals
        wait_for(received, bool, 40)

    def creation_arguments(self, index):
        return {"prompt": f"Remember {self.marker}. Reply with that exact token only. Do not use tools.",
                "target": {"agy": {"model": self.target_model}}, "cwd": str(self.project), "worktree": False}


def message(text):
    return {"parts": [{"kind": "text", "text": text}]}


def wait_turn(runtime, previous=None, waiting=False, coordinator=None):
    deadline = time.monotonic() + 100
    while time.monotonic() < deadline:
        if coordinator:
            with coordinator.lock:
                check(not coordinator.failures, "coordinator peer failed: " + str(coordinator.failures))
        for thread in runtime.state()["threads"]:
            if thread["harnessId"] != "agy":
                continue
            turn = thread["observation"]["latestExecution"]
            if turn and turn["executionId"] != previous and turn["status"] != "running":
                if turn["status"] == "waiting-for-user" and not waiting:
                    raise RuntimeError("unexpected permission request")
                return thread, turn
        time.sleep(.25)
    raise TimeoutError("timed out waiting for the Antigravity task")


def check(condition, reason):
    if not condition:
        raise RuntimeError(reason)


def check_detection(binary, root, env):
    directory = root / "detection-bin"
    directory.mkdir()
    profile = root / "detection-profile"
    # Exercise the Runtime's environment fallback with a fully controlled PATH.
    isolated = {**env, "PATH": str(directory) + ":/usr/bin:/bin", "SHELL": "/usr/bin/false"}
    def service(action):
        subprocess.run([binary, action, "--data-dir", profile], env=isolated, cwd=root,
                       stdout=subprocess.DEVNULL, check=True, timeout=45)
    service("start")
    try:
        runtime = Runtime(profile)
        detect = lambda: runtime.invoke("harness:detect-installation", ["agy"])
        check(detect()["status"] == "missing", "an absent executable appeared installed")
        executable = directory / "agy"
        for name, version, expected in [
                ("Different ACP Agent", "1.5.17", "did not identify"),
                ("Antigravity ACP Server", "1.5.0", "1.5.1 or later")]:
            info = {"protocolVersion": 1, "agentInfo": {"name": name, "version": version}}
            executable.write_text(f"#!{sys.executable}\nimport json, sys\n"
                                  "request = json.loads(sys.stdin.readline())\n"
                                  f"print(json.dumps(dict(jsonrpc='2.0', id=request['id'], result={info!r})), flush=True)\n")
            executable.chmod(0o700)
            try:
                detect()
            except ValueError as error:
                check(expected in str(error), "wrong installation diagnostic: " + str(error))
            else:
                raise RuntimeError("invalid ACP peer appeared installed")
        print("discovery rejected a missing agy, a different ACP agent and pre-1.5.1 Antigravity", flush=True)
    finally:
        service("stop")


@contextlib.contextmanager
def desktop_ui(desktop, binary, profile, socket, env):
    owner = DesktopLease(Path("/private/tmp/mokusei-ui-verification.lock"), "agy-dispatch")
    owner.acquire()
    try:
        with subprocess.Popen([desktop, "--runtime", binary, "--data-dir", profile, "--automation-socket", socket],
                              env=env, cwd=socket.parent, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as app:
            try:
                def ready():
                    check(app.poll() is None, "the isolated desktop exited before its UI was ready")
                    return socket.exists()
                wait_for(ready, bool, 30)
                yield UI(socket, app.pid)
            finally:
                app.terminate()
                try:
                    app.wait(10)
                except subprocess.TimeoutExpired:
                    app.kill()
    finally:
        owner.close()


def select_target(ui, runtime):
    wait_for(ui.request, lambda s: s and "settings.open" in s["actions"], 45)
    ui.request({"name": "settings.open"})

    def select(harness, selected):
        def control():
            page = ui.request() or {}
            return next((c for c in (page.get("settings") or {}).get("controls", [])
                         if c["id"].endswith("target." + harness) and c["enabled"]
                         and c["value"] is selected), None)
        current = wait_for(control, bool, 45)
        ui.request({"name": "settings.control", "controlId": current["id"], "handle": current["handle"],
                    "operation": "activate", "value": None})

    select("agy", False)
    select("codex", True)
    wait_for(ui.request, lambda s: s and "settings.close" in s["actions"], 25)
    ui.request({"name": "settings.close"})
    wait_for(runtime.state, lambda s: s["settings"]["moku"]["targetHarnessIds"] == ["agy"], 25)
    print("macOS Chief Agent settings selected and saved Antigravity as the dispatch target", flush=True)


def check_reader(ui, thread_id, execution_id):
    def card():
        snapshot = ui.request() or {}
        if snapshot.get("page") == "overview" and "thread.open" in snapshot["actions"]:
            return next((r for r in snapshot["threads"] if r["threadId"] == thread_id), None)
    target = wait_for(card, bool, 45)
    ui.request({"name": "thread.open", "threadId": target["threadId"], "typeId": target["typeId"]})
    def mounted(snapshot):
        controls = ((snapshot or {}).get("reading") or {}).get("controls", [])
        return any(c["role"] == "turn" and c["value"].get("executionId") == execution_id
                   and c["value"].get("state") == "ready" and c["value"].get("visibleRowCount", 0) > 0
                   for c in controls)
    wait_for(ui.request, mounted, 45)
    print("macOS opened the saved Antigravity card from Overview and mounted its completed execution", flush=True)


def replay(binary, root, stack, desktop):
    gateway = stack.enter_context(Gemini())
    server = threading.Thread(target=gateway.serve_forever, daemon=True)
    server.start()
    stack.callback(server.join)
    stack.callback(gateway.shutdown)
    stack.callback(gateway.release.set)
    peer = Coordinator(root)
    stack.callback(peer.close)
    peer.marker = "CHIEF_" + secrets.token_hex(6)
    native = root / "codex"
    native.mkdir()
    home = root / "home"
    home.mkdir()
    agy_profile = home / ".gemini" / "antigravity-cli"
    agy_profile.mkdir(parents=True)
    (agy_profile / "settings.json").write_text(json.dumps({"auth": {"type": "gemini-api-key"}}))
    (native / "config.toml").write_text(f'''model_provider = "fixture"
cli_auth_credentials_store = "file"
check_for_update_on_startup = false
[model_providers.fixture]
name = "Local test coordinator"
base_url = "{peer.url}/v1"
wire_api = "responses"
env_key = "FIXTURE_KEY"
requires_openai_auth = false
supports_websockets = false
''')
    env = {k: os.environ[k] for k in ("PATH", "USER", "LANG", "SHELL") if k in os.environ}
    env.update(HOME=str(home), CODEX_HOME=str(native), CODEX_SQLITE_HOME=str(native), CHIEF_HEADLESS="1",
               GEMINI_API_KEY=gateway.token, GOOGLE_GEMINI_BASE_URL=gateway.url,
               GEMINI_HOME=str(root / "other-google-tool"),
               FIXTURE_KEY="fixture-only")
    check_detection(binary, root, env)
    profile = root / "profile"

    def service(action):
        subprocess.run([binary, action, "--data-dir", profile], cwd=root, env=env,
                       stdout=subprocess.DEVNULL, check=True, timeout=45)
    service("start")
    stack.callback(service, "stop")
    runtime = Runtime(profile)
    detected = runtime.invoke("harness:detect-installation", ["agy"])
    check(detected["status"] == "installed", "native agy missing")
    version = subprocess.check_output([detected["executablePath"], "--version"], env=env, text=True).strip()
    selection = runtime.configure()["selection"]["threadSettings"]
    peer.model, peer.effort = selection["model"], selection["thinking"]["effort"]
    state = runtime.state()
    settings = state["settings"]
    settings["moku"]["targetHarnessIds"] = ["codex"] if desktop else ["agy"]
    settings["harnesses"]["agy"] = {"authMethod": "gemini-api-key"}
    runtime.invoke("app:update-settings", [{"settings": settings, "expectedSettingsRevision": state["settingsRevision"]}])
    preferences = profile / "desktop-preferences.json"
    if desktop:
        preferences.write_text(json.dumps({"onboardingCompleted": True}))
        with desktop.open("rb") as executable:
            print("desktop_sha256=" + hashlib.file_digest(executable, "sha256").hexdigest(), flush=True)
        with desktop_ui(desktop, binary, profile, root / "setup.sock", env) as ui:
            select_target(ui, runtime)
    service("stop")
    service("start")
    catalog = runtime.invoke("harness:settings-presentation", [{"scope": "global", "harnessId": "agy"}])["value"]
    published = runtime.invoke("harness:settings-presentation", [{"scope": "global", "harnessId": "agy", "readPublished": True}])["value"]
    default_model = catalog["effectiveModel"]["model"]
    peer.target_model = next(m["id"] for m in published["models"] if m["id"].startswith("gemini-") and m["id"] != default_model)
    checkout = Path(__file__).resolve().parent
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=checkout, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=checkout))
    with binary.open("rb") as executable:
        digest = hashlib.file_digest(executable, "sha256").hexdigest()
    print(f"source={revision} dirty={dirty} runtime_sha256={digest} "
          f"agy={version} model={peer.target_model} provider=loopback", flush=True)
    runtime.invoke("moku:submit", [{"input": message(f"BENCHMARK CREATE one Antigravity test task in {peer.project}.")}])
    thread, first = wait_turn(runtime, coordinator=peer)
    check(first["status"] == "completed" and first.get("summary", "").strip() == peer.marker,
          "first execution did not deliver the exact fixture reply")
    tid = thread["id"]
    check(thread["directoryScope"] == str(peer.project.resolve()), "the requested project did not get its own Overview folder")
    peer.wait_terminal(tid, first)
    check(any(r["threadId"] == tid for r in peer.receipts.values()), "wrong create_thread receipt")
    print(f"agy {version} | moku:submit -> create_thread -> native reply and coordinator terminal event passed", flush=True)

    def send(text):
        return runtime.invoke("thread:follow-up", [{"threadId": tid, "input": message(text)}])

    gateway.stage = "recall"
    send("Return exactly RECALL: followed by one space and the token from my previous message. One line only.")
    _, second = wait_turn(runtime, first["executionId"])
    check(second["status"] == "completed" and second.get("summary", "").strip() == "RECALL: " + peer.marker,
          f"follow-up did not return the exact recall reply (status={second['status']}, error={second.get('error')})")
    service("stop")
    service("start")
    for turn, expected in ((first, peer.marker), (second, "RECALL: " + peer.marker)):
        snapshot = content(runtime, tid, {"kind": "turn", "key": turn["executionId"]})
        rows = snapshot["value"]["turns"]
        check(len(rows) == 1 and rows[0]["executionId"] == turn["executionId"], "wrong turn projection")
        check(rows[0]["model"] == peer.target_model, "the execution lost the explicitly selected model")
        replies = [b["text"].strip() for b in rows[0]["blocks"] if b["kind"] == "assistant"]
        check(replies == [expected], "scoped transcript did not retain the exact independent reply")
    print("same-session recall and scoped replies after Runtime restart passed", flush=True)
    if desktop:
        with desktop_ui(desktop, binary, profile, root / "ui.sock", env) as ui:
            check_reader(ui, tid, second["executionId"])
        service("start")
    workspace = Path(thread["cwd"]).resolve()
    check(workspace == peer.project.resolve(), "task ran outside the selected temporary project")
    gateway.stage = "approve"
    send("Use the terminal command tool to run touch followed by a space and the exact CHIEF_ token you recalled before. "
         "Use the token itself as the filename in the current directory. Use no other tools.")
    _, approval = wait_turn(runtime, second["executionId"], waiting=True)
    check(approval["status"] == "waiting-for-user", "native approval was not observed: " + approval["status"])
    interaction = approval["interactions"][0]
    command = interaction.get("description", "").partition("\n")[0]
    check(command == "touch " + peer.marker, "resumed native session did not request the exact recalled command")
    allow_once = [a for a in interaction["actions"] if a["intent"] == "allow"
                  and a["label"].strip().lower() in {"allow", "allow once", "allow this time", "run", "run once", "yes", "yes, once"}]
    check(len(allow_once) == 1, "one-time approval not identified among " + str([a["label"] for a in interaction["actions"]]))
    runtime.invoke("thread:interaction-respond", [{"threadId": tid, "executionId": approval["executionId"],
                   "interactionId": interaction["id"], "actionId": allow_once[0]["id"]}])
    _, approved = wait_turn(runtime, second["executionId"])
    check(approved["status"] == "completed" and (workspace / peer.marker).is_file(),
          "approved command did not create the recalled filename")
    print("resumed native session, one-time approval and native tool execution passed", flush=True)
    tool_rows = content(runtime, tid, {"kind": "turn", "key": approved["executionId"]})["value"]["turns"][0]
    check(any(b["kind"] == "tool" for b in tool_rows["blocks"]), "native tool call missing from the scoped reader")

    gateway.stage = "deny"
    send("Use the terminal command tool to run exactly: touch denied-marker. If denied, stop and reply DENIED. Do not use any other tool.")
    _, pending = wait_turn(runtime, approved["executionId"], waiting=True)
    check(pending["status"] == "waiting-for-user", "fresh native permission request was not observed: " + pending["status"])
    interaction = pending["interactions"][0]
    check(interaction.get("description", "").partition("\n")[0] == "touch denied-marker", "unexpected command for denial")
    action = next(a for a in interaction["actions"] if a["intent"] == "deny")
    runtime.invoke("thread:interaction-respond", [{"threadId": tid, "executionId": pending["executionId"],
                   "interactionId": interaction["id"], "actionId": action["id"]}])
    _, denied = wait_turn(runtime, approved["executionId"])
    check(denied["status"] == "completed" and not (workspace / "denied-marker").exists(),
          "permission denial did not protect the test workspace")
    print("new permission request, denial and workspace check passed", flush=True)
    gateway.stage = "hold"
    send("Write a long essay about the history of the alphabet. Use no tools.")
    check(gateway.held.wait(30), "native prompt did not reach the gateway before Stop")
    latest = next(t for t in runtime.state()["threads"] if t["id"] == tid)
    runtime.invoke("thread:interrupt", [{"threadId": tid, "expectedCancellationId": latest["cancellationId"]}])
    gateway.release.set()
    _, stopped = wait_turn(runtime, denied["executionId"])
    check(stopped["status"] == "interrupted", "interrupt did not settle the execution")
    peer.wait_terminal(tid, stopped)
    print("exact execution interruption passed", flush=True)
    gateway.stage = "failure"
    send("Reply with the word ready.")
    _, failed = wait_turn(runtime, stopped["executionId"])
    check(gateway.rejected.is_set() and failed["status"] == "failed", "native provider error was recorded as success")
    peer.wait_terminal(tid, failed)
    print("injected provider error settled as failed", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--desktop", type=Path, help="also enable the target in Settings and open the saved Thread with this Chief desktop")
    args = parser.parse_args()
    # Chief reserves chief-* under the system temp directory for Inbox work.
    # Model a user-selected project folder so its settled card is in Overview.
    with lease(), tempfile.TemporaryDirectory(prefix="agy-dispatch-") as tmp, contextlib.ExitStack() as stack:
        replay(args.runtime.resolve(), Path(tmp), stack, args.desktop.resolve() if args.desktop else None)
