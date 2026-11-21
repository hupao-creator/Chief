"""Measure public HTTP on a fresh profile with the production Claude adapter."""
import argparse
import concurrent.futures
import hashlib
import http.client
import json
import os
import platform
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def wait_for(predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while not predicate():
        if time.monotonic() >= deadline:
            raise TimeoutError("fixture did not reach the expected state")
        time.sleep(.005)


class Client:
    def __init__(self, discovery, record):
        self.port = discovery["port"]
        self.headers = {"Authorization": "Bearer " + discovery["token"],
                        "X-Mokusei-Protocol": str(discovery["protocolVersion"]),
                        "X-Mokusei-Epoch": discovery["epoch"], "Content-Type": "application/json"}
        self.record = record

    def post(self, conn, command, args):
        body = json.dumps({"commandId": f"{time.time_ns() // 1000000}_{uuid.uuid4()}", "args": args})
        conn.request("POST", "/invoke/" + command, body, self.headers)

    def invoke(self, role, command, *args):
        start = time.monotonic_ns()
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=20)
        try:
            self.post(conn, command, args)
            response = conn.getresponse()
            first = time.monotonic_ns()
            data = response.read()
            end = time.monotonic_ns()
        finally:
            conn.close()
        envelope = json.loads(data)
        self.record(role=role, command=command, start=start, headers=first, end=end,
                    bytes=len(data), http=response.status, ok=envelope["ok"])
        if response.status != 200 or not envelope["ok"]:
            raise RuntimeError((command, envelope.get("error")))
        return envelope["value"]

    def cancel_refresh(self, root, binding):
        command = "harness:settings-presentation"
        hold = root / "hold-init"
        pid_file = root / "probing"
        hold.touch()
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=20)
        try:
            self.post(conn, command, [{**binding, "refresh": True}])
            wait_for(lambda: pid_file.exists() and pid_file.read_text())
            pid = int(pid_file.read_text())
            start = time.monotonic_ns()
            conn.close()

            def retired():
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    return True
                return False
            wait_for(retired, timeout=5)
            self.record(role="cancel-refresh", command=command, disconnect=start, drained=time.monotonic_ns())
        finally:
            conn.close()
            hold.unlink()
            pid_file.unlink(missing_ok=True)

    def stream(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=25)
        try:
            start = time.monotonic_ns()
            conn.request("GET", "/events", headers=self.headers)
            response = conn.getresponse()
            hello = response.readline()
            first = time.monotonic_ns()
            if json.loads(hello)["type"] != "hello":
                raise ValueError("missing stream handshake")
            while True:
                line = response.readline()
                if line == b"\n":
                    break
                if not line:
                    raise EOFError("missing keepalive")
            self.record(role="stream", command="/events", start=start, hello=first,
                        heartbeat=time.monotonic_ns(), http=response.status)
        finally:
            conn.close()


def workload(client, root, rounds, interval):
    execution = {"scope": "global", "harnessId": "claude", "executionOwner": "moku"}
    defaults = {"scope": "global", "harnessId": "claude"}

    def present(role, binding):
        value = client.invoke(role, "harness:settings-presentation", binding)
        if "executionSnapshotError" in value or value["value"]["models"][0]["value"] != "fixture-model":
            raise ValueError(("presentation did not load", value.get("executionSnapshotError")))

    def detect():
        result = client.invoke("discovery", "harness:detect-installation", "claude")
        if result["status"] != "installed":
            raise ValueError("fixture not installed")

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        present("initialize", execution)
        present("defaults", defaults)
        heartbeat = pool.submit(client.stream)
        for _ in range(rounds):
            state = client.invoke("setup", "state:load")
            settings = state["settings"]
            profile = settings["moku"]["executionHarnesses"]["claude"]["threadSettings"]
            profile["permissionMode"] = "plan" if profile["permissionMode"] != "plan" else "auto"
            (root / "entered").unlink(missing_ok=True)
            (root / "hold").touch()
            save = pool.submit(client.invoke, "save", "app:update-settings",
                               {"settings": settings, "expectedSettingsRevision": state["settingsRevision"]})
            wait_for((root / "entered").exists)
            client.record(role="validation-entered", at=time.monotonic_ns())
            reads = [pool.submit(present, "prefetch", execution), pool.submit(present, "control", defaults),
                     pool.submit(detect)]
            for read in reads:
                read.result()
            (root / "hold").unlink()
            result = save.result()
            if result["status"] != "saved" or result["settingsRevision"] != state["settingsRevision"] + 1:
                raise ValueError("save lost or spurious revision")
            committed = client.invoke("verify", "state:load")
            if committed["settingsRevision"] != result["settingsRevision"] or committed["settings"] != result["settings"]:
                raise ValueError("committed settings changed under readers")
        heartbeat.result()
        client.cancel_refresh(root, execution)
        present("after-cancel", execution)
        for _ in range(2):
            # The workspace waits from completion of one round to the next.
            deadline = time.monotonic() + interval
            while time.monotonic() + 15 < deadline:
                time.sleep(15)
                detect()
            time.sleep(max(0, deadline - time.monotonic()))
            present("periodic", execution)
            present("periodic-defaults", defaults)
        for line in (root / "calls").read_text().splitlines():
            kind, at = line.split()
            client.record(role="native-peer", method=kind, at=int(at))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("seed", type=Path)
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--interval", type=float, default=300)
    args = parser.parse_args()
    binary = args.binary.resolve()
    peer = Path(__file__).with_name("peer.py")
    def record(**values):
        print(json.dumps(values), flush=True)
    record(binarySHA256=digest(binary), seedSHA256=digest(args.seed), collectorSHA256=digest(Path(__file__)),
           peerSHA256=digest(peer), macOS=platform.mac_ver()[0], arch=platform.machine(),
           python=platform.python_version(), rounds=args.rounds, intervalSeconds=args.interval)
    with tempfile.TemporaryDirectory(prefix="chief-http-") as temp:
        root = Path(temp).resolve()
        profile = root / "profile"
        subprocess.run([args.seed.resolve(), profile], check=True)
        claude = root / "claude"
        claude.write_bytes(b"#!" + os.fsencode(sys.executable) + b"\n" + peer.read_bytes())
        claude.chmod(0o700)
        env = {"HOME": str(root), "TMPDIR": str(root), "PATH": str(root) + ":/usr/bin:/bin",
               "CHIEF_HEADLESS": "1", "SHELL": "/bin/sh"}
        process = subprocess.Popen([binary, "serve", "--data-dir", profile], env=env, cwd=root,
                                   stdout=subprocess.DEVNULL)
        try:
            path = profile / "runtime/connection.json"
            wait_for(lambda: path.exists() or process.poll() is not None)
            if process.poll() is not None:
                raise RuntimeError(f"fixture startup exited with {process.returncode}")
            conn = json.loads(path.read_text())
            if conn["pid"] != process.pid or Path(conn["dataDir"]).resolve() != profile:
                raise ValueError("discovery belongs to another instance")
            workload(Client(conn, record), root, args.rounds, args.interval)
        finally:
            if process.poll() is None:
                process.terminate()
                if process.wait(timeout=30) != 0:
                    raise RuntimeError("runtime failed to close")


if __name__ == "__main__":
    main()
