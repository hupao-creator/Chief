package runtime

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strconv"
	"strings"

	"github.com/hupao-creator/Chief/internal/core/model"
)

type conversationMessage struct {
	ID          string   `json:"id"`
	Role        string   `json:"role"`
	CreatedAt   int64    `json:"createdAt"`
	Text        string   `json:"text"`
	Attachments []string `json:"attachments,omitempty"`
}

// Only the coordinator's user-admission and completed Talk records are public
// dialogue. In particular, a Harness user turn may contain injected context.
func dialogueMessage(owner string, raw json.RawMessage) (conversationMessage, bool) {
	var row struct {
		ID, Type, Role, Status, Content, Name, ExecutionID, Presentation string
		SystemEvent, IsError                                             bool
		CreatedAt, CompletedAt                                           int64
		Arguments                                                        struct{ Text string }
		Result                                                           struct{ OK bool }
		Attachments                                                      []struct{ Name string }
	}
	if json.Unmarshal(raw, &row) != nil || row.ID == "" || row.CreatedAt <= 0 || row.SystemEvent ||
		(row.Presentation != "" && row.Presentation != "visible") {
		return conversationMessage{}, false
	}
	m := conversationMessage{ID: owner + "/" + row.ID, CreatedAt: row.CreatedAt}
	switch {
	case row.Type == "message" && row.Role == "user" && row.Status == "complete":
		m.Role, m.Text = "user", row.Content
		for _, file := range row.Attachments {
			if file.Name != "" {
				m.Attachments = append(m.Attachments, file.Name)
			}
		}
		return m, strings.TrimSpace(m.Text) != "" || len(m.Attachments) > 0
	case row.Type == "tool-operation" && row.Name == "talk" && row.ExecutionID != "" &&
		row.CompletedAt > 0 && !row.IsError && row.Result.OK && strings.TrimSpace(row.Arguments.Text) != "":
		m.Role, m.Text = "chief", row.Arguments.Text
		return m, true
	}
	return conversationMessage{}, false
}

type conversationSource struct {
	thread model.ThreadRecord
	index  int
	row    conversationMessage
}

// Audit creation times never decrease within a coordinator transcript. Merge
// the newest end of each session, breaking ties by persisted session and row
// order. A cursor denotes an immutable row, so new arrivals do not shift pages.
func mokuConversationPage(ctx context.Context, threads []model.ThreadRecord, before string) (json.RawMessage, error) {
	sources := []conversationSource{}
	for _, t := range threads { // Newer sessions are prepended to the store's thread order.
		if t.Moku || t.MokuHistory {
			sources = append(sources, conversationSource{thread: t, index: len(t.Transcript)})
		}
	}
	var boundary int64
	boundarySource := -1
	if before != "" {
		owner, rawIndex, _ := strings.Cut(before, "/")
		index, err := strconv.Atoi(rawIndex)
		for i, s := range sources {
			if s.thread.ID == owner && err == nil && index >= 0 && index < len(s.thread.Transcript) {
				if row, ok := dialogueMessage(owner, s.thread.Transcript[index]); ok {
					boundary, boundarySource, sources[i].index = row.CreatedAt, i, index
				}
				break
			}
		}
		if boundarySource < 0 {
			return nil, errors.New("unknown Chief conversation cursor")
		}
	}
	advance := func(i int) {
		s := &sources[i]
		for s.index--; s.index >= 0 && ctx.Err() == nil; s.index-- {
			row, ok := dialogueMessage(s.thread.ID, s.thread.Transcript[s.index])
			if ok && (boundary == 0 || row.CreatedAt < boundary || row.CreatedAt == boundary && i >= boundarySource) {
				s.row = row
				return
			}
		}
	}
	for i := range sources {
		advance(i)
	}
	page := struct {
		CommandRowIDs bool                  `json:"commandRowIds"`
		Messages      []conversationMessage `json:"messages"`
		Before        string                `json:"before,omitempty"`
	}{CommandRowIDs: true, Messages: []conversationMessage{}}
	size, cursor := 0, ""
	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		newest := -1
		for i, s := range sources {
			if s.index >= 0 && (newest < 0 || s.row.CreatedAt > sources[newest].row.CreatedAt) {
				newest = i
			}
		}
		if newest < 0 {
			break
		}
		s := &sources[newest]
		// Each audit record already contains its escaped text and file names.
		// Allow a large individual user message to occupy a page by itself.
		cost := len(s.thread.Transcript[s.index])
		if len(page.Messages) >= 64 || len(page.Messages) > 0 && size+cost > 1024*1024 {
			page.Before = cursor
			break
		}
		size += cost
		page.Messages = append(page.Messages, s.row)
		cursor = s.thread.ID + "/" + strconv.Itoa(s.index)
		advance(newest)
	}
	slices.Reverse(page.Messages)
	return json.Marshal(page)
}
