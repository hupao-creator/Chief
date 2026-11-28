# /// script
# requires-python = ">=3.11"
# dependencies = ["aiortc==1.14.0"]
# ///
"""Opt-in native account check. Send synthetic speech only, using a disposable Chief profile."""
import argparse
import array
import asyncio
from contextlib import nullcontext
import fractions
import hashlib
import http.client
import json
import os
import random
import re
import socket
from pathlib import Path
import subprocess
import sys
import tempfile
import wave

from aiortc import AudioStreamTrack, RTCConfiguration, RTCPeerConnection, RTCSessionDescription
from av import AudioFrame

from model_peer import model_peer

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/benchmarks"))
from adapter import Runtime

def words(text):
    return re.findall(r"[\w]+", text.casefold())


def target_sentence():
    choose = random.SystemRandom().choice
    return "The " + choose(["amber", "silver", "golden", "green"]) + " " + choose(
        ["otter", "tiger", "rabbit", "badger"]) + " found the " + choose(["map", "compass", "lantern", "basket"]) + "."


class SyntheticMic(AudioStreamTrack):
    def __init__(self, samples):
        super().__init__()
        self.samples = samples
        self.position = self.timestamp = 0
        self.clock = None
        self.enabled = False

    async def recv(self):
        rate, size = 24000, 480
        now = asyncio.get_running_loop().time()
        if self.clock is None:
            self.clock = now
        await asyncio.sleep(max(0, self.clock + self.timestamp / rate - now))
        data = b""
        if self.enabled:
            data = self.samples[self.position:self.position + 2 * size]
            self.position += len(data)
        frame = AudioFrame(format="s16", layout="mono", samples=size)
        frame.planes[0].update(data.ljust(2 * size, b"\0"))
        frame.sample_rate, frame.pts, frame.time_base = rate, self.timestamp, fractions.Fraction(1, rate)
        self.timestamp += size
        return frame


async def exercise(binary, root, harness, rounds, report, model_environment, execution_profile):
    expected = target_sentence()
    report["targetSentence"] = expected
    wav = root / "request.wav"
    subprocess.run(["say", "-v", "Samantha", "-o", str(wav), "--file-format=WAVE", "--data-format=LEI16@24000",
                    "Chief, what is the workspace verification sentence in your private routing preferences? Please say only that exact sentence in English using your Talk tool."], check=True, timeout=20)
    with wave.open(str(wav), "rb") as file:
        assert (file.getsampwidth(), file.getnchannels(), file.getframerate()) == (2, 1, 24000)
        track = SyntheticMic(file.readframes(file.getnframes()))
    profile = root / "profile"
    native_home = os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))
    # Profile and Chief workspace live in this temporary tree. Native account
    # access goes through the installed Codex executable and its own auth store.
    env = dict(os.environ, HOME=str(root), CODEX_HOME=native_home, CHIEF_HEADLESS="1")
    env.update(model_environment)
    process = subprocess.Popen([binary, "serve", "--data-dir", profile], cwd=root, env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    rtc = RTCPeerConnection(RTCConfiguration(iceServers=[]))
    events = lease = None
    sockets = []
    output = terminal = None
    try:
        discovery = profile / "runtime/connection.json"
        async with asyncio.timeout(45):
            while not discovery.is_file():
                if process.poll() is not None:
                    raise RuntimeError("isolated runtime exited during startup")
                await asyncio.sleep(0.1)
        service = Runtime(profile)
        state = await asyncio.to_thread(service.state)
        settings = state["settings"]
        settings["moku"]["hostHarnessPreference"] = harness
        if execution_profile is not None:
            # Apply the selected destination's ordinary Chief Agent profile.
            # The runtime owns validation and model admission.
            settings["moku"]["executionHarnesses"][harness] = execution_profile
        # Only the selected Chief receives this value in its own system prompt.
        settings["moku"]["routingPreset"] = "custom"
        settings["moku"]["routingGuidance"] = (
            "When asked for the workspace verification sentence, answer directly with the talk tool. "
            f"For every such request, including a repeated one, use this exact English sentence once: {expected}")
        for entry in settings["pluginSettings"]:
            if entry["id"] in ("tag.settings", "report.settings"):
                entry["value"]["enabled"] = False
        result = await asyncio.to_thread(service.invoke, "app:update-settings",
            [{"settings": settings, "expectedSettingsRevision": state["settingsRevision"]}])
        if result.get("status") == "conflict":
            raise RuntimeError("isolated profile setup conflicted")
        connection = json.loads(discovery.read_text())
        headers = {"Authorization": "Bearer " + connection["token"], "X-Mokusei-Epoch": connection["epoch"],
                   "X-Mokusei-Protocol": str(connection["protocolVersion"]), "Content-Type": "application/json"}
        events = http.client.HTTPConnection("127.0.0.1", connection["port"], timeout=120)
        events.request("GET", "/events", headers=headers)
        sockets.append(events.sock)
        event_stream = events.getresponse()
        hello = json.loads(event_stream.readline())
        lease = http.client.HTTPConnection("127.0.0.1", connection["port"], timeout=120)
        rtc.addTrack(track)
        channel = rtc.createDataChannel("oai-events", ordered=True)
        non_silent_audio = False
        context_appends = 0
        output_segments = {}
        remote_turns = {}
        event_types = set()

        @channel.on("message")
        def data_event(payload):
            nonlocal context_appends
            try:
                event = json.loads(payload)
            except (ValueError, TypeError):
                return
            kind = event.get("type")
            event_types.add(kind)
            if kind == "session.context.appended":
                context_appends += 1
            elif kind == "output_transcript.added":
                item = event.get("item", {})
                if isinstance(item.get("id"), str) and isinstance(item.get("text"), str):
                    output_segments[item["id"]] = item["text"]
            if kind in ("turn.created", "turn.done"):
                turn = event.get("turn", {})
                if turn.get("role") == "assistant":
                    remote_turns[turn["id"]] = turn["transcript"]
            elif kind == "turn.delta" and event.get("turn_id") in remote_turns:
                remote_turns[event["turn_id"]] += event["delta"]

        async def listen(receiver):
            nonlocal non_silent_audio
            while True:
                frame = await receiver.recv()
                samples = array.array("h", bytes(frame.planes[0])[:frame.samples * 2])
                if max((abs(v) for v in samples), default=0) > 300:
                    non_silent_audio = True

        @rtc.on("track")
        def got_track(receiver):
            nonlocal output
            output = asyncio.create_task(listen(receiver))

        await rtc.setLocalDescription(await rtc.createOffer())
        lease.request("POST", "/voice/global", json.dumps({"clientId": hello["clientId"], "offer": rtc.localDescription.sdp}), headers)
        sockets.append(lease.sock)
        response = await asyncio.to_thread(lease.getresponse)
        first = json.loads(await asyncio.to_thread(response.readline))
        if "answer" not in first:
            raise RuntimeError(first.get("error", {}).get("message", "missing SDP answer"))
        terminal = asyncio.create_task(asyncio.to_thread(response.readline))
        report["sdpAnswer"] = True
        await rtc.setRemoteDescription(RTCSessionDescription(sdp=first["answer"], type="answer"))
        async with asyncio.timeout(30):
            while rtc.connectionState != "connected" or channel.readyState != "open":
                await asyncio.sleep(0.1)
        report["webrtcConnected"] = True
        print("Native V3 returned SDP and opened the WebRTC data channel.", file=sys.stderr, flush=True)
        await asyncio.sleep(1)
        expected_words = words(expected)

        def check_remote_output():
            report.update(contextAppends=context_appends, outputTranscript=list(remote_turns.values()),
                          outputSegments=list(output_segments.values()), dataEvents=sorted(event_types),
                          nonSilentRemoteAudio=non_silent_audio)
            if terminal.done():
                final = terminal.result()
                message = json.loads(final).get("error", {}).get("message") if final else None
                raise RuntimeError(message or "voice connection ended during replay")
            if context_appends:
                raise RuntimeError("the voice session received an unexpected speech append")
            for transcripts in (remote_turns, output_segments):
                segment = words(" ".join(transcripts.values()))
                if any(segment[i:i + len(expected_words)] == expected_words for i in range(len(segment))):
                    raise RuntimeError("the private Talk appeared in the remote voice transcript")

        admissions, inputs, rows, talks, talk_executions = {}, {}, {}, {}, {}
        voice_session = None
        for count in range(1, rounds + 1):
            previous_handoffs, previous_talks = set(admissions), set(talks)
            track.position = 0
            track.enabled = True
            async with asyncio.timeout(100):
                while True:
                    check_remote_output()
                    state = await asyncio.to_thread(service.state)
                    owner = next(t for t in state["threads"] if t.get("moku"))
                    if owner["harnessId"] != harness:
                        raise RuntimeError("wrong Chief execution owner")
                    execution = owner.get("observation", {}).get("latestExecution") or {}
                    report["destination"] = {key: execution[key] for key in ("executionId", "status", "error") if key in execution}
                    for row in owner.get("transcript", []):
                        if (row.get("role") == "user" and row.get("status") == "complete"
                                and row.get("voiceHandoffId") and row.get("voiceSessionId") and row.get("executionId")):
                            handoff = row["voiceHandoffId"]
                            if voice_session is None:
                                voice_session = row["voiceSessionId"]
                            if (voice_session != row["voiceSessionId"] or rows.get(handoff, row["id"]) != row["id"]
                                    or admissions.get(handoff, row["executionId"]) != row["executionId"]):
                                raise RuntimeError("handoff was admitted more than once or changed ownership")
                            if "workspace verification sentence" not in " ".join(words(row["content"])):
                                raise RuntimeError("the destination did not receive the recorded request")
                            admissions[handoff], inputs[handoff], rows[handoff] = row["executionId"], row["content"], row["id"]
                        if (row.get("name") == "talk" and row.get("completedAt") and not row.get("isError")
                                and row.get("result", {}).get("ok") and row.get("executionId") in admissions.values()):
                            talks[row["id"]] = row["arguments"]["text"]
                            talk_executions[row["id"]] = row["executionId"]
                    new_handoffs = admissions.keys() - previous_handoffs
                    new_talks = talks.keys() - previous_talks
                    bound_talk = False
                    if len(new_handoffs) == len(new_talks) == 1:
                        hid, tid = next(iter(new_handoffs)), next(iter(new_talks))
                        bound_talk = talks[tid] == expected and talk_executions[tid] == admissions[hid]
                    report.update(audioSent=track.position == len(track.samples), admittedHandoffs=admissions,
                                  voiceSessionId=voice_session, inputTranscripts=inputs,
                                  committedTalk=list(talks.values()), talkExecutions=talk_executions)
                    if report["audioSent"] and len(admissions) == count and bound_talk:
                        break
                    await asyncio.sleep(0.15)
            track.enabled = False
            await asyncio.sleep(1.5)
            check_remote_output()
            report["verifiedRounds"] = count
            print(f"Round {count} confirmed destination admission and committed Talk.", file=sys.stderr, flush=True)
    finally:
        for stream_socket in sockets:
            try:
                stream_socket.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        if lease:
            lease.close()
        if events:
            events.close()
        await rtc.close()
        if output:
            output.cancel()
            await asyncio.gather(output, return_exceptions=True)
        process.terminate()
        try:
            await asyncio.to_thread(process.wait, 15)
        except subprocess.TimeoutExpired:
            process.kill()
            await asyncio.to_thread(process.wait)
        if terminal:
            await asyncio.gather(terminal, return_exceptions=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--harness", choices=("codex", "pi", "claude", "opencode"), default="codex")
    parser.add_argument("--rounds", type=int, choices=(1, 2), default=1, help="repeat the identical recording on one call")
    destination = parser.add_mutually_exclusive_group()
    destination.add_argument("--pi-loopback", action="store_true", help="run the installed Pi with a deterministic local model")
    destination.add_argument("--opencode-loopback", action="store_true", help="run installed OpenCode with a deterministic local model")
    destination.add_argument("--chief-profile", type=Path, help="JSON Chief Agent execution settings for the selected harness")
    args = parser.parse_args()
    if args.pi_loopback and args.harness != "pi":
        parser.error("--pi-loopback requires --harness pi")
    if args.opencode_loopback and args.harness != "opencode":
        parser.error("--opencode-loopback requires --harness opencode")
    loopback = args.pi_loopback or args.opencode_loopback
    binary = args.runtime.resolve()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    metadata = subprocess.check_output([ROOT / "scripts/go.sh", "version", "-m", binary], cwd=ROOT, text=True)
    settings = dict(re.findall(r"^\s*build\s+(vcs\.\w+)=(.+)$", metadata, re.MULTILINE))
    if settings.get("vcs.revision") != revision or settings.get("vcs.modified") not in ("true", "false"):
        parser.error("Build chief-runtime from this checkout before running the live replay.")
    report = {"revision": revision, "sourceDirty": settings["vcs.modified"] == "true",
              "driverDirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT)),
              "runtimeSha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
              "harness": args.harness, "rounds": args.rounds, "targetModel": "loopback" if loopback else "native account", "audioSource": "synthetic", "passed": False}
    try:
        with tempfile.TemporaryDirectory(prefix="chief-voice-live-") as root:
            directory = Path(root)
            peer = model_peer(directory / "agent", args.harness) if loopback else nullcontext(({}, None))
            with peer as (environment, execution_profile):
                if args.chief_profile:
                    profile_bytes = args.chief_profile.read_bytes()
                    execution_profile = json.loads(profile_bytes)
                    report["chiefProfileSHA256"] = hashlib.sha256(profile_bytes).hexdigest()
                asyncio.run(exercise(binary, directory, args.harness, args.rounds, report, environment, execution_profile))
        report["passed"] = True
    except Exception as error:
        report["failure"] = str(error) or type(error).__name__
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report["passed"] else 1

if __name__ == "__main__":
    sys.exit(main())
