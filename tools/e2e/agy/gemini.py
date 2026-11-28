"""Loopback Gemini responses for the installed agy CLI. No provider credentials required."""
import json
import re
import secrets
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


class Gemini(ThreadingHTTPServer):
    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server_port}"
        self.token = secrets.token_hex(24)
        self.stage = "first"
        self.last_tool_stage = None
        self.held = threading.Event()
        self.release = threading.Event()
        self.rejected = threading.Event()

    def response_parts(self, body):
        history = [part.get("text", "") for turn in body["contents"] for part in turn["parts"]]
        token = re.search(r"\bCHIEF_[a-f0-9]{12}\b", "\n".join(history))
        recalled = token[0] if token else "NO_HISTORY"
        if self.stage == "first":
            return [{"text": recalled}]
        if self.stage == "recall":
            return [{"text": "RECALL: "}, {"text": recalled}]
        if self.stage in ("approve", "deny") and self.stage != self.last_tool_stage:
            self.last_tool_stage = self.stage
            filename = recalled if self.stage == "approve" else "denied-marker"
            return [{"functionCall": {"id": "fixture-" + self.stage, "name": "run_command",
                    "args": {"CommandLine": "touch " + filename, "toolSummary": "Create the replay marker",
                             "WaitMsBeforeAsync": 1000}}}]
        return [{"text": "Done."}]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, code, body, media="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", media)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        route = urlsplit(self.path)
        auth = [self.headers.get("x-goog-api-key"), self.headers.get("Authorization", "").removeprefix("Bearer ")]
        auth.extend(parse_qs(route.query).get("key", []))
        if self.server.token not in auth:
            return self.reply(401, b"{}")
        size = int(self.headers.get("Content-Length", "0"))
        if not 0 < size <= 8 * 1024 * 1024:
            return self.reply(413, b"{}")
        body = json.loads(self.rfile.read(size))
        if route.path.endswith(":countTokens"):
            return self.reply(200, b'{"totalTokens":100}')
        method = route.path.rsplit(":", 1)[-1]
        if method not in ("generateContent", "streamGenerateContent"):
            return self.reply(404, b"{}")
        if self.server.stage == "hold":
            self.server.held.set()
            self.server.release.wait(30)
            return
        if self.server.stage == "failure":
            self.server.rejected.set()
            return self.reply(400, b'{"error":{"code":400,"message":"fixture refusal","status":"INVALID_ARGUMENT"}}')
        parts = self.server.response_parts(body)

        def frame(parts, final):
            candidate = {"index": 0, "content": {"role": "model", "parts": parts}}
            if final:
                candidate["finishReason"] = "STOP"
            return json.dumps({"candidates": [candidate]}).encode()

        if method == "generateContent":
            return self.reply(200, frame(parts, True))
        frames = [b"data: " + frame([part], i == len(parts) - 1) + b"\n\n" for i, part in enumerate(parts)]
        self.reply(200, b"".join(frames), "text/event-stream")
