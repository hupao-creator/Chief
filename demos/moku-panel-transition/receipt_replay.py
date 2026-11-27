"""Run the native Composer against Go transport, with a loopback response-loss proxy."""
from collections import defaultdict
from contextlib import closing
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from threading import Thread
import time
from urllib.parse import unquote

source = Path(__file__).resolve().parent
repo = source.parents[1]
sys.path.insert(0, str(repo / "tools/verification"))
from native_replay import NativeReplay

replay = NativeReplay(repo, "ComposerReceiptReplay", "com.chief.replay.composer-receipt")
writes = defaultdict(list)
queries = []
requests = {}


def call(path, payload, headers):
    with closing(HTTPConnection("127.0.0.1", upstream["port"], timeout=5)) as conn:
        conn.request("POST", path, payload, headers)
        response = conn.getresponse()
        return response.status, json.loads(response.read())


def lookup(receipt, headers, until=None):
    deadline = time.monotonic() + 4
    while True:
        status, result = call("/commands/receipt", json.dumps({"commandId": receipt}), headers)
        if status != 200 or until is None or result["status"] == until:
            return status, result
        if time.monotonic() >= deadline:
            raise RuntimeError(f"{receipt} did not reach {until}: {result}")
        time.sleep(.005)


def input_text(channel, args):
    if channel == "thread:fork":
        return args[0]["request"]["executionId"]
    return args[0]["input"]["parts"][0]["text"]


class Proxy(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        raw = self.rfile.read(int(self.headers["Content-Length"]))
        data = json.loads(raw)
        receipt = data["commandId"]
        headers = {key: value for key, value in self.headers.items()
                   if key.lower() not in {"content-length", "host", "connection"}}
        mode_file = replay.workspace / "mode"
        mode = mode_file.read_text() if mode_file.exists() else ""
        if self.path == "/commands/receipt":
            queries.append(receipt)
            status, result = call(self.path, raw, headers)
        else:
            channel = unquote(self.path).removeprefix("/invoke/")
            if channel in {"thread:fork", "thread:follow-up", "moku:submit"}:
                text = input_text(channel, data["args"])
                writes[channel].append((receipt, text))
                requests[receipt] = (self.path, raw, headers)
                if receipt.endswith("-followup"):
                    _, fork = lookup(receipt.removesuffix("-followup"), headers)
                    assert data["args"][0]["threadId"] == fork["result"]["value"]["threadId"], fork
                lose = (mode == "lose" or mode == "lose-fork" and channel == "thread:fork"
                        or mode == "lose-followup" and channel == "thread:follow-up")
                if lose:
                    with closing(HTTPConnection("127.0.0.1", upstream["port"], timeout=5)) as conn:
                        conn.request("POST", self.path, raw, headers)
                        status, pending = lookup(receipt, headers, "pending")
                        assert status == 200 and pending["status"] == "pending", pending
                    # Drop both sockets after Go durably admitted the command.
                    self.close_connection = True
                    print(channel, receipt, "Go receipt pending; disconnected", flush=True)
                    return
            status, result = call(self.path, raw, headers)
        body = json.dumps(result).encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


try:
    def build(name):
        binary = replay.workspace / name
        subprocess.run([str(repo / "scripts/go.sh"), "build", "-o", binary,
                        "./demos/moku-panel-transition/" + name], cwd=repo, check=True)
        return binary

    collector = build("attachment-replay")
    backend = build("receipt-peer")
    files = json.loads(subprocess.check_output([collector, "stage"], cwd=replay.workspace))
    (replay.workspace / "files.json").write_text(json.dumps(files))
    replay.compile([source / "ReceiptReplay.swift", source / "SteerReaderReplay.swift", source / "ReportSendReplay.swift"], extra_args=["-package-name", "macos"])
    with subprocess.Popen([backend], cwd=replay.workspace, stdin=subprocess.PIPE, stdout=subprocess.PIPE) as peer:
        try:
            upstream = json.loads(peer.stdout.readline())
            auth = {"Authorization": "Bearer " + upstream["token"], "X-Mokusei-Epoch": upstream["epoch"],
                    "X-Mokusei-Protocol": str(upstream["protocolVersion"])}
            status, invalid = call("/invoke/thread%3Afollow-up", json.dumps({
                "commandId": "4C7F366D-557C-4C71-BE02-6CE37909F617", "args": []}), auth)
            calls = replay.workspace / "handler-calls.jsonl"
            assert status == 400 and invalid["error"]["code"] == "INVALID_COMMAND_ID" and not calls.read_bytes()
            print("Go rejected the baseline bare UUID before entering the handler", flush=True)
            with closing(HTTPConnection("127.0.0.1", upstream["port"], timeout=5)) as stream:
                stream.request("GET", "/events", headers=auth)
                with stream.getresponse() as events:
                    hello = json.loads(events.readline())
                    assert hello["type"] == "hello" and hello["epoch"] == upstream["epoch"], hello
                    upstream["followUpRowIdentity"] = hello["followUpRowIdentity"]
            with ThreadingHTTPServer(("127.0.0.1", 0), Proxy) as server:
                (replay.workspace / "peer.json").write_text(json.dumps({**upstream, "port": server.server_port}))
                Thread(target=server.serve_forever, daemon=True).start()
                try:
                    evidence = Path(os.environ.get("CHIEF_REPORT_REPLAY_EVIDENCE", replay.workspace / "evidence"))
                    evidence.mkdir(parents=True, exist_ok=True)
                    env = dict(os.environ, NSUnbufferedIO="YES", CHIEF_REPORT_REPLAY_EVIDENCE=str(evidence.resolve()))
                    with subprocess.Popen([str(replay.executable)], cwd=replay.workspace, env=env) as process:
                        try:
                            ready = replay.workspace / "reader-ocr-ready"
                            startup_deadline = time.monotonic() + 120
                            while not ready.exists():
                                if process.poll() is not None:
                                    raise RuntimeError(f"Reader OCR startup exited with status {process.returncode}")
                                if time.monotonic() >= startup_deadline:
                                    raise subprocess.TimeoutExpired("English reader OCR startup", 120)
                                time.sleep(.05)
                            status = process.wait(timeout=50)
                            if status:
                                raise subprocess.CalledProcessError(status, process.args)
                        except (RuntimeError, subprocess.SubprocessError):
                            if process.poll() is None:
                                try:
                                    subprocess.run(["/usr/bin/sample", str(process.pid), "2", "1", "-file",
                                                    str(evidence / "timeout-sample.txt")], timeout=8)
                                except (OSError, subprocess.SubprocessError) as error:
                                    print("Receipt replay process sample unavailable:", error, flush=True)
                                finally:
                                    process.kill()
                                    process.wait(timeout=5)
                            if evidence == replay.workspace / "evidence":
                                retained = Path(tempfile.mkdtemp(prefix="chief-receipt-failure-"))
                                shutil.copytree(evidence, retained, dirs_exist_ok=True)
                                evidence = retained
                            print("Receipt replay failure evidence:", evidence, flush=True)
                            raise
                finally:
                    server.shutdown()
            for channel in ("moku:submit", "thread:follow-up"):
                receipt = writes[channel][0][0]
                if channel == "moku:submit":
                    original = json.loads(requests[receipt][1])["args"][0]["input"]["parts"]
                    assert original[1:] == [{"kind": "mention", "name": "Previous project",
                                             "path": "/fixture/Previous project", "pathType": "directory"}], original
                status, observed = lookup(receipt, auth)
                assert status == 200 and observed["status"] == "complete" and observed["result"]["ok"]
                assert queries.count(receipt) >= 2, queries
                # A deliberate duplicate probe must return the stored response.
                status, duplicate = call(*requests[receipt])
                assert status == 200 and duplicate == observed["result"]
                print(channel, "recovered", receipt, "client lookups", queries.count(receipt), flush=True)
            actual = defaultdict(list)
            for entry in map(json.loads, calls.read_text().splitlines()):
                text = input_text(entry["channel"], entry["args"])
                actual[entry["channel"]].append(text)
                if text == "mixed picker":
                    folder = replay.workspace / "Project 空"
                    assert entry["args"][0]["input"]["parts"] == [
                        {"kind": "text", "text": text},
                        {"kind": "mention", "pathType": "directory", "path": str(folder), "name": folder.name},
                        *({"kind": "local-file", "file": {"id": f["id"]}} for f in files),
                    ], entry
                    print("Go handler received the selected folder and both staged file IDs", flush=True)
            for channel in ("moku:submit", "thread:follow-up", "thread:fork"):
                expected = ["A", "D", "BC", "rejected", "boundary", "direct"]
                if channel == "moku:submit":
                    expected += ["mixed picker"]
                if channel == "thread:follow-up":
                    expected += ["after-fork", "historical", "after-followup", "historical", "same-checkpoint", "changed", "changed"]
                    expected += ["sidecard " + step for step in ("catalog first", "receipt first", "finished", "reject", "fold", "switch card", "leave")]
                    expected += ["Report accept", "Report reject", "Report leave"]
                    expected += ["Repeat this instruction"] * 5
                if channel == "thread:fork":
                    expected = ["historical"] * 4 + ["current"]
                assert [text for _, text in writes[channel]] == actual[channel] == expected, (writes[channel], actual[channel])
                print(channel, "admitted IDs / handler inputs", writes[channel], flush=True)
            initial, final = [write for write in writes["thread:follow-up"] if write[1] == "changed"]
            assert writes["thread:fork"][-1][0] == initial[0] + "-fork"
            assert final[0] == initial[0] + "-fork-followup"
        finally:
            peer.stdin.close()
            assert peer.wait(timeout=5) == 0
    subprocess.run([collector, "collect"], cwd=replay.workspace, check=True)
    assert not Path(files[0]["path"]).exists()
    assert Path(files[1]["path"]).read_bytes() == b"second"
    print("Collector removed the released file and preserved the durable successor bytes after process exit", flush=True)
finally:
    replay.close()
