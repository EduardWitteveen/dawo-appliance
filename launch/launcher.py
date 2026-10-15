"""The Launcher: a small local web page to start, stop and open environments.

Part of Launch (ADR 0008, docs/adr/0008-launch-environments.md). It serves one
page on 127.0.0.1 with a card per environment of the catalogue and runs the
`launch` command for the buttons. Nothing in here is specific to one
workplace.

  launcher.py [--port 8790] [--launch launch] [--page launcher.html]
              [--auto-start ID [--auto-start-delay 60]]

With --auto-start the Launcher starts that environment by itself after the
delay (#238), so a machine can run unattended: the page shows the countdown
and a button to cancel it. It fires once, and only when nothing runs yet;
any start or stop through the page cancels it.

Safety: it listens on 127.0.0.1 only, and every action needs the random token
that is put into the page when it is served, so another web site cannot press
the buttons (cross-site requests cannot read the page). Starting and stopping
run `launch` as the user who runs the Launcher; the system decides (polkit)
what that user may start.

Experimental and unofficial. Not for production.
SPDX-License-Identifier: EUPL-1.2
"""

import argparse
import http.server
import json
import re
import secrets
import subprocess
import sys
import threading
import time

TOKEN = secrets.token_hex(16)
ID_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


def run(args, timeout=60):
    """Run launch with args; return (exit code, stdout, stderr)."""
    try:
        p = subprocess.run([OPTS.launch, *args], capture_output=True, text=True,
                           timeout=timeout, stdin=subprocess.DEVNULL)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


_CACHE = {"at": 0.0, "data": []}
_LOCK = threading.Lock()

# The pending automatic start (#238): {"id", "at"} until it fires or is
# cancelled, then None.
AUTO = {"pending": None}


def auto_start_worker(eid, at):
    """Start eid at time `at`, unless cancelled or something already runs."""
    while time.time() < at:
        time.sleep(0.5)
        if AUTO["pending"] is None:
            return
    with _LOCK:
        if AUTO["pending"] is None:
            return
        AUTO["pending"] = None
        _CACHE["at"] = 0.0
    busy = [e["id"] for e in environments() if e["state"] != "stopped"]
    if busy:
        sys.stderr.write(f"launcher: automatic start of {eid} skipped: {', '.join(busy)} already runs\n")
        return
    rc, out, err = run([eid, "--yes"], timeout=300)
    sys.stderr.write(f"launcher: automatic start of {eid}: exit {rc}: {(out + err).strip()}\n")
    with _LOCK:
        _CACHE["at"] = 0.0


def environments_cached(max_age=8.0):
    """environments(), at most every max_age seconds (the page polls often)."""
    with _LOCK:
        if time.monotonic() - _CACHE["at"] > max_age:
            _CACHE["data"] = environments()
            _CACHE["at"] = time.monotonic()
        return _CACHE["data"]


def environments():
    """The catalogue with, per environment, its state and its preflight."""
    rc, out, _ = run(["--list", "--json"])
    catalog = json.loads(out) if rc == 0 else {"environments": []}
    rc, out, _ = run(["--status", "--json"], timeout=120)
    states = {s["id"]: s for s in (json.loads(out) if rc == 0 and out.strip() else [])}
    result = []
    for env in catalog.get("environments", []):
        eid = env["id"]
        rc, out, _ = run(["--check", eid, "--json"], timeout=60)
        check = json.loads(out) if out.strip() else {"ok": True, "problems": []}
        result.append({
            "id": eid,
            "title": env.get("title", eid),
            "summary": env.get("summary", ""),
            "version": env.get("version", ""),
            "url": env.get("url", ""),
            "login": env.get("login", ""),
            "state": states.get(eid, {}).get("state", "stopped"),
            # While it starts: {step, steps, label, started, since, expected,
            # error} as the environment wrote it (#232), else None.
            "progress": states.get(eid, {}).get("progress"),
            # The automatic start that is still to come (#238), else None.
            "autostart": ({"at": AUTO["pending"]["at"]}
                          if AUTO["pending"] and AUTO["pending"]["id"] == eid else None),
            "problems": check.get("problems", []),
        })
    return result


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "Launcher"

    def send(self, code, body, ctype="application/json; charset=utf-8"):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            with open(OPTS.page, encoding="utf-8") as f:
                page = f.read().replace("__LAUNCHER_TOKEN__", TOKEN)
            self.send(200, page, "text/html; charset=utf-8")
        elif self.path == "/api/environments":
            self.send(200, json.dumps(environments_cached()))
        else:
            self.send(404, json.dumps({"error": "not found"}))

    def do_POST(self):
        if self.path == "/api/autostart/cancel":
            if self.headers.get("X-Launcher-Token") != TOKEN:
                self.send(403, json.dumps({"error": "forbidden"}))
                return
            with _LOCK:
                AUTO["pending"] = None
                _CACHE["at"] = 0.0
            self.send(200, json.dumps({"ok": True}))
            return
        m = re.fullmatch(r"/api/(start|stop)/([a-z0-9-]+)", self.path)
        if not m or not ID_RE.match(m.group(2)):
            self.send(404, json.dumps({"error": "not found"}))
            return
        if self.headers.get("X-Launcher-Token") != TOKEN:
            self.send(403, json.dumps({"error": "forbidden"}))
            return
        verb, eid = m.groups()
        with _LOCK:
            AUTO["pending"] = None  # the user chose; no automatic start
        args = [eid, "--yes"] if verb == "start" else ["--stop", eid]
        rc, out, err = run(args, timeout=300)
        with _LOCK:
            _CACHE["at"] = 0.0  # show the new state on the next refresh
        self.send(200 if rc == 0 else 500,
                  json.dumps({"ok": rc == 0, "code": rc, "output": (out + err).strip()}))

    def log_message(self, fmt, *args):
        sys.stderr.write("launcher: " + (fmt % args) + "\n")


def main():
    global OPTS
    ap = argparse.ArgumentParser(description="The Launcher (ADR 0008)")
    ap.add_argument("--port", type=int, default=8790)
    ap.add_argument("--launch", default="launch")
    ap.add_argument("--page", required=True)
    ap.add_argument("--auto-start", default="")
    ap.add_argument("--auto-start-delay", type=int, default=60)
    OPTS = ap.parse_args()
    if OPTS.auto_start:
        if not ID_RE.match(OPTS.auto_start):
            ap.error("--auto-start: not an environment id")
        at = time.time() + OPTS.auto_start_delay
        AUTO["pending"] = {"id": OPTS.auto_start, "at": at}
        threading.Thread(target=auto_start_worker, args=(OPTS.auto_start, at), daemon=True).start()
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", OPTS.port), Handler)
    sys.stderr.write(f"launcher: http://127.0.0.1:{OPTS.port}/\n")
    httpd.serve_forever()


OPTS = None
if __name__ == "__main__":
    main()
