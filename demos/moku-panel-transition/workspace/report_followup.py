"""Record a native Report follow-up in a private, nonactivating workspace."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
import uuid

from capture import DEMO, ROOT, Session, completed, declared_tools, find_tool, lease, native_lease, save, sha256, wait_for
from collection import enable_agent

sys.path.insert(0, str(ROOT / "tools/verification"))
from native_replay import NativeReplay


def capture(runtime, output, identity=False):
    output.mkdir(parents=True, exist_ok=False)

    def log(event, **details):
        with (output / "events.jsonl").open("a") as events:
            print(json.dumps({"event": event, **details}), file=events)

    session = Session(runtime, output, uuid.uuid4().hex, log)
    replay = NativeReplay(ROOT, "ReportFollowup", "com.chief.replay.offscreen-report")
    reference = {}
    finished_source = threading.Event()
    try:
        replay.compile([Path(__file__).with_name("ReadingPanelClose.swift"), Path(__file__).with_name("ReportFollowup.swift"), DEMO / "CollapseCapture.swift", Path(__file__).with_name("ReportIdentity.swift")])
        save(output / "build.json", {"captureHostSHA256": sha256(replay.executable), "runtimeSHA256": sha256(runtime),
            "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "productionDiff": subprocess.check_output(["git", "diff", "HEAD", "--", "app/macos/Sources"], cwd=ROOT, text=True)})
        session.prepare()
        session.start()
        session.configure()
        peer = session.peer
        peer.count = 1
        peer.title = lambda _: "Review the Overview measurements"
        peer.body = lambda _: "The previous execution completed its review."
        respond = peer.respond

        def report_response(request):
            tools = declared_tools(request)
            inputs = request.get("input", [])
            create = find_tool(tools, "create_report")
            if create:
                if any(item.get("type") == "function_call_output" for item in inputs):
                    return peer.response_events("Report complete.", None)
                if not finished_source.wait(30):
                    raise TimeoutError("The report needs a completed source execution")
                args = {"title": "Overview measurements", "emoji": "📊", "shortDescription": "Read the source and follow up.",
                        "html": "<h1>Overview measurements</h1><p>The previous execution reviewed the Overview measurements. Its result is open in the right-hand column.</p>",
                        "coverHTML": "<p>Overview measurements</p>", "relatedExecutions": [reference]}
                return peer.response_events("", {"type": "function_call", "call_id": "report_measurements", "name": create[0],
                    "namespace": create[1], "arguments": json.dumps(args)})
            metadata = request.get("text", {}).get("format", {}).get("schema")
            if not metadata and not find_tool(tools, "create_thread") and "修复完成了吗" in json.dumps(inputs, ensure_ascii=False):
                events = peer.response_events("The fix is complete. The new execution has verified the result.", None)

                def stream():
                    yield events[0]
                    time.sleep(2.4)
                    yield from events[1:4]
                    time.sleep(1.1)
                    yield from events[4:]

                return stream()
            return respond(request)

        peer.respond = report_response
        enable_agent(session, "report", True)
        session.runtime.invoke("moku:submit", [{"input": {"parts": [{"kind": "text",
            "text": "BENCHMARK CREATE 1 completed task. E2E " + session.nonce}]}}])
        wait_for(lambda: peer.receipts, lambda refs: len(refs) == 1, 60)
        thread = peer.receipts["bench_create_01"]["threadId"]
        execution = completed(session, thread)["observation"]["latestExecution"]["executionId"]
        reference.update(threadId=thread, executionId=execution)
        finished_source.set()
        reports = wait_for(lambda: [item for item in session.runtime.state()["applicationThreads"]
            if item["ref"]["typeId"] == "report.document"], bool, 90)
        enable_agent(session, "report", False)
        for scenario in (["identity", "identity-reduced"] if identity else ["report-send"]):
            process = session.spawn([replay.executable, session.profile, reports[0]["ref"]["threadId"],
                                     thread, execution, scenario], "report")
            if process.wait(timeout=95):
                raise RuntimeError((session.root / "report.txt").read_text()[-3000:])
            shutil.copytree(replay.application.parent / scenario, output / scenario)
    finally:
        finished_source.set()
        cleanup = session.close()
        save(output / "cleanup.json", cleanup)
        replay.close()
        if not cleanup["ok"]:
            raise RuntimeError(f"Isolated replay cleanup failed: {cleanup}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="a new directory for the movie and observations")
    parser.add_argument("--runtime", type=Path, default=ROOT / ".build/e2e/chief-runtime")
    parser.add_argument("--identity", action="store_true", help="record Report entry, Close and interrupted Close")
    args = parser.parse_args()
    with lease(), native_lease():
        capture(args.runtime.resolve(), args.output.resolve(), args.identity)
