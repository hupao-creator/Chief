package moku

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
)

type failureTarget struct {
	ThreadID  string `json:"threadId"`
	FailureID string `json:"failureId"`
}

// Host selection can fail before Chief has a native execution to observe.
type hostUnavailable struct {
	error
	code string
}

func (e hostUnavailable) Unwrap() error { return e.error }

func failureCode(reason *string) string {
	if reason == nil {
		return "execution"
	}
	// Provider errors can contain URLs, paths and credentials. Only map recognized
	// diagnostics to authored explanations; never forward their remaining text.
	message := strings.ToLower(strings.TrimSpace(*reason))
	switch {
	case strings.HasPrefix(message, "codex 连接恢复失败"):
		return "connection"
	case strings.HasPrefix(message, "401 unauthorized"), strings.HasPrefix(message, "invalid api key"),
		strings.HasPrefix(message, "authentication failed"):
		return "authentication"
	case strings.HasPrefix(message, "429 too many requests"), strings.HasPrefix(message, "rate limit reached"):
		return "rate-limit"
	}
	return "execution"
}

func appendFailure(record *model.ThreadRecord, id, execution, source, code string) error {
	state := "unavailable"
	if source != "" {
		state = "ready"
	}
	row := map[string]any{"type": "chief-failure", "id": id, "executionId": execution, "sourceId": source,
		"failureCode": code, "resendState": state, "createdAt": max(time.Now().UnixMilli(), record.UpdatedAt)}
	raw, err := json.Marshal(row)
	if err == nil {
		record.Transcript = append(record.Transcript, raw)
	}
	return err
}

func (c *Coordinator) recordHostFailure(ctx context.Context, record model.ThreadRecord, request SubmitRequest, input model.AgentInput, code string) error {
	// No native send has retained the staged attachments for this user row yet.
	if c.config.RetainInput != nil {
		var err error
		input, err = c.config.RetainInput(ctx, record.ID, input)
		if err != nil {
			return err
		}
	}
	return c.config.UpdateThread(ctx, record.ID, func(current *model.ThreadRecord) error {
		if !current.Moku {
			return errors.New("Chief session changed")
		}
		id := model.FollowUpRowID(ctx)
		if id == "" {
			id = newID()
		}
		user := userMessage(input, id, max(time.Now().UnixMilli(), current.UpdatedAt))
		user["resendRequest"] = request
		raw, err := json.Marshal(user)
		if err != nil {
			return err
		}
		current.Transcript = append(current.Transcript, raw)
		return appendFailure(current, newID(), "", id, code)
	})
}

func readFailure(record model.ThreadRecord, target failureTarget) (SubmitRequest, error) {
	if record.ID != target.ThreadID || !record.Moku || live(record) {
		return SubmitRequest{}, errors.New("Chief session is busy or has changed")
	}
	source := ""
	for i := len(record.Transcript) - 1; i >= 0; i-- {
		var row struct {
			ID, Type, Role, SourceID, ResendState string
		}
		if err := json.Unmarshal(record.Transcript[i], &row); err != nil {
			return SubmitRequest{}, err
		}
		if row.ID == target.FailureID && row.Type == "chief-failure" && row.ResendState == "ready" {
			source = row.SourceID
		} else if source != "" && row.ID == source && row.Type == "message" && row.Role == "user" {
			var original struct{ ResendRequest *SubmitRequest }
			if err := json.Unmarshal(record.Transcript[i], &original); err != nil {
				return SubmitRequest{}, err
			}
			if original.ResendRequest != nil {
				return *original.ResendRequest, nil
			}
			break
		}
	}
	return SubmitRequest{}, errors.New("this Chief request is no longer available to resend")
}

func (c *Coordinator) setResendState(ctx context.Context, target failureTarget, from, to string) error {
	return c.config.UpdateThread(ctx, target.ThreadID, func(record *model.ThreadRecord) error {
		for i := len(record.Transcript) - 1; i >= 0; i-- {
			var row map[string]any
			if err := json.Unmarshal(record.Transcript[i], &row); err != nil {
				return err
			}
			if row["type"] == "chief-failure" && row["id"] == target.FailureID && row["resendState"] == from {
				row["resendState"] = to
				raw, err := json.Marshal(row)
				if err != nil {
					return err
				}
				record.Transcript[i] = raw
				return nil
			}
		}
		return errors.New("Chief resend was already handled")
	})
}

func (c *Coordinator) restoreFailure(ctx context.Context, record model.ThreadRecord) error {
	execution := record.Observation.LatestExecution
	if execution == nil || execution.Status != "failed" {
		return nil
	}
	for i := len(record.Transcript) - 1; i >= 0; i-- {
		var row struct{ Type, ExecutionID string }
		if err := json.Unmarshal(record.Transcript[i], &row); err != nil {
			return err
		}
		if row.Type == "chief-failure" && row.ExecutionID == execution.ExecutionID {
			return nil
		}
	}
	return c.settleExecution(ctx, record)
}
