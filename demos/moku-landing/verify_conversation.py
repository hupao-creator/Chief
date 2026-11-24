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


def verify_layout(visit, stage):
    for size, width, height, panel, bottom in (("regular", 1100, 800, 648, 36), ("small", 860, 600, 546, 30)):
        single, multiline = visit[size], visit[size + "Multiline"]
        for frame in (single, multiline):
            for name, expected in (("windowWidth", width), ("windowHeight", height), ("panelHeight", panel),
                                   ("bottomMargin", bottom), ("sameSpeakerGap", 7), ("speakerChangeGap", 14)):
                if abs(frame[name] - expected) > 1:
                    raise AssertionError(f"{size} {name}: expected {expected} pt, measured {frame[name]} pt")
            if frame["topMargin"] < 23 or frame["documentHeight"] <= frame["listHeight"]:
                raise AssertionError(f"Expected overflowing messages inside the Dock margins: {frame}")
        editor_growth = multiline["editorHeight"] - single["editorHeight"]
        list_shrinkage = single["listHeight"] - multiline["listHeight"]
        if editor_growth <= 1 or abs(list_shrinkage - editor_growth) > 1:
            raise AssertionError(f"{size} message list did not make room for the draft: {single}, {multiline}")
        if stage == "send":
            short = visit["short"][size]
            if (short["panelHeight"] >= panel or abs(short["listHeight"] - short["documentHeight"]) > 1
                    or min(short["topGap"], short["bottomGap"]) < -1):
                raise AssertionError(f"{size} short conversation did not fit the date and message bubbles: {short}")


def run(binary, output):
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
        "状态标签已更新。\n\n中文界面\n左侧列表：运行中\n任务卡片：已完成\n\n"
        "英文界面\n左侧列表：Running\n任务卡片：Completed\n\n"
        "接下来核对两个窗口：\n在普通窗口里对照截图。\n缩小窗口，逐行查看消息。\n输入四行草稿，再读一次最新回复。",
        "截图中标注的两处都已核对，附件仍然跟着这条消息。",
    ]
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
            verify_layout(json.loads(receipt.read_text()), stage)
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
