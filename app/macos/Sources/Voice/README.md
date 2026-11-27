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
}
```

Bind to the observable `session.state`. Call `start()` on an explicit request from the user. On first use, macOS asks for microphone access. After a denial, the user can grant access in **System Settings → Privacy & Security → Microphone**.

| State | Meaning |
| --- | --- |
| `.idle` | Ready for an explicit start. |
| `.connecting` | Checking permission, negotiating the call or starting the audio devices. |
| `.listening` | The authenticated session, WebRTC connection, data channel, microphone and playout engine are active. |
| `.stopping` | Microphone capture has stopped and the transport is draining. |
| `.failed(let message)` | The call or its bound Chief execution failed. Present the reason. An explicit start makes a fresh attempt. |

`stop()` is valid during permission, negotiation or listening. Repeated starts during a call or its drain are idempotent. Releasing the session closes its devices. A disconnected call ends, and accepted Chief tasks continue under their own execution IDs. A new call starts with fresh speech ownership.

The active Chief configuration selects the target across all reading pages. The voice relay independently needs a discovered Codex installation, native ChatGPT authentication, V3 availability and provider network access. The calling bundle needs the signed microphone entitlement and purpose string. [Native relay and admission](../../../../internal/plugins/harness/codex/voice/README.md) · [Packaging](../../build/README.md#package-contents) · [Live verification](../../../../tools/e2e/README.md#global-voice)
