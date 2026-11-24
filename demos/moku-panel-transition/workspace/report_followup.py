"""Record a native Report follow-up in a private, nonactivating workspace."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

from capture import DEMO, ROOT, Session, completed, declared_tools, find_tool, lease, native_lease, save, sha256, wait_for
from collection import enable_agent

sys.path.insert(0, str(ROOT / "tools/verification"))
from native_replay import NativeReplay


def capture(runtime, output, scenarios):
    output.mkdir(parents=True, exist_ok=False)

    def log(event, **details):
        with (output / "events.jsonl").open("a") as events:
            print(json.dumps({"event": event, **details}), file=events)

    session = Session(runtime, output, uuid.uuid4().hex, log)
    replay = NativeReplay(ROOT, "ReportFollowup", "com.chief.replay.offscreen-report")
    reference = {}
    try:
        workspace = Path(__file__).parent
        replay.compile([workspace / "ReadingPanelClose.swift", workspace / "ReportFollowup.swift",
                        DEMO / "CollapseCapture.swift", workspace / "ReportIdentity.swift", workspace / "TagReturn.swift"])
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
        session.runtime.invoke("moku:submit", [{"input": {"parts": [{"kind": "text",
            "text": "BENCHMARK CREATE 1 completed task. E2E " + session.nonce}]}}])
        wait_for(lambda: peer.receipts, lambda refs: len(refs) == 1, 60)
        thread = peer.receipts["bench_create_01"]["threadId"]
        execution = completed(session, thread)["observation"]["latestExecution"]["executionId"]
        reference.update(threadId=thread, executionId=execution)
        if "tag-return" in scenarios:
            peer.tagged_ids = {thread}
            enable_agent(session, "tag", True)
            wait_for(session.runtime.state, lambda state: any(t["id"] == thread and t.get("tags")
                     for t in state["threads"]), 90)
            enable_agent(session, "tag", False)
        enable_agent(session, "report", True)
        reports = wait_for(lambda: [item for item in session.runtime.state()["applicationThreads"]
            if item["ref"]["typeId"] == "report.document"], bool, 90)
        enable_agent(session, "report", False)
        for scenario in scenarios:
            process = session.spawn([replay.executable, session.profile, reports[0]["ref"]["threadId"],
                                     thread, execution, scenario], "report")
            if process.wait(timeout=95):
                raise RuntimeError((session.root / "report.txt").read_text()[-3000:])
            shutil.copytree(replay.application.parent / scenario, output / scenario)
    finally:
        cleanup = session.close()
        save(output / "cleanup.json", cleanup)
        replay.close()
        if not cleanup["ok"]:
            raise RuntimeError(f"Isolated replay cleanup failed: {cleanup}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="a new directory for the movie and observations")
    parser.add_argument("--runtime", type=Path, default=ROOT / ".build/e2e/chief-runtime")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--identity", action="store_true", help="record Report entry, Close and interrupted Close")
    mode.add_argument("--tag-return", action="store_true", help="record Overview filters during Report Close and reopen")
    args = parser.parse_args()
    with lease(), native_lease():
        scenarios = ["report-send"]
        if args.tag_return:
            scenarios = ["tag-return", "tag-return-reduced"]
        elif args.identity:
            scenarios = ["identity", "identity-reduced"]
        capture(args.runtime.resolve(), args.output.resolve(), scenarios)
