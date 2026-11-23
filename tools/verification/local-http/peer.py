"""Only the two native Claude control replies used by settings discovery."""
import json
import os
import sys
import time
from pathlib import Path

root = Path(os.environ["HOME"])
for line in sys.stdin:
    message = json.loads(line)
    kind = message["request"]["subtype"]
    with (root / "calls").open("a") as calls:
        print(kind, time.monotonic_ns(), file=calls)
    if kind == "initialize":
        if (root / "hold-init").exists():
            (root / "probing").write_text(str(os.getpid()))
            deadline = time.monotonic() + 10
            while (root / "hold-init").exists() and time.monotonic() < deadline:
                time.sleep(.005)
        value = {"models": [{"value": "fixture-model", "supportsEffort": False}]}
    elif kind == "get_settings":
        time.sleep(float(os.environ.get("CHIEF_ONBOARDING_FIXTURE_DELAY", "0")))
        if (root / "hold").exists():
            (root / "entered").touch()
            time.sleep(1.25)
        value = {"applied": {"model": "fixture-model"}}
    else:
        raise ValueError(kind)
    print(json.dumps({"type": "control_response", "response": {"subtype": "success",
          "request_id": message["request_id"], "response": value}}), flush=True)
