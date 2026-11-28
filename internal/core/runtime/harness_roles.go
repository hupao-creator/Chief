package runtime

import (
	"context"
	"encoding/json"
	"errors"
	"slices"

	"github.com/hupao-creator/Chief/internal/core/model"
	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/core/store"
)

func (r *Runtime) isBackgroundBinding(id string) bool {
	bindings, ok := r.config.Applications.(interface {
		BackgroundSettingsWorkspace(string) (string, string, bool)
	})
	if !ok {
		return false
	}
	_, _, found := bindings.BackgroundSettingsWorkspace(id)
	return found
}

func (r *Runtime) disallowsRole(id, role string) bool {
	h := r.config.Harnesses[id]
	return h != nil && !h.Descriptor().SupportsRole(role)
}

func (r *Runtime) pruneRoleProfiles(profiles map[string]json.RawMessage, role string) bool {
	before := len(profiles)
	for id := range profiles {
		if r.disallowsRole(id, role) {
			delete(profiles, id)
		}
	}
	return len(profiles) != before
}

// Only settings belonging to registered roles are reconciled. Ordinary Harness
// settings, Thread directories and previously admitted sessions have other owners.
func (r *Runtime) reconcileHarnessRoles(ctx context.Context) error {
	_, err := r.config.Store.Update(ctx, func(tx *store.Tx) error {
		var settings model.Settings
		if exists, err := tx.Get("settings", &settings); !exists || err != nil {
			return err
		}
		chief := &settings.Moku
		changed := r.pruneRoleProfiles(chief.ExecutionHarnesses, plugin.ChiefHostRole)
		if r.disallowsRole(chief.HostHarnessPreference, plugin.ChiefHostRole) {
			chief.HostHarnessPreference = "auto"
			changed = true
		}
		targetCount := len(chief.TargetHarnessIDs)
		chief.TargetHarnessIDs = slices.DeleteFunc(chief.TargetHarnessIDs, func(id string) bool {
			return r.disallowsRole(id, plugin.AgentThreadRole)
		})
		changed = changed || len(chief.TargetHarnessIDs) != targetCount
		for i, entry := range settings.PluginSettings {
			if !r.isBackgroundBinding(entry.ID) {
				continue
			}
			raw, err := r.repairBackgroundRole(entry, chief.HostHarnessPreference)
			if err != nil {
				return err
			}
			if raw != nil {
				settings.PluginSettings[i].Value = raw
				changed = true
			}
		}
		if !changed {
			return nil
		}
		var revision int64
		if _, err := tx.Get("settings-revision", &revision); err != nil {
			return err
		}
		if revision >= model.MaximumSafeInteger {
			return errors.New("settings revision exhausted")
		}
		if err := tx.Put("settings", settings); err != nil {
			return err
		}
		return tx.Put("settings-revision", revision+1)
	})
	return err
}

func (r *Runtime) repairBackgroundRole(entry model.PluginSettings, chief string) (json.RawMessage, error) {
	var value backgroundSettings
	if err := json.Unmarshal(entry.Value, &value); err != nil {
		return nil, err
	}
	profile := value.independentProfile()
	changed := false
	if profile != nil {
		changed = r.pruneRoleProfiles(profile.Harnesses, entry.ID)
		if r.disallowsRole(profile.HarnessPreference, entry.ID) {
			// Default to Use Chief and retain other independent model choices.
			value.Mode, profile.HarnessPreference = "inherit", chief
			if r.disallowsRole(chief, entry.ID) {
				profile.HarnessPreference = "auto"
			}
			if len(profile.Harnesses) == 0 {
				profile = nil
			}
			changed = true
		}
	}
	if value.Mode == "inherit" && (value.Enabled == nil || *value.Enabled) && r.disallowsRole(chief, entry.ID) {
		// A coordinator can opt out of this role. Use its retained independent
		// choice or the normal automatic resolution in the role's workspace.
		value.Mode = "override"
		if profile == nil {
			profile = &executionProfiles{HarnessPreference: "auto", Harnesses: map[string]json.RawMessage{}}
		}
		changed = true
	}
	if !changed {
		return nil, nil
	}
	fields := map[string]any{"mode": value.Mode}
	if value.Enabled != nil {
		fields["enabled"] = *value.Enabled
	}
	if value.Mode == "override" {
		fields["harnessPreference"], fields["harnesses"] = profile.HarnessPreference, profile.Harnesses
	} else if profile != nil {
		fields["independent"] = profile
	}
	return json.Marshal(fields)
}
