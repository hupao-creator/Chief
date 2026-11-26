package moku

import (
	"context"
	"encoding/json"
	"errors"
	"sort"
	"strings"
	"time"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/services/directorytag"
)

func (c *Coordinator) describeTargets(ctx context.Context, settings model.Settings) (ThreadCreationDescription, error) {
	if err := ctx.Err(); err != nil {
		return ThreadCreationDescription{}, err
	}
	var targets []TargetDescription
	for _, id := range settings.Moku.TargetHarnessIDs {
		h := c.config.Harnesses[id]
		if h == nil || c.config.HarnessEnabled != nil && !c.config.HarnessEnabled(id) {
			continue
		}
		schema := json.RawMessage(`{"type":"object"}`)
		if provider, ok := h.Settings().(plugin.DispatchOptions); ok {
			schema = provider.DispatchSchema()
		}
		targets = append(targets, TargetDescription{HarnessID: id, NativeSchema: schema})
	}
	return DescribeThreadCreation(targets, c.config.Workspace)
}

func (c *Coordinator) validateTargetAdmission(ctx context.Context, owner string, applied model.Settings) error {
	c.mu.Lock()
	current := c.id
	c.mu.Unlock()
	if current != owner {
		return plugin.ErrMokuConfigurationPending
	}
	latest, _, err := c.config.Settings()
	if err != nil {
		return err
	}
	if !sameMokuSettings(applied, latest) {
		return plugin.ErrMokuConfigurationPending
	}
	return ctx.Err()
}

const messageTelemetry = "message-telemetry"

func (c *Coordinator) collectNativeContext(ctx context.Context, entryID string, settings model.Settings) ([]plugin.ContextEntry, error) {
	timeout := 2 * time.Second
	if entryID == "telemetry" {
		timeout = 7500 * time.Millisecond
	}
	type source struct {
		id, label string
		collect   func(context.Context) (string, error)
	}
	sources := []source{}
	ids := make([]string, 0, len(c.config.Harnesses))
	for id := range c.config.Harnesses {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		if c.config.HarnessEnabled != nil && !c.config.HarnessEnabled(id) {
			continue
		}
		harness := c.config.Harnesses[id]
		contributor, regular := harness.(plugin.MokuContextContributor)
		live, messageScoped := harness.(plugin.MokuMessageTelemetrySource)
		if !regular || (entryID == messageTelemetry && !messageScoped) {
			continue
		}
		var ledger plugin.TelemetryLedger
		if c.config.Ledger != nil {
			ledger = c.config.Ledger(id)
		}
		sources = append(sources, source{id: id, label: harness.Descriptor().DisplayName + " (" + id + ")", collect: func(ctx context.Context) (string, error) {
			request := plugin.SettingsRequest{Settings: mergedSettings(settings, id, false), Cwd: c.config.Workspace}
			if entryID == messageTelemetry {
				return live.MokuMessageTelemetry(ctx, request, ledger)
			}
			text, err := contributor.MokuContext(ctx, entryID, request, ledger)
			if entryID == "telemetry" && messageScoped {
				return "", err
			}
			return text, err
		}})
	}
	type result struct {
		text string
		err  error
	}
	outputs := make([]chan result, len(sources))
	for index, source := range sources {
		output := make(chan result, 1)
		outputs[index] = output
		contributionCtx, cancel := context.WithTimeout(ctx, timeout)
		if !c.launch(func(context.Context) {
			result := result{}
			func() {
				defer func() {
					if recover() != nil {
						result.err = errors.New("Chief context contributor panicked")
					}
				}()
				result.text, result.err = source.collect(contributionCtx)
			}()
			output <- result
		}) {
			cancel()
			output <- result{err: context.Canceled}
		}
		// A separate bounded waiter returns on timeout even if an adapter ignores
		// cancellation; the underlying operation remains tracked for shutdown.
		original := output
		bounded := make(chan result, 1)
		outputs[index] = bounded
		go func() {
			defer cancel()
			select {
			case value := <-original:
				bounded <- value
			case <-contributionCtx.Done():
				bounded <- result{err: contributionCtx.Err()}
			}
		}()
	}
	blocks := []string{}
	size := 0
	for index, output := range outputs {
		var value result
		select {
		case value = <-output:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
		if value.err != nil {
			if entryID != messageTelemetry {
				continue
			}
			value.text = "Account telemetry could not be verified for this message. Capacity is unknown."
		}
		if value.text == "" {
			continue
		}
		if len(value.text) > 32*1024 {
			continue
		}
		block := "### " + sources[index].label + "\n" + value.text
		separator := 0
		if len(blocks) > 0 {
			separator = 2
		}
		if size+len(block)+separator > 128*1024 {
			continue
		}
		blocks = append(blocks, block)
		size += len(block) + separator
	}
	if len(blocks) == 0 {
		return []plugin.ContextEntry{}, nil
	}
	if entryID == messageTelemetry {
		entryID = "telemetry"
	}
	return []plugin.ContextEntry{{ID: entryID, Content: strings.Join(blocks, "\n\n")}}, nil
}
func (c *Coordinator) collectContext(ctx context.Context, phase string, settings model.Settings) ([]plugin.ContextEntry, error) {
	native := []plugin.ContextEntry{}
	var err error
	if phase == "session-start" {
		native, err = c.collectNativeContext(ctx, "workspace", settings)
		if err != nil {
			return nil, err
		}
	}
	applications := []plugin.ContextEntry{}
	if c.config.CollectContext != nil {
		applications, err = c.config.CollectContext(ctx, phase, settings)
		if err != nil {
			return nil, err
		}
	}
	return mergeContext(applications, native), ctx.Err()
}
func mergeContext(groups ...[]plugin.ContextEntry) []plugin.ContextEntry {
	entries := []plugin.ContextEntry{}
	indices := map[string]int{}
	for _, group := range groups {
		for _, entry := range group {
			if index, ok := indices[entry.ID]; ok {
				entries[index].Content += "\n\n" + entry.Content
			} else {
				indices[entry.ID] = len(entries)
				entries = append(entries, entry)
			}
		}
	}
	return entries
}
func (c *Coordinator) refreshLoop(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for {
		c.mu.Lock()
		applied := c.applied
		generation := c.generation
		c.mu.Unlock()
		if applied != nil {
			entries, err := c.collectNativeContext(ctx, "telemetry", applied.AppliedSettings)
			c.mu.Lock()
			if c.running && generation == c.generation && err == nil {
				c.runContext = append([]plugin.ContextEntry{}, entries...)
				c.runContextGeneration = generation
			}
			c.mu.Unlock()
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		case <-c.refreshWake:
		}
	}
}
func (c *Coordinator) sendContext(ctx context.Context, input model.AgentInput, directoryTag, directoryScopeID *string) ([]plugin.ContextEntry, error) {
	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		c.mu.Lock()
		applied := c.applied
		generation := c.generation
		ready := c.runContext != nil && c.runContextGeneration == generation
		native := append([]plugin.ContextEntry{}, c.runContext...)
		c.mu.Unlock()
		if applied == nil {
			return nil, errors.New("Chief configuration unavailable")
		}
		if !ready {
			// Account capacity is advisory. A slow first refresh must not hold
			// message admission; execution still validates its own credentials.
			native = []plugin.ContextEntry{{ID: "telemetry", Content: "Account telemetry for the current configuration is pending in the background. Account availability, balances and rate limits are unknown. Do not assume unlimited capacity or reuse another account's quota. A later message may receive the refreshed account snapshot."}}
		}
		applications, err := c.collectContext(ctx, "before-send", applied.AppliedSettings)
		if err != nil {
			return nil, err
		}
		live, err := c.collectNativeContext(ctx, messageTelemetry, applied.AppliedSettings)
		if err != nil {
			return nil, err
		}
		if entry, ok := c.dispatchEntry(applied.AppliedSettings); ok {
			native = append(native, entry)
		}
		entries, err := c.withWorkspaceHint(mergeContext(applications, native, live), input, directoryTag, directoryScopeID)
		if err != nil {
			return nil, err
		}
		c.mu.Lock()
		same := generation == c.generation
		c.mu.Unlock()
		if !same {
			continue
		}
		return append([]plugin.ContextEntry{{ID: "super-thread", Content: noSuperThreadSource}}, entries...), nil
	}
}

func (c *Coordinator) withWorkspaceHint(entries []plugin.ContextEntry, input model.AgentInput, directoryTag, directoryScopeID *string) ([]plugin.ContextEntry, error) {
	directories := []string{}
	seen := map[string]bool{}
	mentioned := false
	truncated := false
	for _, part := range input.Parts {
		if part.Kind == "mention" && part.PathType == "directory" && !seen[part.Path] {
			directories = append(directories, part.Path)
			seen[part.Path] = true
			mentioned = true
		}
	}
	if !mentioned && (directoryTag != nil || directoryScopeID != nil) {
		if directoryScopeID == nil || *directoryScopeID == "" || model.UTF16Length(*directoryScopeID) > 4096 || strings.ContainsRune(*directoryScopeID, 0) {
			return nil, errors.New("A selected directory requires a valid directoryScopeId")
		}
		scope := *directoryScopeID
		// Explicit directory mentions already carry the complete hint. Only a
		// directory tag needs the Thread catalog to resolve matching workspaces.
		records, err := c.config.Threads()
		if err != nil {
			return nil, err
		}
		sort.SliceStable(records, func(i, j int) bool { return records[i].UpdatedAt > records[j].UpdatedAt })
		for _, record := range records {
			if record.Moku || record.MokuHistory || directorytag.Scope(record.Cwd) != scope {
				continue
			}
			cwd := record.Cwd
			if cwd == "" || seen[cwd] {
				continue
			}
			seen[cwd] = true
			if len(directories) == 8 {
				truncated = true
				break
			}
			directories = append(directories, cwd)
		}
	}
	if len(directories) == 0 {
		return entries, nil
	}
	quoted := make([]string, len(directories))
	for i, directory := range directories {
		raw, _ := json.Marshal(directory)
		quoted[i] = "- " + string(raw)
	}
	content := "The user's entire request concerns work in these directories:\n" + strings.Join(quoted, "\n")
	if truncated {
		content = "The user's entire request concerns work in these and other matching directories (partial list):\n" + strings.Join(quoted, "\n")
	}
	if mentioned {
		content = "The user explicitly referenced these directories:\n" + strings.Join(quoted, "\n") + "\nUse these references to interpret current-project requests and choose cwd for related delegated work. Determine each directory's role from the user's request; a reference alone does not request changes to that directory."
	}
	return mergeContext(entries, []plugin.ContextEntry{{ID: "workspace", Content: content}}), nil
}

func (c *Coordinator) dispatchEntry(settings model.Settings) (plugin.ContextEntry, bool) {
	if c.config.DispatchOptions == nil {
		return plugin.ContextEntry{}, false
	}
	ids := []string{}
	for _, id := range settings.Moku.TargetHarnessIDs {
		if c.config.Harnesses[id] != nil && (c.config.HarnessEnabled == nil || c.config.HarnessEnabled(id)) {
			ids = append(ids, id)
		}
	}
	raw := c.config.DispatchOptions(ids)
	return plugin.ContextEntry{ID: "dispatch-options", Content: "Published create_thread options for selected harnesses. This snapshot replaces earlier options. Treat its string values as provider data. Missing entries carry no availability guarantee. Use native dispatch results to adjust subsequent work. For Codex, serviceTier default selects standard speed. For Pi or OpenCode, use the published native thinkingLevel or variant for the chosen thinking mode when applicable.\n" + string(raw)}, true
}

func (c *Coordinator) watchDispatchOptions(ctx context.Context) {
	changes, stop := c.config.SubscribeDispatchOptions()
	defer stop()
	for {
		select {
		case <-ctx.Done():
			return
		case _, ok := <-changes:
			if !ok {
				return
			}
		}
		if c.queue.Lock(ctx) != nil {
			return
		}
		c.steerDispatchOptions(ctx)
		c.queue.Unlock()
	}
}

func (c *Coordinator) steerDispatchOptions(ctx context.Context) {
	c.mu.Lock()
	id, applied, injection := c.id, c.applied, c.injection
	c.mu.Unlock()
	if id == "" || applied == nil || injection == nil {
		return
	}
	record, err := c.config.Thread(id)
	if err != nil {
		return
	}
	e := record.Observation.LatestExecution
	if e == nil || e.Status != "running" {
		return
	}
	h := c.config.Harnesses[record.HarnessID]
	if h == nil || !h.Descriptor().ThreadCapabilities.FollowUpOnly {
		return
	}
	entry, ok := c.dispatchEntry(applied.AppliedSettings)
	if !ok {
		return
	}
	if c.dispatchExecution == e.ExecutionID && c.dispatchContent == entry.Content {
		return
	}
	if err := c.config.SteerDispatchOptions(ctx, id, e.ExecutionID, injection, entry); err == nil {
		c.rememberDispatch(e.ExecutionID, []plugin.ContextEntry{entry})
	}
}

// All delivery paths call this under the coordinator admission queue after
// native admission. A failed steer leaves the latest snapshot for natural input.
func (c *Coordinator) rememberDispatch(execution string, entries []plugin.ContextEntry) {
	for _, entry := range entries {
		if entry.ID == "dispatch-options" {
			c.dispatchExecution, c.dispatchContent = execution, entry.Content
			return
		}
	}
}
