"""Role admission and recovery checks for the disposable AGY replay."""
import copy
import json
import sqlite3

from adapter import wait_for


def check_role_admission(runtime):
    state = runtime.state()
    roles = {p["key"]: set(p.get("harnessRoles", [])) for p in state["plugins"]}
    assert roles["harness:agy"] == {"agent"}, roles
    for provider in ("pi", "claude", "codex", "opencode"):
        assert roles["harness:" + provider] == {"agent", "moku", "tag.settings", "report.settings"}, roles

    def reject(channel, request):
        try:
            runtime.invoke(channel, [request])
        except ValueError as error:
            if "agy" not in str(error) or "cannot participate" not in str(error):
                raise
        else:
            raise RuntimeError(f"{channel} accepted Antigravity for an internal role")

    for owner in ("moku", "tag.settings", "report.settings"):
        binding = {"executionOwner": owner} if owner == "moku" else {"applicationSettings": owner}
        reject("harness:settings-presentation", {"scope": "global", "harnessId": "agy", **binding})
        for retained in ([False] if owner == "moku" else [False, True]):
            draft = copy.deepcopy(state["settings"])
            if owner == "moku":
                draft["moku"]["hostHarnessPreference"] = "agy"
            else:
                entry = next(e for e in draft["pluginSettings"] if e["id"] == owner)
                profile = {"harnessPreference": "agy", "harnesses": {}}
                entry["value"] = ({"mode": "inherit", "independent": profile} if retained
                                  else {"mode": "override", **profile})
            reject("app:update-settings", {"settings": draft, "expectedSettingsRevision": state["settingsRevision"]})
    assert runtime.state()["settingsRevision"] == state["settingsRevision"]
    print("role declarations, execution catalogs and active/retained role write rejection passed", flush=True)


def seed_legacy_roles(profile):
    # Seed only the replay's stopped SQLite store. New clients cannot write these assignments.
    database = profile / "chief-go-state-v1/state.sqlite"
    with sqlite3.connect(database.as_uri() + "?mode=rw", uri=True) as db:
        settings = json.loads(db.execute("SELECT body FROM records WHERE key='settings'").fetchone()[0])
        saved = copy.deepcopy(settings)
        settings["harnesses"]["agy"]["authMethod"] = "oauth-business"
        settings["moku"]["hostHarnessPreference"] = "agy"
        settings["moku"]["executionHarnesses"]["agy"] = {}
        codex = settings["moku"]["executionHarnesses"]["codex"]
        for entry in settings["pluginSettings"]:
            profile_value = {"harnessPreference": "agy", "harnesses": {"agy": {}, "codex": codex}}
            if entry["id"] == "tag.settings":
                entry["value"] = {"mode": "override", "enabled": False, **profile_value}
            elif entry["id"] == "report.settings":
                entry["value"] = {"mode": "inherit", "enabled": False, "independent": profile_value}
        db.execute("UPDATE records SET body=? WHERE key='settings'", (json.dumps(settings).encode(),))
    return saved


def check_repaired_roles(runtime, saved):
    # Startup pins the automatic preference in a separate settings revision.
    state = wait_for(runtime.state, lambda s: s["settings"]["moku"]["hostHarnessPreference"] == "codex", 30)
    settings = state["settings"]
    expected = copy.deepcopy(saved)
    for entry in expected["pluginSettings"]:
        if entry["id"] in ("tag.settings", "report.settings"):
            entry["value"] = {"mode": "inherit", "enabled": False, "independent": {
                "harnessPreference": "auto", "harnesses": {"codex": saved["moku"]["executionHarnesses"]["codex"]}}}
    assert settings == expected, "recovery changed unrelated settings or lost a retained model"
    result = runtime.invoke("app:update-settings", [{"settings": settings, "expectedSettingsRevision": state["settingsRevision"]}])
    assert result["status"] == "saved" and result["settingsRevision"] == state["settingsRevision"], result["status"]
    print("legacy Chief, independent Tag and retained Super Thread settings reopened and saved", flush=True)
