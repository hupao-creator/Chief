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
# A separately powered sound source can supply this near-end signal during local playback.
NEAR_END_BANDS = (1900, 2100, 2300)


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
        self.measure_bands = BANDS

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
                        peer.band_frames.append([band_power(mono, frame.sample_rate, frequency) for frequency in peer.measure_bands])
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


async def acoustic_challenge(peer, directory, monitor, *, local_playback):
    """Compare a raw room observation and the decoded uplink in the same playback window."""
    async def window():
        await monitor.command("resetBands")
        if local_playback:
            peer.band_frames = []
        await asyncio.sleep(0.28)
        frames, peer.band_frames = peer.band_frames, None
        room = await monitor.command("bands")
        if tuple(room["frequenciesHz"]) != BANDS + NEAR_END_BANDS:
            raise RuntimeError("Room monitor and receiver analysis frequencies differ.")
        samples = {"room": {"buffers": room["buffers"], "power": room["power"]}}
        if local_playback:
            samples["uplink"] = {"buffers": len(frames),
                                 "power": [sum(column) / len(frames) for column in zip(*frames)] if frames else []}
        return samples

    await asyncio.sleep(0.18)
    baseline = await window()
    baseline_time = asyncio.get_running_loop().time()
    evidence = {"roomFrequenciesHz": BANDS + NEAR_END_BANDS, "baseline": baseline, "windows": []}
    if local_playback:
        evidence["uplinkFrequenciesHz"] = peer.measure_bands
    for index in random.SystemRandom().sample(range(len(BANDS)), len(BANDS)):
        frequency = BANDS[index]
        player = None
        if local_playback:
            fixture = directory / f"generated-{frequency}.wav"
            with wave.open(str(fixture), "wb") as wav:
                wav.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
                wav.writeframes(tone_frame(frequency) * 40)
            player = await asyncio.create_subprocess_exec("/usr/bin/afplay", str(fixture))
        else:
            peer.tone.frequency = frequency
            peer.tone.enabled = True
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
        for source, sample in received.items():
            quiet = baseline[source]
            if min(quiet["buffers"], sample["buffers"]) < 3:
                sample["matched"] = None
                continue
            power = sample["power"]
            floor = max(1e-8, 5 * quiet["power"][index], 4 * max(p for i, p in enumerate(power[:len(BANDS)]) if i != index))
            sample.update(thresholdPower=floor, matched=power[index] > floor)
        evidence["windows"].append(dict(received, frequencyHz=frequency, startMS=start_ms, endMS=end_ms))
        await asyncio.sleep(0.16)
    peer.tone.frequency = 400
    return evidence


def verify_acoustics(acoustic, require_input_signal):
    system = acoustic["systemPlayback"]["windows"]
    if any(row["room"]["matched"] and row["uplink"]["matched"] for row in system):
        raise RuntimeError("A system playback tone reached the WebRTC microphone.")
    if not all(row["room"]["matched"] for path in acoustic.values() for row in path["windows"]):
        raise Blocked("The room microphone could not confirm every playback tone.")
    if any(row["uplink"]["matched"] is None for row in system):
        raise Blocked("Insufficient decoded microphone buffers during system playback.")
    if require_input_signal:
        # Confirm the independent tone was admitted in quiet and in every mixed window.
        def has_near_end(sample):
            low, signal, high = sample["power"][-len(NEAR_END_BANDS):]
            return signal > max(1e-8, 4 * max(low, high))

        quiet = acoustic["systemPlayback"]["baseline"]
        if not all(has_near_end(row["room"]) for row in [quiet, *system]):
            raise Blocked("The room microphone could not confirm the separate 2100 Hz control.")
        if not has_near_end(quiet["uplink"]):
            raise RuntimeError("The independent input tone did not reach the peer before playback.")
        if not all(has_near_end(row["uplink"]) for row in system):
            raise RuntimeError("The independent input tone disappeared during system playback.")


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
        if args.require_input_signal:
            if acoustics is None:
                print("Make a short sound at the microphone now.", file=sys.stderr, flush=True)
            else:
                peer.measure_bands = BANDS + NEAR_END_BANDS
                print("Play a steady 2100 Hz tone near the microphone from a separate device now.", file=sys.stderr, flush=True)
        await peer.wait_for_input(require_signal=args.require_input_signal)
        report["inputPeakBeforeMute"] = peer.peak
        if acoustics is not None:
            async with native_process(binary) as observer:
                await observer.command("monitor")
                acoustics["systemPlayback"] = await acoustic_challenge(peer, binary.parent, observer, local_playback=True)
                await observer.command("stopMonitor")
            if args.require_input_signal:
                print("The separate near-end tone can stop now.", file=sys.stderr, flush=True)
        peer.tone.enabled = True
        states["remoteAudio"] = await native.wait(inputRunning=True, outputRunning=True, speaking=True)
        await native.command("mute")
        states["playingWhileMuted"] = await native.wait(inputRunning=False, outputRunning=True, speaking=True)
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
                acoustics["webRTCPlayoutToRoomMicrophone"] = await acoustic_challenge(peer, binary.parent, observer, local_playback=False)
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
                if args.acoustic_loopback:
                    acoustic = report["acoustic"]
                    verify_acoustics(acoustic, args.require_input_signal)
                if args.require_input_signal and report["inputPeakBeforeMute"] <= 300:
                    raise Blocked("The microphone did not return a non-silent decoded sample.")
                report["status"] = "passed"
                return 0
        finally:
            lease.close()
            loop.remove_signal_handler(signal.SIGTERM)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exercise", action="store_true", help="Use the existing microphone and play a quiet tone locally.")
    parser.add_argument("--require-input-signal", action="store_true", help="Require non-silent input before the remote tone starts.")
    parser.add_argument("--acoustic-loopback", action="store_true", help="Check local playback rejection and audible remote playback with a room microphone.")
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
