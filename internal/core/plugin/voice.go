package plugin

import "context"

// GlobalVoice is a call-scoped media relay. Submit returns only after the
// selected Chief accepts the input or reports its failure. Releasing the call
// revokes pending input and speech, while admitted work keeps its own lifetime.
type GlobalVoice struct {
	ID      string
	Offer   string
	Answer  func(string) error
	Submit  func(ctx context.Context, handoffID, text string) error
	Replies <-chan VoiceReply
}

type VoiceReply struct {
	Context   context.Context
	HandoffID string
	Text      string
	Failure   error
}
