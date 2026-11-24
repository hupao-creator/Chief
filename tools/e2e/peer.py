"""Deterministic external Responses input; the native Codex engine stays real.

Reuse the benchmark's existing loopback protocol peer, read-only. This adapter
owns e2e payloads, never Runtime or UI state.
"""
import hashlib
import json
import threading
import uuid

from provider import Provider, declared_tools, find_tool


class Peer(Provider):
    def __init__(self, directory, nonce):
        self.nonce = nonce
        self.holds, self.input_cancellations = [], []
        self.collection_projects = []
        self.overview_project = None
        self.tagged_ids = set()
        self.report_sources = {}
        self.request_context = threading.local()
        super().__init__(directory, 1)

    def prepare_overview(self):
        self.count = 14
        self.overview_project = self.directory / "Review"
        self.overview_project.mkdir()

    def prepare_collection(self):
        self.collection_projects = [self.directory / name for name in ("Library", "Studio")]
        self.count = 14  # One standalone task and eight/four report sources per folder.
        for project in self.collection_projects:
            project.mkdir()

    def creation_arguments(self, index):
        args = super().creation_arguments(index)
        if self.collection_projects:
            library, studio = self.collection_projects
            args["cwd"] = str(library if index <= 9 else studio)
        elif self.overview_project and index <= 12:
            args["cwd"] = str(self.overview_project)
        return args

    def tag_response(self, request, tools):
        # Read the real pool, then use each mutation's revision-fenced result.
        status = None
        for item in reversed(request.get("input", [])):
            if item.get("role") == "user":
                break
            if item.get("type") == "function_call_output" and item.get("call_id", "").startswith("e2e_tag_"):
                raw = json.loads(item["output"].split("\nOutput:\n")[-1])
                if "content" in raw:
                    raw = json.loads(next(part["text"] for part in raw["content"] if part["type"] == "text"))
                status = raw.get("statusbar", raw)
                break
        if status is None:
            name, args = "read_statusbar", {}
        else:
            pending = sorted(self.tagged_ids.intersection(status["unassignedThreadIds"]))
            if not pending:
                return self.response_events("Classification complete.", None)
            if not status["tags"]:
                name, args = "create_tag", {"name": "Review work", "emoji": "📌"}
            else:
                name, args = "assign_threads", {"assignments": [
                    {"threadId": ident, "tagId": status["tags"][0]["id"]} for ident in pending]}
            args["expectedRevision"] = status["revision"]
        tool, namespace = find_tool(tools, name)
        return self.response_events("", {"type": "function_call", "call_id": "e2e_tag_" + uuid.uuid4().hex,
            "name": tool, "namespace": namespace, "arguments": json.dumps(args)})

    def respond(self, request):
        tools = declared_tools(request)
        if find_tool(tools, "assign_threads"):
            self.request_count += 1
            return self.tag_response(request, tools)
        if self.collection_projects and (create := find_tool(tools, "create_report")):
            self.request_count += 1
            inputs = request.get("input", [])
            done = {item.get("call_id") for item in inputs if item.get("type") == "function_call_output"}
            for item in reversed(inputs):
                if item.get("role") != "user":
                    continue
                for part in item["content"]:
                    text = part.get("text", "")
                    if "\nStatusbar: " not in text:
                        continue
                    status, _ = json.JSONDecoder().raw_decode(text.rsplit("\nStatusbar: ", 1)[1])
                    for row in status["unassignedThreads"]:
                        thread = row["id"]
                        if thread not in self.report_sources:
                            continue
                        call_id = "report_" + thread
                        if call_id in done:
                            continue
                        args = {"title": "Collection report " + thread[:8], "emoji": "📚",
                                "shortDescription": "Collection budget fixture", "html": "<p>Review</p>",
                                "coverHTML": "<div>Review</div>", "relatedExecutions": [
                                    {"threadId": thread, "executionId": self.report_sources[thread]}]}
                        return self.response_events("", {"type": "function_call", "call_id": call_id,
                            "name": create[0], "namespace": create[1], "arguments": json.dumps(args)})
                    return self.response_events("Reports complete.", None)
            raise ValueError("missing report statusbar")
        events = super().respond(request)
        # A real model-service stream remains active until the UI cancels it.
        # No Runtime operation or internal state is used to hold execution.
        hold = ("E2E STOP " + self.nonce in json.dumps(request.get("input", []))
                and any(e.get("type") == "response.output_text.delta" and
                        e.get("delta") == self.followup_body() for e in events))
        self.request_context.hold = hold
        if not hold:
            return events
        self.holds.append({"request": self.request_count, "purpose": "await actual composer Stop"})

        def stream():
            for event in events[:3]:
                yield event
            yield {**events[3], "delta": "Working on this follow-up. Waiting for the user's Stop action."}
            while not self.stopping.wait(.2):
                yield {"type": "response.in_progress", "response": events[0]["response"]}
        return stream()

    def failure(self, error):
        if getattr(self.request_context, "hold", False) and isinstance(error, (BrokenPipeError, ConnectionResetError)):
            self.input_cancellations.append({"reason": type(error).__name__, "purpose": "held external stream closed"})
        else:
            super().failure(error)

    def title(self, index):
        return "E2E review " + self.nonce

    def body(self, index):
        return f"# Review {self.nonce}\n\nFirst result: amber river cedar stone.\n\nCompleted initial task."

    def followup_body(self):
        return f"# Follow-up {self.nonce}\n\nSecond result: violet lake maple cloud.\n\nCompleted follow-up task."

    def answer(self, index, request):
        if "E2E FOLLOWUP " + self.nonce in json.dumps(request.get("input", [])):
            return self.followup_body()
        return self.body(index)

    def evidence(self):
        return {"kind": "deterministic-responses-peer-real-codex", "nonce": self.nonce,
                "requests": self.request_count, "receipts": self.receipts,
                "failures": self.failures, "controlCancellations": self.cancellations,
                "heldInputs": self.holds, "inputCancellations": self.input_cancellations,
                "payloads": {"initial": self.body(1), "followup": self.followup_body()}}


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()
