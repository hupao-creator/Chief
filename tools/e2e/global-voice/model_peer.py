"""Deterministic OpenAI-compatible model for installed Pi and OpenCode clients."""
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import re
import threading
import uuid


class Model(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        size = int(self.headers.get("Content-Length", "0"))
        if self.path != "/v1/chat/completions" or not 0 < size <= 16 * 1024 * 1024:
            self.send_error(400)
            return
        request = json.loads(self.rfile.read(size))
        messages = request["messages"]
        # Read the private sentence and available tool from the harness's real model
        # request. The fixture has no reference to Chief or the media client.
        prompt = " ".join(json.dumps(m.get("content")) for m in messages if m["role"] in ("system", "developer"))
        sentence = re.search(r"exact English sentence once: (The [a-z ]+\.)", prompt)
        names = [tool["function"]["name"] for tool in request.get("tools", [])]
        result = {"content": "Complete."}
        finish = "stop"
        if sentence and "talk" in names and messages[-1]["role"] == "user":
            result = {"tool_calls": [{"index": 0, "id": "call_" + uuid.uuid4().hex, "type": "function",
                                      "function": {"name": "talk", "arguments": json.dumps({"text": sentence[1]})}}]}
            finish = "tool_calls"
        identity = "chatcmpl-" + uuid.uuid4().hex
        frames = []
        for delta, end in [({"role": "assistant"}, None), (result, None), ({}, finish)]:
            chunk = {"id": identity, "object": "chat.completion.chunk", "model": request["model"],
                     "choices": [{"index": 0, "delta": delta, "finish_reason": end}]}
            frames.append("data: " + json.dumps(chunk) + "\n\n")
        body = ("".join(frames) + "data: [DONE]\n\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


@contextmanager
def model_peer(directory, harness):
    with ThreadingHTTPServer(("127.0.0.1", 0), Model) as server:
        endpoint = f"http://127.0.0.1:{server.server_port}/v1"
        if harness == "pi":
            directory.mkdir()
            config = {"providers": {"voice-fixture": {
                "baseUrl": endpoint, "api": "openai-completions", "apiKey": "voice-fixture",
                "models": [{"id": "voice-replay", "name": "Voice replay", "contextWindow": 128000, "maxTokens": 2048}]}}}
            (directory / "models.json").write_text(json.dumps(config))
            (directory / "settings.json").write_text(json.dumps({
                "defaultProvider": "voice-fixture", "defaultModel": "voice-replay", "defaultThinkingLevel": "off"}))
            environment, profile = {"PI_CODING_AGENT_DIR": str(directory)}, None
        else:
            config = {"model": "voice-fixture/voice-replay", "provider": {"voice-fixture": {
                "npm": "@ai-sdk/openai-compatible", "name": "Voice replay",
                "options": {"baseURL": endpoint, "apiKey": "voice-fixture"}, "models": {
                    "voice-replay": {"name": "Voice replay", "tool_call": True, "limit": {"context": 128000, "output": 2048}}}}}}
            environment = {"OPENCODE_CONFIG_CONTENT": json.dumps(config)}
            profile = {"useDefaultThreadSettings": False, "threadSettings": {"provider": "voice-fixture", "model": "voice-replay"}}
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            yield environment, profile
        finally:
            server.shutdown()
            worker.join()
