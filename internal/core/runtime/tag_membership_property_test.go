package runtime

import (
	"context"
	"fmt"
	"path/filepath"
	"slices"
	"testing"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/core/store"
	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

// Pool maintenance must also preserve assignments saved before single-tag writes.
func TestRetainTagMembershipProperties(test *testing.T) {
	rapidcheck.Check(test, func(t *rapid.T) {
		db, err := store.Open(filepath.Join(test.TempDir(), "state.sqlite"))
		if err != nil {
			t.Fatal(err)
		}
		defer db.Close()
		const scope = "/project/Review"
		const folder = "Review"
		emoji := "📌"
		writer := tagsWriteCapability{scope: scope, runtime: &Runtime{config: Config{Store: db}}}
		count := rapid.IntRange(2, 4).Draw(t, "assignments")
		task := model.ThreadRecord{SessionRecord: model.SessionRecord{ID: "task", Cwd: scope}, TagEmojis: map[string]string{}}
		pool := []tagDefinition{}
		for i := range count {
			name := fmt.Sprintf("Topic %d", i)
			task.Tags = append(task.Tags, name)
			task.TagEmojis[name] = emoji
			pool = append(pool, tagDefinition{ID: name, Name: name, Emoji: emoji})
		}
		expected := slices.Clone(task.Tags)
		index := rapid.IntRange(0, count-1).Draw(t, "changed")
		op := plugin.SemanticTagOperation{Kind: rapid.SampledFrom([]string{"create", "update", "merge"}).Draw(t, "operation"), Emoji: &emoji}
		switch op.Kind {
		case "create":
			op.Name = folder
		case "update":
			op.Name, op.NewName = task.Tags[index], folder
			expected[index] = folder
		case "merge":
			op.Names, op.Target = []string{task.Tags[index]}, folder
			expected[index] = folder
		}
		_, err = db.Update(context.Background(), func(tx *store.Tx) error {
			if err := tx.Put(tagPoolKey(scope), pool); err != nil {
				return err
			}
			return tx.Put("thread:task", task)
		})
		if err == nil {
			_, err = db.Update(context.Background(), func(tx *store.Tx) error {
				_, err := writer.apply(tx, op)
				return err
			})
		}
		if err != nil {
			t.Fatal(err)
		}
		status, err := captureTagStatusbar(db.Snapshot(), scope)
		if err != nil {
			t.Fatal(err)
		}
		names := map[string]string{}
		for _, tag := range status.Tags {
			names[tag.ID] = tag.Name
		}
		var assigned []string
		for _, pair := range status.Assignments {
			assigned = append(assigned, names[pair.TagID])
		}
		slices.Sort(expected)
		slices.Sort(assigned)
		if !slices.ContainsFunc(status.Tags, func(tag plugin.TagStatusDefinition) bool { return tag.Name == folder }) || !slices.Equal(assigned, expected) {
			t.Fatalf("pool edit %s: expected folder tag and assignments %v, got %+v", op.Kind, expected, status)
		}
	})
}
