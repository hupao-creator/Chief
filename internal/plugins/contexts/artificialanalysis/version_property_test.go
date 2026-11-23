package artificialanalysis

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/hupao-creator/Chief/tools/verification/pbt/rapidcheck"
	"pgregory.net/rapid"
)

type pageResponses map[string]string

func (pages pageResponses) Do(req *http.Request) (*http.Response, error) {
	body, ok := pages[req.URL.String()]
	if !ok {
		return nil, fmt.Errorf("unexpected URL %s", req.URL)
	}
	status := http.StatusOK
	if body == "304" {
		if req.Header.Get("If-None-Match") != `"original"` {
			return nil, fmt.Errorf("missing detail ETag")
		}
		status = http.StatusNotModified
	}
	return &http.Response{StatusCode: status, Header: http.Header{"Etag": {`"original"`}}, Body: io.NopCloser(strings.NewReader(body))}, nil
}

func chartDeclaration(version string) string {
	return "<span>Artificial Analysis Intelligence Index v" + version + " incorporates 9 evaluations</span>"
}

func TestEvaluationVersionProperties(t *testing.T) {
	rapidcheck.Check(t, func(rt *rapid.T) {
		check := func(err error) {
			rt.Helper()
			if err != nil {
				rt.Fatal(err)
			}
		}
		versions := []string{"", "5.0", "5.0.1", "6.2.3"}
		rosterVersion := rapid.SampledFrom(versions).Draw(rt, "roster")
		index := `\"releases\":[{\"slug\":\"alpha\",\"name\":\"Alpha\",\"modelNames\":[\"Alpha\"]}],\"models\":[{\"slug\":\"beta\",\"isReasoning\":true,\"effort\":{\"slug\":\"max\"},\"release\":{\"slug\":\"beta\",\"name\":\"beta\"}}]`
		pages := pageResponses{indexURL: chartDeclaration(rosterVersion) + index}
		expectedVersions := map[string]string{}
		selectors := []AcquisitionIdentity{}
		for _, slug := range []string{"alpha", "beta"} {
			version := rapid.SampledFrom(versions).Draw(rt, slug+"-version")
			caption := chartDeclaration(version)
			if rapid.Bool().Draw(rt, slug+"-conflict") && version != "" {
				caption += chartDeclaration("7.8")
				version = ""
			}
			expectedVersions[slug] = version
			// The comparison page includes a foreign row; legacy fields and TTFT
			// deliberately carry plausible numbers distinct from the required metrics.
			model := fmt.Sprintf(`{"slug":"%s","isReasoning":true,"effort":{"slug":"max"},"release":{"slug":"%s","name":"%s"},"intelligenceIndex":0,"terminalBench21":0.7,"gdpPdfAllPass":1.2,"omniscienceHallucinationRate":0,"headline":{"outputSpeed":17,"timeToFirstToken":1,"timeToFirstAnswerToken":3}}`, slug, slug, slug)
			pages[indexURL+slug] = caption + strings.ReplaceAll(`"initialModels":[{"slug":"other","isReasoning":false,"release":{"slug":"other","name":"Other"}},`+model+"]", `"`, `\"`)
			selectors = append(selectors, AcquisitionIdentity{Names: []string{slug}})
		}
		options := Options{CacheRoot: t.TempDir(), HTTPClient: pages}
		source, err := NewSource(options)
		check(err)
		defer source.Close()
		check(source.Refresh(context.Background(), selectors))
		snap := source.Snapshot()
		if len(snap.Releases) != 2 {
			rt.Fatalf("unexpected releases: %+v", snap)
		}
		common := expectedVersions["alpha"]
		if common != expectedVersions["beta"] {
			common = ""
		}
		if string(snap.IntelligenceIndexVersion) != common {
			rt.Fatalf("snapshot version %q, want %q", snap.IntelligenceIndexVersion, common)
		}
		models := []NativeModel{}
		for i, r := range snap.Releases {
			if len(r.Evaluations) != 1 {
				rt.Fatal(r)
			}
			e := r.Evaluations[0]
			if e.Slug != r.Slug || e.Configuration.Effort != "max" || string(e.IntelligenceIndexVersion) != expectedVersions[r.Slug] {
				rt.Fatalf("wrong configuration or version: %+v", e)
			}
			if e.IntelligenceIndex == nil || *e.IntelligenceIndex != 0 || e.BenchmarkScores.OmniscienceV11HallucinationRate == nil || *e.BenchmarkScores.OmniscienceV11HallucinationRate != 0 {
				rt.Fatal("measured zero lost")
			}
			if e.HeadlineOutputTokensPerSecond == nil || *e.HeadlineOutputTokensPerSecond != 17 || e.HeadlineTimeToFirstAnswerTokenSeconds == nil || *e.HeadlineTimeToFirstAnswerTokenSeconds != 3 {
				rt.Fatal("wrong headline metric")
			}
			if e.MedianOutputTokensPerSecond != nil || e.MedianTimeToFirstAnswerTokenSeconds != nil || e.BenchmarkScores.GDPPDF != nil || e.BenchmarkScores.TerminalBenchV40 != nil {
				rt.Fatal("accepted missing or invalid measurement")
			}
			models = append(models, NativeModel{Label: r.Slug, Identity: Identity{Selector: r.Slug}})
			for range 45 {
				snap.Releases[i].Evaluations = append(snap.Releases[i].Evaluations, e)
			}
		}
		compact := FormatModels(snap, models)
		if !strings.Contains(compact, "compact JSON rows") {
			rt.Fatal("compact path not exercised")
		}
		for slug, version := range expectedVersions {
			label := "unknown"
			if version != "" {
				label = "v" + version
			}
			if !strings.Contains(compact, fmt.Sprintf(`["%s",true,"max","%s",false,"%s",0,`, slug, slug, label)) {
				rt.Fatal("compact version missing for ", slug)
			}
		}
		pages[indexURL+"beta"] = "304"
		check(source.Refresh(context.Background(), selectors[1:]))
		beta := source.Snapshot().Releases[1].Evaluations[0]
		if string(beta.IntelligenceIndexVersion) != expectedVersions["beta"] || beta.IntelligenceIndex == nil {
			rt.Fatal("304 changed the original observation")
		}
		// A release sample can omit an earlier configuration after regrading.
		// The original row keeps its label when only the new effort is observed.
		oldAlpha := source.Snapshot().Releases[0].Evaluations[0]
		other := `\"initialModels\":[{\"slug\":\"alpha-low\",\"release\":{\"slug\":\"alpha\",\"name\":\"Alpha\"},\"isReasoning\":true,\"effort\":{\"slug\":\"low\"},\"intelligenceIndex\":12}]`
		pages[indexURL+"alpha"] = chartDeclaration("8.0") + other
		check(source.Refresh(context.Background(), selectors[:1]))
		updated := source.Snapshot()
		rows := updated.Releases[0].Evaluations
		if len(rows) != 2 || !reflect.DeepEqual(oldAlpha, rows[0]) || rows[1].IntelligenceIndexVersion != "8.0" || updated.IntelligenceIndexVersion != "" {
			rt.Fatal("partial release sample relabeled or lost prior facts")
		}
		reopened, err := NewSource(options)
		check(err)
		defer reopened.Close()
		if !reflect.DeepEqual(reopened.Snapshot(), source.Snapshot()) {
			rt.Fatal("cache changed the observation")
		}
		// A schema-2 cohort without row labels can attest only its own recorded
		// version. Removing that label must preserve unknown, even with a live roster.
		path := filepath.Join(options.CacheRoot, "moku-evaluation-facts.json")
		raw, err := os.ReadFile(path)
		check(err)
		var envelope map[string]any
		check(json.Unmarshal(raw, &envelope))
		delete(envelope, "rosterIndexVersion")
		historical := rapid.SampledFrom(versions[:3]).Draw(rt, "historical")
		if historical == "" {
			if rapid.Bool().Draw(rt, "malformed-historical-label") {
				envelope["intelligenceIndexVersion"] = map[string]any{"unrelated": 5}
			} else {
				delete(envelope, "intelligenceIndexVersion")
			}
		} else {
			envelope["intelligenceIndexVersion"] = historical
		}
		for _, v := range envelope["configurations"].([]any) {
			facts := record(record(v)["facts"])
			delete(facts, "intelligenceIndexVersion")
			delete(facts, "headlineOutputTokensPerSecond")
			delete(facts, "headlineTimeToFirstAnswerTokenSeconds")
		}
		data, err := json.Marshal(envelope)
		check(err)
		old, err := parsePersisted(data)
		check(err)
		for _, row := range old.Configurations {
			if string(row.Facts.IntelligenceIndexVersion) != historical {
				rt.Fatal("historical version changed")
			}
		}
		envelope["source"] = "another-evaluator"
		data, err = json.Marshal(envelope)
		check(err)
		if _, err = parsePersisted(data); err == nil {
			rt.Fatal("accepted another source")
		}
	})
}
