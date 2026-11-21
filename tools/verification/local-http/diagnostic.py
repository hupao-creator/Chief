"""Generate a build-only Go overlay for timing global settings presentations."""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
revision, directory = sys.argv[1:]
out = Path(directory).resolve()
out.mkdir(parents=True, exist_ok=False)
overlay = {}


def source(name):
    path = Path("internal/core/runtime") / name
    overlay[str(ROOT / path)] = str(out / name)
    return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT, text=True)


def insert(text, anchor, addition):
    if text.count(anchor) != 1:
        raise ValueError(f"ambiguous or missing instrumentation site: {anchor}")
    return text.replace(anchor, anchor + addition)


config = insert(source("configuration.go"), '"path/filepath"', '\n "time"')
config = insert(config, 'type configurationContextKey struct{}', '''
type presentationClockKey struct{}
type presentationClock struct { gate time.Duration; acquisitions int }
''')
config = insert(config, 'func (r *Runtime) configurationLock(ctx context.Context) (func(), error) {', '''
    if clock, ok := ctx.Value(presentationClockKey{}).(*presentationClock); ok {
        at := time.Now()
        defer func() { clock.gate += time.Since(at); clock.acquisitions++ }()
    }''')
(out / "configuration.go").write_text(config)

settings = insert(source("settings.go"), '"sync"', '\n "time"')
settings = insert(settings, 'snapshotError := ""', '''
    started := time.Now()
    clock := new(presentationClock)
    ctx = context.WithValue(ctx, presentationClockKey{}, clock)
    var native time.Duration
    defer func() {
        println("presentation-ns", request.Scope, request.HarnessID,
            request.ExecutionOwner == "moku", time.Since(started).Nanoseconds(),
            clock.acquisitions, clock.gate.Nanoseconds(), native.Nanoseconds())
    }()''')
call = 'value, err := h.Settings().Presentation(ctx, plugin.SettingsPresentationRequest{Settings: harnessSettings, Cwd: cwd, ThreadSettings: threadSettings, Refresh: request.Refresh})'
settings = insert(settings, call, '\n    native = time.Since(nativeStart)').replace(call, 'nativeStart := time.Now()\n    ' + call)
(out / "settings.go").write_text(settings)
(out / "overlay.json").write_text(json.dumps({"Replace": overlay}))
