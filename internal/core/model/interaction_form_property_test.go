package model

import (
	"encoding/json"
	"testing"

	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

// Hidden form fields are satisfied by their default or omitted. A hidden field
// without a default must never turn into an unanswerable required question.
func TestPublicFormPreflightProperties(test *testing.T) {
	rapidcheck.Check(test, func(t *rapid.T) {
		hiddenValue := rapid.Bool().Draw(t, "hidden")
		required := rapid.Bool().Draw(t, "required")
		withDefault := rapid.Bool().Draw(t, "withDefault")
		supplied := rapid.Bool().Draw(t, "supplied")
		answer := rapid.SampledFrom([]string{"answer", "answer-2"}).Draw(t, "answer")

		form := &PublicQuestionForm{Type: "string", Required: required}
		if hiddenValue {
			hidden := true
			form.Hidden = &hidden
		}
		defaultValue := ""
		if withDefault {
			defaultValue = "default"
			form.Default = json.RawMessage(`"default"`)
		}
		interaction := PublicInteraction{
			ID: "interaction", Kind: "form", Title: "Form",
			Questions: []PublicInteractionQuestion{{ID: "q", Prompt: "Question", Form: form}},
		}
		answers := map[string]json.RawMessage{}
		if supplied {
			encoded, err := json.Marshal(answer)
			if err != nil {
				t.Fatal(err)
			}
			answers["q"] = encoded
		}
		result := ValidatePublicInteractionAnswers(interaction, answers)

		expectedValid := !required || hiddenValue || supplied || withDefault
		if result.Valid != expectedValid {
			t.Fatalf("hidden=%v required=%v default=%q supplied=%v: valid=%v errors=%v", hiddenValue, required, defaultValue, supplied, result.Valid, result.Errors)
		}
		if hiddenValue {
			if _, ok := result.Answers["q"]; ok {
				t.Fatal("hidden answer left the process")
			}
			if len(result.ActiveQuestionIDs) != 0 {
				t.Fatalf("hidden question became active: %v", result.ActiveQuestionIDs)
			}
		} else if len(result.ActiveQuestionIDs) != 1 || result.ActiveQuestionIDs[0] != "q" {
			t.Fatalf("visible question not active: %v", result.ActiveQuestionIDs)
		}
		expectedValue := ""
		if withDefault && (hiddenValue || !supplied) {
			expectedValue = "default"
		} else if !hiddenValue && supplied {
			expectedValue = answer
		}
		if expectedValue == "" {
			if _, ok := result.ValidatedFormValues["q"]; ok {
				t.Fatal("field without an active value produced a validated value")
			}
		} else if got := result.ValidatedFormValues["q"]; got != expectedValue {
			t.Fatalf("unexpected handed-off value: got %v, want %q", got, expectedValue)
		}
	})
}
