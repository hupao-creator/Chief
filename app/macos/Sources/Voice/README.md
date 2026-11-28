# Global Voice Mode

`ChiefVoice` provides a single workspace-level voice conversation with the selected Chief Harness. The module owns microphone permission, WebRTC, the runtime connection for the call and device teardown. Its public interface has no view, Thread selection or Harness-specific parameter.

## Use from a macOS host

Add `ChiefVoice` to the calling Swift target. Construct one session on the main actor with the workspace's connected `RuntimeClient` and retain it for the lifetime of the workspace.

```swift
import ChiefCore
import ChiefVoice

@MainActor
final class WorkspaceVoice {
    let session: GlobalVoiceSession

    init(client: RuntimeClient) {
        session = GlobalVoiceSession(client: client)
    }

    func beginConversation() { session.start() }
    func endConversation() { session.stop() }
    func toggleMicrophone() {
        session.setMicrophoneMuted(!session.isMicrophoneMuted)
    }
}
```

Bind to the observable `session.state`. Call `start()` on an explicit request from the user. On first use, macOS asks for microphone access. After a denial, the user can grant access in **System Settings → Privacy & Security → Microphone**.

| State | Meaning |
| --- | --- |
| `.idle` | Ready for an explicit start. |
| `.connecting` | Checking permission, negotiating the call or starting the audio devices. |
| `.listening` | The authenticated session, WebRTC connection, data channel and system playout are active. Input starts enabled. |
| `.stopping` | Microphone capture has stopped and the transport is draining. |
| `.failed(let message)` | The call or its bound Chief execution failed. Present the reason. An explicit start makes a fresh attempt. |

During `.listening`, `isMicrophoneMuted` and `isRemoteSpeaking` are independent observable values. The audio engine uses WebRTC software echo cancellation and noise suppression so the input and output can run independently. Muting detaches the microphone track from its negotiated RTP sender, closes the audio engine's input gate and stops recording. The receiver, output device, data channel and connection health checks stay active. Unmuting reattaches the same local track and confirms the audio device module is recording before publishing the change. A device transition that fails ends the call with its reason.

`isRemoteSpeaking` follows audible PCM on the negotiated remote track. The meter samples signed 16-bit audio, retains the time of the latest buffer above approximately −48 dBFS, and returns to quiet after 240 ms without audible samples. The default WebRTC audio processing module also taps the processed local capture buffer. Each audio callback measures per-buffer RMS, gates levels below approximately −48 dBFS and publishes the strongest normalized window since the last UI sample. The main actor samples every 40 ms, with faster attack than release. The UI observes separate microphone and playback levels and the held remote-speaking flag. PCM stays inside the audio callbacks. Muting clears the microphone level immediately. System volume and the level at the listener's ear are outside this measurement.

`stop()` is valid during permission, negotiation or listening. Repeated starts during a call or its drain are idempotent. Releasing the session closes its devices. A disconnected call ends, and accepted Chief tasks continue under their own execution IDs. Stop and failure clear both media indicators. A new call starts with fresh speech ownership and an enabled microphone.

The active Chief configuration selects the target across all reading pages. The voice relay independently needs a discovered Codex installation, native ChatGPT authentication, V3 availability and provider network access. The calling bundle needs the signed microphone entitlement and purpose string. [Native relay and admission](../../../../internal/plugins/harness/codex/voice/README.md) · [Packaging](../../build/README.md#package-contents) · [Live verification](../../../../tools/e2e/README.md#global-voice)

## Verify native microphone and playout

Resolve the macOS Swift package to install its pinned WebRTC framework. The [native probe](../../../../tools/e2e/global-voice/native.py) holds the shared desktop lease while compiling the production media files and running the probe. Its default mode reads the launch host's microphone authorization and default device availability without requesting permission or starting I/O.

```sh
python3 tools/e2e/global-voice/native.py
python3 tools/e2e/global-voice/native.py --meter-fixture
uv run tools/e2e/global-voice/native.py --exercise --output /tmp/chief-native-voice.json
uv run tools/e2e/global-voice/native.py --exercise --acoustic-loopback --require-input-signal --output /tmp/chief-native-acoustics.json
```

Run the exercise on a Mac with an already-authorized launch host, live input and output devices, and an available shared desktop lease. The exercise uses one local WebRTC peer and a quiet 400 Hz tone. It records CoreAudio input/output activity when startup and unmute return, and checks received microphone RTP, ceased RTP while muted, ongoing remote sound while muted, silence detection, restored capture, peer loss, reconnection and hangup. It also cancels an offer before opening either device.

`--acoustic-loopback` plays three brief local tones in randomized order at the existing volume. The receiving peer measures their frequency power in scheduled windows and compares it with a quiet baseline and neighboring bands. It then sends a second sequence down WebRTC while Chief's input is muted. A separate local process measures those tones with the default microphone. These two checks use a microphone within earshot of the default speaker. The JSON records only power measurements, times and states. `--require-input-signal` additionally requires a non-silent decoded microphone sample. Used alone, that switch prompts the operator to make a sound. The signed host and the Chief/provider handoff have separate verification. [Native-account speech replay](../../../../tools/e2e/README.md#global-voice)
