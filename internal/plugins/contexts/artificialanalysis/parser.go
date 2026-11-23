package artificialanalysis

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
)

var embeddedArray = regexp.MustCompile(`\\"([A-Za-z0-9_]+)\\":\[\{\\"`)

type embedded struct {
	key     string
	entries []any
}

func readEmbeddedJSON(raw string, start int) string {
	var decoded strings.Builder
	depth := 0
	inString, escaped := false, false
	for index := start; index < len(raw); index++ {
		character := raw[index]
		if character == '\\' && index+1 < len(raw) && (raw[index+1] == '"' || raw[index+1] == '\\') {
			index++
			character = raw[index]
		}
		decoded.WriteByte(character)
		if inString {
			if escaped {
				escaped = false
			} else if character == '\\' {
				escaped = true
			} else if character == '"' {
				inString = false
			}
			continue
		}
		switch character {
		case '"':
			inString = true
		case '{', '[':
			depth++
		case '}', ']':
			depth--
			if depth == 0 {
				return decoded.String()
			}
		}
	}
	return ""
}
func embeddedArrays(html string) []embedded {
	result := []embedded{}
	for _, match := range embeddedArray.FindAllStringSubmatchIndex(html, -1) {
		key := html[match[2]:match[3]]
		start := match[0] + strings.IndexByte(html[match[0]:match[1]], '[')
		data := readEmbeddedJSON(html, start)
		var entries []any
		if data != "" && json.Unmarshal([]byte(data), &entries) == nil {
			result = append(result, embedded{key, entries})
		}
	}
	return result
}

const indexName = "Artificial Analysis Intelligence Index v"
const versionNumber = `[0-9]{1,6}(?:\.[0-9]{1,6}){1,3}`

var exactVersion = regexp.MustCompile("^" + versionNumber + "$")

// The chart caption and Dataset description identify the metric being plotted.
// Require a complete version token so a prerelease cannot become a stable version.
var chartVersion = regexp.MustCompile(`>` + indexName + `([^ <]+)(?: incorporates |(?:<!-- -->)? includes:)`)
var datasets = regexp.MustCompile(`(?s)<script type="application/ld\+json">(.*?)</script>`)

func readIndexVersion(html string) IndexVersion {
	version := ""
	observe := func(candidate string) bool {
		if !exactVersion.MatchString(candidate) || (version != "" && version != candidate) {
			return false
		}
		version = candidate
		return true
	}
	for _, match := range chartVersion.FindAllStringSubmatch(html, -1) {
		if !observe(match[1]) {
			return ""
		}
	}
	for _, bounds := range datasets.FindAllStringSubmatchIndex(html, -1) {
		raw := html[bounds[2]:bounds[3]]
		if !strings.Contains(raw, indexName) {
			continue
		}
		var data struct {
			Type        string `json:"@type"`
			Description string `json:"description"`
		}
		if json.Unmarshal([]byte(raw), &data) != nil || data.Type != "Dataset" {
			continue
		}
		if label, ok := strings.CutPrefix(data.Description, indexName); ok {
			candidate, _, _ := strings.Cut(label, " ")
			if !observe(candidate) {
				return ""
			}
		}
	}
	const marker = `\"intelligenceIndex\":{`
	for {
		index := strings.Index(html, marker)
		if index < 0 {
			return IndexVersion(version)
		}
		start := index + len(marker) - 1
		var metadata map[string]any
		if json.Unmarshal([]byte(readEmbeddedJSON(html, start)), &metadata) != nil || metadata["slug"] != "artificial-analysis-intelligence-index" {
			return ""
		}
		name, ok := strings.CutPrefix(text(metadata["name"]), indexName)
		if !ok || !observe(name) {
			return ""
		}
		html = html[start+1:]
	}
}

func configurationIdentity(value any) *target {
	v := record(value)
	release := record(v["release"])
	slug := canonical(v["slug"], 512)
	reasoning, ok := v["isReasoning"].(bool)
	releaseSlug, releaseName := canonical(release["slug"], 512), canonical(release["name"], 512)
	if slug == "" || !ok || releaseSlug == "" || releaseName == "" {
		return nil
	}
	config := Configuration{Reasoning: reasoning}
	if reasoning && v["effort"] != nil {
		config.Effort = canonical(record(v["effort"])["slug"], 128)
		if config.Effort == "" {
			return nil
		}
	}
	return &target{Slug: slug, ReleaseSlug: releaseSlug, ReleaseName: releaseName, Configuration: &config}
}
func parseIndex(html string) []target {
	configurations := []target{}
	seen := map[string]bool{}
	releases := map[string]string{}
	roster := []any{}
	releasePages := map[string]bool{}
	pages := []target{}
	for _, array := range embeddedArrays(html) {
		for _, entry := range array.entries {
			identity := configurationIdentity(entry)
			if identity != nil && !seen[identity.Slug] {
				seen[identity.Slug] = true
				configurations = append(configurations, *identity)
			}
			v := record(entry)
			if v == nil {
				continue
			}
			if array.key == "releases" {
				slug, name := canonical(v["slug"], 512), canonical(v["name"], 512)
				if slug != "" && name != "" {
					releases[slug] = name
					if names, ok := v["modelNames"].([]any); ok && len(names) > 0 && !releasePages[slug] {
						releasePages[slug] = true
						pages = append(pages, target{Slug: slug, ReleaseSlug: slug, ReleaseName: name, ReleasePage: true})
					}
				}
			} else if array.key == "models" {
				roster = append(roster, entry)
			}
		}
	}
	for _, entry := range roster {
		v := record(entry)
		slug, releaseSlug := canonical(v["slug"], 512), canonical(v["releaseSlug"], 512)
		name := releases[releaseSlug]
		if slug != "" && releaseSlug != "" && name != "" && !seen[slug] {
			seen[slug] = true
			configurations = append(configurations, target{Slug: slug, ReleaseSlug: releaseSlug, ReleaseName: name})
		}
	}
	for _, entry := range configurations {
		if !releasePages[entry.ReleaseSlug] {
			pages = append(pages, entry)
		}
	}
	return pages
}
func parsePage(html string, requested target, observed, etag string) ([]persistedConfiguration, error) {
	version := readIndexVersion(html)
	rows := []persistedConfiguration{}
	seen := map[string]bool{}
	add := func(raw any) {
		id := configurationIdentity(raw)
		if id == nil || seen[id.Slug] || id.ReleaseSlug != requested.ReleaseSlug {
			return
		}
		if !requested.ReleasePage && (id.Slug != requested.Slug || (requested.Configuration != nil && *id.Configuration != *requested.Configuration)) {
			return
		}
		seen[id.Slug] = true
		facts := modelFacts(record(raw), id, version)
		rows = append(rows, persistedConfiguration{Slug: id.Slug, ReleaseSlug: id.ReleaseSlug, ReleaseName: id.ReleaseName, Configuration: *id.Configuration, ObservedAt: observed, ETag: etag, Facts: &facts})
	}
	const marker = `\"currentModel\":`
	if index := strings.Index(html, marker); index >= 0 {
		var model map[string]any
		if json.Unmarshal([]byte(readEmbeddedJSON(html, index+len(marker))), &model) == nil {
			add(model)
		}
	}
	if requested.ReleasePage || len(rows) == 0 {
		for _, array := range embeddedArrays(html) {
			if requested.ReleasePage && array.key != "initialModels" {
				continue
			}
			for _, entry := range array.entries {
				add(entry)
			}
		}
	}
	if len(rows) == 0 {
		return nil, fmt.Errorf("AA detail has no matching model configuration for %s", requested.Slug)
	}
	return rows, nil
}

func modelFacts(v map[string]any, identity *target, version IndexVersion) Facts {
	name := canonical(v["name"], 512)
	if name == "" {
		name = identity.Slug
	}
	deprecated, _ := v["deprecated"].(bool)
	return Facts{
		IntelligenceIndexVersion:              version,
		HeadlineOutputTokensPerSecond:         nonnegative(record(v["headline"])["outputSpeed"]),
		HeadlineTimeToFirstAnswerTokenSeconds: nonnegative(record(v["headline"])["timeToFirstAnswerToken"]),
		EvaluatedModel:                        name, Deprecated: deprecated,
		IntelligenceIndex:               nonnegative(v["intelligenceIndex"]),
		MedianOutputTokensPerSecond:     nonnegative(record(v["timescaleData"])["medianOutputSpeed"]),
		CostPerIntelligenceIndexTaskUSD: nonnegative(record(record(v["intelligenceIndexCostPerTask"])["cost"])["total"]),
		BenchmarkScores: BenchmarkScores{
			AABriefcaseV11:                  finite(record(record(v["briefcaseBreakdown"])["overall"])["elo"]),
			AutomationBenchAA:               proportion(v["automationBenchPartialScore"]),
			GDPPDF:                          proportion(v["gdpPdfAllPass"]),
			FrontierCodeV20:                 proportion(v["frontierCode20"]),
			TerminalBenchV40:                proportion(v["terminalBench40"]),
			OmniscienceV11Accuracy:          proportion(v["omniscienceAccuracy"]),
			OmniscienceV11HallucinationRate: proportion(v["omniscienceHallucinationRate"]),
			HLEDiamond:                      proportion(v["hleDiamond"]),
			CritPtV2Hard:                    proportion(v["critptAgenticHard"]),
			TerminalBenchScienceV01:         proportion(v["terminalBenchScience"]),
		},
		MedianTimeToFirstAnswerTokenSeconds: nonnegative(record(v["timeToFirstAnswerToken"])["total"]),
		InputUSDPer1MTokens:                 nonnegative(v["price1mInputTokens"]),
		OutputUSDPer1MTokens:                nonnegative(v["price1mOutputTokens"]),
	}
}
