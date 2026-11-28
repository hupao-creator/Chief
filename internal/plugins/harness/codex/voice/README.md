# Codex global voice relay

The macOS host holds one [GlobalVoiceSession](../../../../../app/macos/Sources/Voice/README.md) per workspace. The authenticated runtime grants one call per profile. Moku resolves the current Chief, pins its owner and supplies the relay with an SDP offer, an answer callback, destination admission and terminal failure notifications for admitted input. The selected Chief Harness owns work and tools. Codex supplies the voice connection even when another Harness runs Chief.

## Native session

Each call launches its own app-server through [Codex executable discovery and isolated native authentication](../README.md). The relay needs a ChatGPT account on the native OpenAI provider. It queries the V3 voice inventory and the account's model catalog. It prefers the advertised `gpt-6-luna` backing model and otherwise selects the explicitly advertised default. Thread admission confirms the exact model, native provider, read-only sandbox and disabled approvals. Tool surfaces are disabled. The relay uses a temporary workspace and private native history home, both released when the call ends.

The start request selects realtime V3, WebRTC, audio output and client-managed responses. Its product call ID and native realtime session ID have distinct lifetimes and meanings. Readiness requires matching session and version plus the SDP answer for this native thread. Account, unsupported-method, empty inventory, negotiation, model and process failures reach the caller. The media handshake checks availability for the current call.

## Handoff and destination failure

The sole input source is a committed V3 `thread/realtime/item/completed` whose timeline item has `type: transcriptSegment`, `role: user` and the confirmed realtime session ID. The native segment ID is the handoff ID to Chief. This ID travels unchanged into the destination receipt. Codex's discretionary background delegation uses a separate identifier and can be absent for a fully transcribed request. It has no execution authority in Chief.

The relay orders user segments by their first native event. If a later transcription completes first, it waits for earlier segments to complete or time out. An empty completion also releases its place in that order. The relay retains an identity digest until stop so repeated delivery cannot repeat work. Distinct segment IDs carrying identical words are independent inputs. Conflicting reuse, malformed completed input, queue overflow or uncertain admission end the call. Partial transcripts, assistant speech and backing-turn notifications cannot submit work.

The [destination admission](../../../../services/moku/README.md#global-voice) records the product call ID, native handoff ID and actual execution ID. The relay receives terminal failures for the current binding. A newer native user segment supersedes that handoff as soon as it starts. The native frontend can briefly acknowledge hearing speech. Chief’s committed Talk appears as text in the Chief conversation, and the relay has no access to its contents.

After 30 seconds without transcription progress on an unfinished user segment, the relay skips that segment and releases any completed inputs next in order. The call remains open. The relay remembers the skipped segment ID until hangup and ignores late events for it. The call bounds unfinished and queued admissions together to 32 and retains up to 1,024 distinct handoffs. Peer loss, a closed lease and runtime shutdown retire the call, release its process and revoke queued work. A user may explicitly start a fresh call. Already admitted business execution retains the ordinary Chief lifetime.

In the development bundle, `codex.voice_relay transcription_stalled` marks a sweep that skipped one or more stalled segments. `handoff_admission_failed` marks a failed submission to Chief while the call is active. `destination_failed` marks a terminal failure of the current admitted handoff. These events carry only the operation, phase and call trace. [Development diagnostics](../../../../platform/diagnostics/README.md)

[PBT domains](../../../../../tools/verification/pbt/README.md) · [Live synthetic speech replay](../../../../../tools/e2e/README.md#global-voice)
