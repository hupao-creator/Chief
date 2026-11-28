# /// script
# requires-python = ">=3.11"
# dependencies = ["aiortc==1.14.0"]
# ///
"""Exercise production VoiceMedia, a local WebRTC peer and per-process macOS audio I/O."""
import argparse
import array
import asyncio
from contextlib import asynccontextmanager
import fractions
import json
import math
import os
from pathlib import Path
import platform
import random
import signal
import subprocess
import sys
import tempfile
import wave

ROOT = Path(__file__).resolve().parents[3]
E2E = ROOT / "tools/e2e"
sys.path[:0] = [str(E2E), str(ROOT / "tools/benchmarks")]
from lease import DesktopLease
from lifecycle import Blocked
from report import sha256

MEDIA = ROOT / "app/macos/Sources/Voice"
SOURCES = [MEDIA / "VoiceMedia.swift", MEDIA / "VoicePlaybackActivity.swift", Path(__file__).with_suffix(".swift")]
FRAMEWORK = ROOT / "app/macos/.build/artifacts/webrtc-xcframework/LiveKitWebRTC/LiveKitWebRTC.xcframework/macos-arm64_x86_64"
BANDS = (650, 1000, 1450)


class Native:
    def __init__(self, process):
        self.process = process

    async def command(self, action, **values):
        self.process.stdin.write(json.dumps({"action": action, **values}).encode() + b"\n")
        await self.process.stdin.drain()
        async with asyncio.timeout(45):
            line = await self.process.stdout.readline()
        if not line:
            raise RuntimeError(f"native driver exited on {action}")
        result = json.loads(line)
        if error := result.get("error"):
            raise RuntimeError(f"{action}: {error}")
        return result

    async def wait(self, *, timeout=8, expect_failure=False, **expected):
        until = asyncio.get_running_loop().time() + timeout
        while True:
            state = await self.command("state")
            if state.get("mediaFailure") and not expect_failure:
                raise RuntimeError(f"media health failed: {state}")
            if all(state[k] == v for k, v in expected.items()) and (not expect_failure or state.get("mediaFailure")):
                return state
            if asyncio.get_running_loop().time() >= until:
                raise RuntimeError(f"native media did not reach {expected}, observed {state}")
            await asyncio.sleep(0.08)


class LocalPeer:
    def __init__(self, rtc, tone):
        self.rtc, self.tone = rtc, tone
        self.reader = None
        self.peak = 0
        self.decoded = 0
        self.band_frames = None

    async def packets(self):
        stats = await self.rtc.getStats()
        return sum(row.packetsReceived for row in stats.values() if row.type == "inbound-rtp" and row.kind == "audio")

    async def wait_for_input(self, after=0, require_signal=False):
        until = asyncio.get_running_loop().time() + 8
        while not self.decoded or await self.packets() <= after or require_signal and self.peak <= 300:
            if asyncio.get_running_loop().time() >= until:
                raise RuntimeError(f"no fresh requested microphone signal: packets={await self.packets()}, peak={self.peak}")
            await asyncio.sleep(0.08)


@asynccontextmanager
async def local_call(native):
    from aiortc import AudioStreamTrack, RTCPeerConnection, RTCConfiguration, RTCSessionDescription
    from aiortc.mediastreams import MediaStreamError
    from av import AudioFrame

    class Tone(AudioStreamTrack):
        enabled = False
        frequency = 400
        frames = 0
        started = None
        sounds = {frequency: tone_frame(frequency) for frequency in (400, *BANDS)}

        async def recv(self):
            clock = asyncio.get_running_loop()
            if self.started is None:
                self.started = clock.time()
            await asyncio.sleep(max(0, self.started + self.frames / 48000 - clock.time()))
            frame = AudioFrame(format="s16", layout="mono", samples=960)
            frame.planes[0].update(self.sounds[self.frequency] if self.enabled else bytes(1920))
            frame.sample_rate, frame.pts, frame.time_base = 48000, self.frames, fractions.Fraction(1, 48000)
            self.frames += 960
            return frame

    rtc = RTCPeerConnection(RTCConfiguration(iceServers=[]))
    peer = LocalPeer(rtc, Tone())
    rtc.addTrack(peer.tone)

    @rtc.on("track")
    def receive(track):
        async def drain():
            try:
                while True:
                    frame = await track.recv()
                    # Opus decodes to signed 16-bit interleaved audio. Retain only its peak.
                    samples = memoryview(frame.planes[0]).cast("h")[: frame.samples * len(frame.layout.channels)]
                    peer.peak = max(peer.peak, max(map(abs, samples), default=0))
                    peer.decoded += 1
                    if peer.band_frames is not None:
                        mono = samples[::len(frame.layout.channels)]
                        peer.band_frames.append([band_power(mono, frame.sample_rate, frequency) for frequency in BANDS])
            except MediaStreamError:
                return
        peer.reader = asyncio.create_task(drain())

    try:
        offer = await native.command("offer")
        await rtc.setRemoteDescription(RTCSessionDescription(sdp=offer["sdp"], type="offer"))
        await rtc.setLocalDescription(await rtc.createAnswer())
        peer.start_receipt = await native.command("answer", sdp=rtc.localDescription.sdp)
        yield peer
    finally:
        await rtc.close()
        if peer.reader:
            peer.reader.cancel()
            await asyncio.gather(peer.reader, return_exceptions=True)


def tone_frame(frequency):
    return array.array("h", (round(2600 * math.sin(2 * math.pi * frequency * i / 48000)) for i in range(960))).tobytes()


def band_power(samples, rate, frequency):
    coefficient = 2 * math.cos(2 * math.pi * frequency / rate)
    previous = older = 0.0
    for sample in samples:
        current = sample / 32768 + coefficient * previous - older
        older, previous = previous, current
    return 4 * max(0, previous**2 + older**2 - coefficient * previous * older) / len(samples)**2


async def acoustic_challenge(peer, directory, monitor=None):
    """The peer measures Chief's physical input; a separate HAL process measures Chief's physical output."""
    async def window():
        if monitor:
            await monitor.command("resetBands")
        else:
            peer.band_frames = []
        await asyncio.sleep(0.28)
        if monitor:
            result = await monitor.command("bands")
            return {"buffers": result["buffers"], "power": result["power"]}
        frames, peer.band_frames = peer.band_frames, None
        return {"buffers": len(frames), "power": [sum(column) / len(frames) for column in zip(*frames)] if frames else [0.0] * 3}

    await asyncio.sleep(0.18)
    baseline = await window()
    baseline_time = asyncio.get_running_loop().time()
    evidence = {"frequenciesHz": BANDS, "baseline": baseline, "windows": []}
    for index in random.SystemRandom().sample(range(len(BANDS)), len(BANDS)):
        frequency = BANDS[index]
        player = None
        if monitor:
            peer.tone.frequency = frequency
            peer.tone.enabled = True
        else:
            fixture = directory / f"generated-{frequency}.wav"
            with wave.open(str(fixture), "wb") as wav:
                wav.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
                wav.writeframes(tone_frame(frequency) * 40)
            player = await asyncio.create_subprocess_exec("/usr/bin/afplay", str(fixture))
        try:
            await asyncio.sleep(0.26)  # Covers device startup and the receiver jitter buffer.
            start_ms = round((asyncio.get_running_loop().time() - baseline_time) * 1000)
            received = await window()
            end_ms = round((asyncio.get_running_loop().time() - baseline_time) * 1000)
        finally:
            if player:
                async with asyncio.timeout(3):
                    if await player.wait() != 0:
                        raise RuntimeError("local acoustic fixture player failed")
            else:
                peer.tone.enabled = False
        power = received["power"]
        floor = max(1e-8, 5 * baseline["power"][index], 4 * max(p for i, p in enumerate(power) if i != index))
        matched = received["buffers"] >= 3 and power[index] > floor
        evidence["windows"].append(dict(received, frequencyHz=frequency, startMS=start_ms, endMS=end_ms,
                                        thresholdPower=floor, matched=matched))
        await asyncio.sleep(0.16)
    evidence["matched"] = baseline["buffers"] >= 3 and all(row["matched"] for row in evidence["windows"])
    peer.tone.frequency = 400
    return evidence


async def exercise(native, report, args, binary):
    states = report["observed"] = {}
    acoustics = report.setdefault("acoustic", {}) if args.acoustic_loopback else None
    await native.command("offer")
    states["pendingOffer"] = await native.wait(inputRunning=False, outputRunning=False)
    await native.command("close")
    states["cancelledOffer"] = await native.wait(inputRunning=False, outputRunning=False)

    async with local_call(native) as peer:
        states["startReturned"] = peer.start_receipt
        states["listening"] = await native.wait(inputRunning=True, outputRunning=True, speaking=False)
        if args.require_input_signal and acoustics is None:
            print("Make a short sound at the microphone now.", file=sys.stderr, flush=True)
        await peer.wait_for_input(require_signal=args.require_input_signal and acoustics is None)
        if acoustics is not None:
            acoustics["speakerToWebRTCMicrophone"] = await acoustic_challenge(peer, binary.parent)
        report["inputPeakBeforeMute"] = peer.peak
        peer.tone.enabled = True
        states["remoteAudio"] = await native.wait(inputRunning=True, outputRunning=True, speaking=True)
        await native.command("mute")
        states["playingWhileMuted"] = await native.wait(inputRunning=False, outputRunning=True, speaking=True, microphoneLevel=0)
        if states["playingWhileMuted"]["playbackLevel"] <= 0:
            raise RuntimeError("remote tone produced no playback level while muted")
        await asyncio.sleep(0.45)  # Let in-flight RTP drain before measuring the muted sender.
        before = await peer.packets()
        await asyncio.sleep(1.1)  # Spans two production health checks.
        after = await peer.packets()
        report["mutedInboundRTPPackets"] = [before, after]
        if before != after:
            raise RuntimeError("the muted microphone still sent RTP")
        await native.wait(inputRunning=False, outputRunning=True, speaking=True)
        peer.tone.enabled = False
        states["remoteSilence"] = await native.wait(inputRunning=False, outputRunning=True, speaking=False)
        if acoustics is not None:
            async with native_process(binary) as observer:
                await observer.command("monitor")
                await observer.wait(inputRunning=True)
                acoustics["webRTCPlayoutToRoomMicrophone"] = await acoustic_challenge(peer, binary.parent, observer)
                states["mutedWithRoomObserver"] = await native.wait(inputRunning=False, outputRunning=True)
                await observer.command("stopMonitor")
        states["unmuteReturned"] = await native.command("unmute")
        states["restoredInput"] = await native.wait(inputRunning=True, outputRunning=True)
        await peer.wait_for_input(after=after)
        report["resumedInboundRTPPackets"] = await peer.packets()
        await native.command("mute")
        await peer.rtc.close()
        states["lostPeerWhileMuted"] = await native.wait(expect_failure=True, inputRunning=False, outputRunning=False, speaking=False)
        await native.command("close")

    async with local_call(native) as fresh:
        states["freshStartReturned"] = fresh.start_receipt
        states["freshCall"] = await native.wait(inputRunning=True, outputRunning=True, speaking=False)
        await fresh.wait_for_input()
        fresh.tone.enabled = True
        states["playingBeforeHangup"] = await native.wait(inputRunning=True, outputRunning=True, speaking=True)
        await native.command("close")
        states["hungUp"] = await native.wait(inputRunning=False, outputRunning=False, speaking=False)


@asynccontextmanager
async def native_process(binary):
    process = await asyncio.create_subprocess_exec(binary, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
                                                   limit=256 * 1024)
    try:
        yield Native(process)
    finally:
        process.stdin.close()
        try:
            async with asyncio.timeout(5):
                await process.wait()
        except TimeoutError:
            process.kill()
            await process.wait()


async def run(args, report):
    framework = args.framework.resolve()
    library = framework / "LiveKitWebRTC.framework/LiveKitWebRTC"
    if not library.is_file():
        raise Blocked("Resolve the macOS Swift package, or pass the macOS framework directory with --framework.")
    report.update(revision=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                  platform=platform.platform(), frameworkSHA256=sha256(library),
                  sources={str(p.relative_to(ROOT)): sha256(p) for p in [*SOURCES, Path(__file__).resolve()]})
    with tempfile.TemporaryDirectory(prefix="chief-native-voice-") as directory:
        binary = Path(directory) / "ChiefVoiceAudioProbe"
        lease = DesktopLease(args.desktop_lease, args.owner)
        loop = asyncio.get_running_loop()
        loop.add_signal_handler(signal.SIGTERM, asyncio.current_task().cancel)
        try:
            report["lease"] = lease.acquire()
            subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-O", "-swift-version", "6",
                            "-module-cache-path", Path(directory) / "ModuleCache", "-target",
                            f"{platform.machine()}-apple-macosx26.0", "-F", framework, "-Xlinker", "-rpath", "-Xlinker",
                            framework, *SOURCES, "-o", binary], check=True, timeout=90)
            async with native_process(binary) as native:
                if args.meter_fixture:
                    report["meterFixture"] = await native.command("meterFixture")
                    report["status"] = "passed"
                    return 0
                status = report["preflight"] = await native.command("preflight")
                if not args.exercise:
                    report["status"] = "preflight"
                    return 0
                if status["microphonePermission"] != "authorized":
                    raise Blocked(f"Existing microphone permission for this launch host is {status['microphonePermission']}.")
                if not status["defaultInput"] or not status["defaultOutput"]:
                    raise Blocked("Default live input and output devices are required.")
                await exercise(native, report, args, binary)
                report["nativeMedia"] = "passed"
                if args.acoustic_loopback and not all(path["matched"] for path in report["acoustic"].values()):
                    raise Blocked("The physical microphone did not identify every emitted frequency in its playback window.")
                if args.require_input_signal and report["inputPeakBeforeMute"] <= 300:
                    raise Blocked("The microphone did not return a non-silent decoded sample.")
                report["status"] = "passed"
                return 0
        finally:
            lease.close()
            loop.remove_signal_handler(signal.SIGTERM)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--meter-fixture", action="store_true", help="Exercise both meter callbacks with synthetic PCM and no devices.")
    mode.add_argument("--exercise", action="store_true", help="Use the existing microphone and play a quiet tone locally.")
    parser.add_argument("--require-input-signal", action="store_true", help="Require non-silent input before the remote tone starts.")
    parser.add_argument("--acoustic-loopback", action="store_true", help="Play short local tones and match them at both physical microphone endpoints.")
    parser.add_argument("--framework", type=Path, default=FRAMEWORK)
    parser.add_argument("--desktop-lease", type=Path, default=Path("/private/tmp/mokusei-ui-verification.lock"))
    parser.add_argument("--owner", default=f"native-voice-{os.getpid()}")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if (args.require_input_signal or args.acoustic_loopback) and not args.exercise:
        parser.error("acoustic measurements need --exercise")
    report = {}
    try:
        code = asyncio.run(run(args, report))
    except Blocked as error:
        report.update(status="blocked", reason=str(error))
        code = 2
    except (asyncio.CancelledError, KeyboardInterrupt):
        report.update(status="interrupted")
        code = 1
    except Exception as error:
        report.update(status="failed", reason=f"{type(error).__name__}: {error}")
        code = 1
    result = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(result)
    print(result, end="")
    return code


if __name__ == "__main__":
    sys.exit(main())
