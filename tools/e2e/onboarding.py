"""Drive the first-run window through macOS Accessibility."""
import json
from pathlib import Path
import subprocess

from desktop import Desktop
from collection import activate
from lifecycle import Blocked
from operator_input import bundle
from report import check_handoff, handoff_intervals, save, sha256


DRIVER = Path(__file__).with_suffix(".swift")


def journey(session, app):
    output = session.output
    driver = session.root / "onboarding-ax"
    build = ["xcrun", "swiftc", "-warnings-as-errors", "-module-cache-path", str(session.root / "ax-cache"),
             str(DRIVER), "-o", str(driver)]
    with (output / "onboarding-driver-build.log").open("w") as log:
        subprocess.run(build, stdout=log, stderr=log, check=True, timeout=45)
    probe = subprocess.run([driver, "--probe"], capture_output=True, check=False, timeout=5)
    environment = json.loads(probe.stdout)
    save(output / "onboarding-environment.json", {**environment, "driverSHA256": sha256(driver),
         "sourceSHA256": sha256(DRIVER)})
    if probe.returncode != 0:
        raise Blocked("macOS Accessibility authorization missing for the onboarding AX driver")
    if environment["reduceMotion"]:
        raise Blocked("onboarding timing requires the normal animations (macOS Reduce Motion is on)")

    app = bundle(app, session, "onboarding-bundle.json")
    # Leave preferences and settings untouched before launch. A prepared Thread
    # or the Overview scenario flag would suppress the first-run window.
    preferences = session.profile / "desktop-preferences.json"
    assert not preferences.exists(), "onboarding requires previously unused desktop preferences"
    initial = session.runtime.state()
    assert not initial["applicationThreads"] and not any(
        thread.get("observation", {}).get("latestExecution") for thread in initial["threads"]
    ), "onboarding requires a fresh Runtime profile"
    session.app = session.spawn([app, "--runtime", session.binary, "--data-dir", session.profile,
                                 "--automation-socket", session.root / "ui.sock"], "app")
    activate(session)
    trace = output / "onboarding-ax.jsonl"
    with trace.open("wb") as stream:
        result = subprocess.run([driver, str(session.app.pid), app.parents[2], session.nonce],
                                stdout=stream, check=False, timeout=205)
    rows = [json.loads(line) for line in trace.read_text().splitlines()]
    confirmations = [r for r in rows if r["kind"] == "confirmation"]
    overruns = []
    late = {r["step"]: r["observedNS"] for r in rows if r["kind"] == "late-readiness"}
    for row in confirmations:
        elapsed = (late.get(row["step"], row["observedNS"]) - row["startNS"]) / 1_000_000
        message = f"{row['step']} → {row['destination']}: {elapsed:.6f} ms ({row['status']})"
        print(message, flush=True)
        if row["status"] != "passed":
            overruns.append(message)
    failures = [r["message"] for r in rows if r["kind"] == "failure"]
    if result.returncode == 2:
        raise Blocked("; ".join(failures))

    # Read the real saved values after the measured UI journey. Earlier reads
    # could change the work scheduled between a mode selection and confirmation.
    if len(confirmations) == 4 and confirmations[-1]["status"] != "input-failed":
        desktop = Desktop(session)
        try:
            phases = desktop.request()["onboarding"]["handoffUptimeNS"]
        finally:
            desktop.close()
        save(output / "onboarding-handoff.json", phases)
        final = confirmations[-1]
        if not failures:
            intervals = handoff_intervals(phases, final["startNS"], late.get("report", final["observedNS"]))
            for name, elapsed in intervals.items():
                print(f"{name}: {elapsed / 1_000_000:.3f} ms", flush=True)
            try:
                check_handoff(intervals)
            except AssertionError as error:
                failures.append(str(error))
        state = session.runtime.state()
        saved_roles = {p["id"]: {"mode": p["value"]["mode"], "enabled": p["value"].get("enabled", True)}
                       for p in state["settings"]["pluginSettings"] if p["id"] in ("tag.settings", "report.settings")}
        completed = json.loads(preferences.read_text()).get("onboardingCompleted") if preferences.exists() else None
        save(output / "onboarding-persisted.json", {"settingsRevision": state["settingsRevision"],
             "roles": saved_roles,
             "onboardingCompleted": completed})
        if (set(saved_roles) != {"tag.settings", "report.settings"}
                or any(role["mode"] != "override" or role["enabled"] is not True for role in saved_roles.values())
                or completed is not True):
            failures.append("both enabled, separate role configurations and completion must be saved")

    if overruns or failures:
        raise AssertionError("; ".join(overruns + failures))
    if result.returncode != 0 or len(confirmations) != 4:
        raise RuntimeError("onboarding AX driver did not record all four confirmations")
