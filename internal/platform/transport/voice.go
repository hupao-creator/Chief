package transport

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/platform/diagnostics"
)

// The HTTP request is the media lease. SDP and call control never enter the
// command journal. Losing either socket revokes only the owning call.
func (s *Server) voice(w http.ResponseWriter, r *http.Request, body []byte) {
	diagnostics.Event(r.Context(), "transport.voice", "received")
	var request struct {
		ClientID string `json:"clientId"`
		Offer    string `json:"offer"`
	}
	if err := model.Unmarshal(body, &request); err != nil || strings.TrimSpace(request.Offer) == "" || len(request.Offer) > 128000 {
		diagnostics.Event(r.Context(), "transport.voice", "invalid_offer")
		s.send(w, 400, resultFailure(errors.New("invalid global voice offer")))
		return
	}
	client := s.client(request.ClientID)
	if client == nil {
		diagnostics.Event(r.Context(), "transport.voice", "client_lease_missing")
		s.send(w, 409, resultFailure(errors.New("global voice requires the current client connection")))
		return
	}
	host, ok := s.host.(interface {
		RunGlobalVoice(context.Context, string, func(string) error) error
	})
	if !ok {
		s.send(w, 404, resultFailure(errors.New("global Voice Mode unavailable")))
		return
	}
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	release := context.AfterFunc(s.lifecycle, cancel)
	defer release()
	go func() {
		select {
		case <-client.done:
			cancel()
		case <-ctx.Done():
		}
	}()
	w.Header().Set("Content-Type", "application/x-ndjson")
	w.Header().Set("Cache-Control", "no-store")
	control := http.NewResponseController(w)
	emit := func(frame any) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := control.SetWriteDeadline(time.Now().Add(5 * time.Second)); err != nil {
			return err
		}
		if err := json.NewEncoder(w).Encode(frame); err != nil {
			return err
		}
		return control.Flush()
	}
	err := host.RunGlobalVoice(ctx, request.Offer, func(sdp string) error {
		diagnostics.Event(ctx, "transport.voice", "answer_ready")
		return emit(map[string]string{"answer": sdp})
	})
	diagnostics.End(ctx, "transport.voice", err)
	if err == nil {
		err = errors.New("global voice call ended")
	}
	_ = emit(resultFailure(err))
}
