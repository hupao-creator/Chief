"""Replay Chief Bar's native editor against a private Runtime and loopback Codex provider."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path[:0] = [str(ROOT / "tools/e2e"), str(ROOT / "tools/benchmarks"), str(ROOT / "tools/verification")]
from adapter import wait_for
from build import validate
from gate.runner import lease
from gate.ux import native_lease
from lifecycle import Session
from native_replay import NativeReplay
from provider import declared_tools, find_tool
from reading.public import content
from report import save, sha256


def run(binary, output):
    output.mkdir(parents=True, exist_ok=False)
    save(output / "runtime.json", validate(binary))
    save(output / "native-build.json", validate(ROOT / "app/macos/.build/debug/Chief"))

    def event(kind, **fields):
        with (output / "events.jsonl").open("a") as log:
            print(json.dumps({"event": kind, **fields}), file=log)

    session = Session(binary, output, uuid.uuid4().hex, event)
    replay = NativeReplay(ROOT, "ChiefConversationReplay", "com.chief.conversation-replay." + uuid.uuid4().hex)
    messages = ["Please review the release notes.", "I’ll check the notes against the latest changes.",
                "Which section needs my attention?", "The upgrade instructions are ready for your review.",
                "Start with the install step."]
    attachment = "upgrade-preview.png"
    try:
        replay.compile([HERE / "NestedHeaderReplay.swift", HERE / "FilterFacePixels.swift"])
        save(output / "source.json", {"commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True, cwd=ROOT).strip(),
             "changes": subprocess.check_output(["git", "status", "--porcelain"], text=True, cwd=ROOT).splitlines(),
             "appSHA256": sha256(replay.executable)})
        session.prepare()
        shutil.copyfile(ROOT / "app/macos/Sources/Shared/PluginUI/Resources/ChiefOverviewIdle.png", session.root / attachment)
        save(session.root / "conversation.json", {"messages": messages, "attachment": attachment,
                                                   "draft": "I’ll check that section next."})
        session.start()
        session.configure()
        peer = session.peer
        peer.title = lambda _: "Review release notes"
        original = peer.respond
        called = set()

        def respond(request):
            tools = declared_tools(request)
            talk = find_tool(tools, "talk")
            if not talk:
                return original(request)
            inputs = json.dumps(request.get("input", []), ensure_ascii=False)
            create = find_tool(tools, "create_thread")
            calls = [("review", create, peer.creation_arguments(1), messages[0]),
                     ("first", talk, {"text": messages[1]}, messages[0]),
                     ("second", talk, {"text": messages[3]}, messages[2]),
                     ("detail", talk, {"text": messages[4]}, messages[2])]
            for key, tool, args, trigger in calls:
                if trigger in inputs and key not in called:
                    called.add(key)
                    return peer.response_events("", {"type": "function_call", "call_id": "chief_" + key,
                        "name": tool[0], "namespace": tool[1], "arguments": json.dumps(args)})
            return peer.response_events("Internal execution summary.", None)

        peer.respond = respond
        session.runtime.invoke("moku:submit", [{"input": {"parts": [{"kind": "text", "text": messages[0]}]}}])
        threads = wait_for(session.runtime.state, lambda state: any(not t.get("moku") for t in state["threads"]), 50)["threads"]
        owner = next(t["id"] for t in threads if t.get("moku"))

        def page():
            return content(session.runtime, owner, {"kind": "moku-conversation"})["value"]["messages"]

        initial = wait_for(page, lambda rows: [m["text"] for m in rows] == messages[:2], 50)
        save(output / "previous-messages.json", initial)
        for stage in ("send", "restart"):
            if stage == "restart":
                session.stop(session.process, "runtime before restart")
                session.start()
            status = replay.run(["--live-conversation", session.profile] + (["--restart"] if stage == "restart" else []), timeout=95)
            receipt = replay.workspace / "evidence" / ("conversation-" + stage + ".json")
            if status or not receipt.exists():
                raise RuntimeError(f"{stage} replay did not finish: " + (replay.root / "stdout.log").read_text()[-1500:])
            rows = page()
            if [r["text"] for r in rows] != messages or [r["role"] for r in rows] != ["user", "chief", "user", "chief", "chief"]:
                raise AssertionError("Persistent conversation differs from the submitted messages and acknowledged Talks")
            if [r.get("attachments", []) for r in rows] != [[], [], [attachment], [], []]:
                raise AssertionError("The attachment name did not follow its submitted message")
            ids = [r["id"] for r in rows]
            if len(set(ids)) != len(ids) or [r["createdAt"] for r in rows] != sorted(r["createdAt"] for r in rows):
                raise AssertionError("Conversation order or identities are inconsistent")
            if stage == "send":
                sent = rows
            elif rows != sent:
                raise AssertionError("Restart changed the committed conversation")
            save(output / ("runtime-" + stage + ".json"), rows)
    finally:
        try:
            replay.export(output)
        finally:
            replay.close()
            cleanup = session.close()
            save(output / "cleanup.json", cleanup)
            if not cleanup["ok"]:
                raise RuntimeError(f"Isolated replay cleanup failed: {cleanup}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, default=ROOT / ".build/e2e/chief-runtime")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    with lease(), native_lease():
        run(args.runtime.resolve(), args.output.resolve())
