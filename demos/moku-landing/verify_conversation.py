"""Replay Chief Bar's native editor against a private Runtime and loopback Codex provider."""
import argparse
import json
from pathlib import Path
import shutil
import signal
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


def verify_layout(visit):
    for size, height in (("regular", 540), ("small", 480), ("smallMultiline", 480)):
        frame = visit[size]
        for name, expected in (("panelHeight", height), ("sameSpeakerGap", 7), ("speakerChangeGap", 14)):
            if abs(frame[name] - expected) > 1:
                raise AssertionError(f"{size} {name}: expected {expected} pt, measured {frame[name]} pt")
    small, multiline = visit["small"], visit["smallMultiline"]
    editor_growth = multiline["editorHeight"] - small["editorHeight"]
    list_shrinkage = small["listHeight"] - multiline["listHeight"]
    if editor_growth <= 1 or abs(list_shrinkage - editor_growth) > 1:
        raise AssertionError(f"Resized message list did not make room for the draft: {small}, {multiline}")


def run(binary, output, send_refresh):
    output.mkdir(parents=True, exist_ok=False)
    save(output / "runtime.json", validate(binary))
    save(output / "native-build.json", validate(ROOT / "app/macos/.build/debug/Chief"))

    def event(kind, **fields):
        with (output / "events.jsonl").open("a") as log:
            print(json.dumps({"event": kind, **fields}), file=log)

    session = Session(binary, output, uuid.uuid4().hex, event)
    replay = NativeReplay(ROOT, "ChiefConversationReplay", "com.chief.conversation-replay." + uuid.uuid4().hex)
    messages = [
        "请看一下「展开全文」的效果。图片附件能按原来的比例显示吗？我想在小窗口里也看清截图中的文字。",
        "我会把截图放进展开后的消息里，保留图片的宽高比。改完会用同一张图片分别查看普通窗口和小窗口，核对正文换行和附件的位置。",
        "精简一下状态文案，把「仅运行中」和「仅已完成」改成「运行中」和「已完成」。附件里标出了需要调整的位置。",
        "两个标签已经改为「运行中」和「已完成」，英文也同步为 Running 和 Completed。接下来会缩小窗口，检查多行消息和下方的输入框能否同时看清。",
        "截图中标注的两处都已核对，附件仍然跟着这条消息。",
    ]
    if send_refresh:
        messages[0] += "\n" + "\n".join(f"核对项目 {n}" for n in range(1, 19))
    attachment = "界面标注.png"
    try:
        replay.compile([HERE / "NestedHeaderReplay.swift", HERE / "FilterFacePixels.swift"])
        save(output / "source.json", {"commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True, cwd=ROOT).strip(),
             "changes": subprocess.check_output(["git", "status", "--porcelain"], text=True, cwd=ROOT).splitlines(),
             "appSHA256": sha256(replay.executable)})
        session.prepare()
        shutil.copyfile(ROOT / "app/macos/Sources/Shared/PluginUI/Resources/ChiefOverviewIdle.png", session.root / attachment)
        save(session.root / "conversation.json", {"messages": messages, "attachment": attachment,
                                                   "draft": "我再核对一下小窗口。"})
        session.start()
        session.configure()
        peer = session.peer
        peer.title = lambda _: "核对窗口截图"
        original = peer.respond
        called = set()

        def respond(request):
            tools = declared_tools(request)
            talk = find_tool(tools, "talk")
            if not talk:
                return original(request)
            inputs = [part.get("text", "") for item in request.get("input", [])
                      for part in item.get("content", []) if isinstance(part, dict)]
            completed = {item.get("call_id") for item in request.get("input", [])
                         if item.get("type") == "function_call_output"}
            if send_refresh and any(messages[2] in text for text in inputs):
                # The native reader releases Talk only after observing both sends.
                wait_for(lambda: (session.root / "allow-reply").exists() or peer.stopping.is_set(), bool, 45)
            create = find_tool(tools, "create_thread")
            calls = [("review", create, peer.creation_arguments(1), messages[0]),
                     ("first", talk, {"text": messages[1]}, messages[0]),
                     ("second", talk, {"text": messages[3]}, messages[2]),
                     ("detail", talk, {"text": messages[4]}, messages[2])]
            for key, tool, args, trigger in calls:
                # A steer can supersede an in-flight model response before its tool runs.
                # Advance the held exchange only on tool outputs in the native request.
                call_id = "chief_" + key
                done = call_id in completed if send_refresh and key in ("second", "detail") else key in called
                if not done and any(trigger.splitlines()[0] in text for text in inputs):
                    called.add(key)
                    return peer.response_events("", {"type": "function_call", "call_id": call_id,
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
        if send_refresh:
            try:
                status = replay.run(["--live-conversation", session.profile, "--send-refresh", session.process.pid], timeout=95)
            finally:
                session.process.send_signal(signal.SIGCONT)
                (session.root / "allow-reply").touch()
            if status or not (replay.workspace / "evidence/conversation-refresh.json").exists():
                raise RuntimeError("Send refresh replay failed: " + (replay.root / "stdout.log").read_text()[-1500:])
            rows = page()
            save(output / "runtime-refresh.json", rows)
            if ([r["text"] for r in rows] != [*messages[:3], *messages[2:]]
                    or [r.get("attachments", []) for r in rows] != [[], [], [], [attachment], [], []]
                    or len({r["id"] for r in rows}) != len(rows)):
                raise AssertionError("Repeated sends or their Talk replies did not persist exactly once")
            return
        for stage in ("send", "restart"):
            if stage == "restart":
                session.stop(session.process, "runtime before restart")
                session.start()
            status = replay.run(["--live-conversation", session.profile] + (["--restart"] if stage == "restart" else []), timeout=95)
            receipt = replay.workspace / "evidence" / ("conversation-" + stage + ".json")
            if status or not receipt.exists():
                raise RuntimeError(f"{stage} replay did not finish: " + (replay.root / "stdout.log").read_text()[-1500:])
            verify_layout(json.loads(receipt.read_text()))
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
    parser.add_argument("--send-refresh", action="store_true", help="hold admission and replies across panel and compact sends")
    args = parser.parse_args()
    with lease(), native_lease():
        run(args.runtime.resolve(), args.output.resolve(), args.send_refresh)
