#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""A tiny fake Kimai for trying the app by hand.

    ./build-aux/mock-kimai.py [port]          # token: testtoken

Control endpoints (no auth), to simulate things happening "elsewhere":
    /__stop           stop every running entry
    /__start?p=1&a=1  start one
    /__start?p=1&a=1&begin=-7200   ... that began N seconds from now
    /__offline=1|0    drop all connections / serve again
    /__skew=SECONDS   make the Date header run ahead of the real clock
    /__slow=SECONDS   delay every answer
"""
import json, sys, time, threading
from datetime import datetime, timedelta, timezone
from email.utils import formatdate
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

TOKEN = "testtoken"
CUSTOMERS = {1: "ACME Corp", 2: "Globex"}
PROJECTS = [
    {"id": 1, "name": "Website Relaunch", "parentTitle": CUSTOMERS[1], "visible": True, "color": "#3584e4"},
    {"id": 2, "name": "Internal", "parentTitle": CUSTOMERS[2], "visible": True, "color": "#9141ac"},
    {"id": 3, "name": "Support", "parentTitle": CUSTOMERS[1], "visible": True, "color": None},
]
ACTIVITIES = {
    1: [{"id": 1, "name": "Development"}, {"id": 2, "name": "Design"}, {"id": 3, "name": "Meeting"}],
    2: [{"id": 3, "name": "Meeting"}, {"id": 4, "name": "Planning"}],
    3: [{"id": 5, "name": "Tickets"}],
}
lock = threading.Lock()
state = {"entries": [], "next_id": 100, "offline": False, "skew": 0, "slow": 0.0}


def fmt(dt):  # Kimai/PHP style: offset without colon
    return dt.strftime("%Y-%m-%dT%H:%M:%S%z")


def entry(e):
    return {
        "id": e["id"], "begin": fmt(e["begin"]), "end": fmt(e["end"]) if e["end"] else None,
        "project": e["project"], "activity": e["activity"], "description": e["description"],
    }


def start(p, a, begin=None, description=None):
    e = {"id": state["next_id"], "begin": begin or datetime.now(timezone.utc).astimezone(),
         "end": None, "project": p, "activity": a, "description": description}
    state["next_id"] += 1
    state["entries"].append(e)
    return e


def seed():
    """A few finished entries over the last days, for the history page."""
    now = datetime.now(timezone.utc).astimezone()
    day = now.replace(hour=0, minute=0, second=0, microsecond=0)
    plan = [  # (days ago, start hour, minutes, project, activity, description)
        (0, 8, 95, 1, 1, "Header redesign"), (0, 10, 50, 2, 4, None), (1, 9, 180, 1, 2, "Landing page"),
        (1, 13, 45, 3, 5, "Ticket 4711"), (1, 15, 75, 1, 3, None), (3, 9, 240, 1, 1, "API client"),
        (3, 14, 60, 2, 3, "Weekly"), (6, 10, 120, 3, 5, None),
    ]
    for ago, hour, mins, p, a, d in plan:
        b = day - timedelta(days=ago) + timedelta(hours=hour)
        e = start(p, a, b, d)
        e["end"] = b + timedelta(minutes=mins)


def full(e):
    out = entry(e)
    pr = next(p for p in PROJECTS if p["id"] == e["project"])
    ac = next(a for a in ACTIVITIES[e["project"]] if a["id"] == e["activity"])
    out["project"] = {"id": pr["id"], "name": pr["name"], "color": pr.get("color"),
                      "customer": {"id": 1, "name": pr["parentTitle"]}}
    out["activity"] = {"id": ac["id"], "name": ac["name"]}
    return out


def parse_naive(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%S").astimezone()


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt_, *args):
        print(self.command, self.path, "->", args[1] if len(args) > 1 else "", flush=True)

    def send(self, code, body=None):
        if state["slow"]:
            time.sleep(state["slow"])
        data = json.dumps(body if body is not None else {}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Date", formatdate(time.time() + state["skew"], usegmt=True))
        self.end_headers()
        self.wfile.write(data)

    def handle_any(self):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        path = u.path
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}") if length else {}
        with lock:
            if path.startswith("/__"):
                if path == "/__stop":
                    for e in state["entries"]:
                        e["end"] = e["end"] or datetime.now(timezone.utc).astimezone()
                elif path == "/__start":
                    off = int(q.get("begin", 0))
                    start(int(q.get("p", 1)), int(q.get("a", 1)),
                          datetime.now(timezone.utc).astimezone() + timedelta(seconds=off))
                elif path.startswith("/__offline="):
                    state["offline"] = path.endswith("1")
                elif path.startswith("/__skew="):
                    state["skew"] = int(path.split("=")[1])
                elif path.startswith("/__slow="):
                    state["slow"] = float(path.split("=")[1])
                return self.send(200, {"ok": True})
            if state["offline"]:
                self.close_connection = True
                self.connection.close()
                return
            if self.headers.get("Authorization") != f"Bearer {TOKEN}":
                return self.send(401, {"code": 401, "message": "Invalid token"})
            m = self.command, path
            running = [e for e in state["entries"] if not e["end"]]
            if m == ("GET", "/api/version"):
                return self.send(200, {"version": "2.99.0", "versionId": 29900, "copyright": "mock"})
            if m == ("GET", "/api/users/me"):
                return self.send(200, {"id": 1, "username": "tester", "timezone": "Europe/Berlin"})
            if m == ("GET", "/api/timesheets"):
                done = sorted([e for e in state["entries"] if e["end"]], key=lambda e: e["begin"], reverse=True)
                return self.send(200, [full(e) if q.get("full") else entry(e) for e in done])
            if self.command == "PATCH" and path.startswith("/api/timesheets/") and not path.endswith("/stop"):
                tid = int(path.split("/")[3])
                for e in state["entries"]:
                    if e["id"] == tid:
                        e["project"] = body.get("project", e["project"])
                        e["activity"] = body.get("activity", e["activity"])
                        e["description"] = body.get("description", e["description"])
                        if body.get("begin"):
                            e["begin"] = parse_naive(body["begin"])
                        if body.get("end"):
                            e["end"] = parse_naive(body["end"])
                        return self.send(200, full(e))
                return self.send(404, {"code": 404, "message": "Not found"})
            if self.command == "DELETE" and path.startswith("/api/timesheets/"):
                tid = int(path.split("/")[3])
                state["entries"] = [e for e in state["entries"] if e["id"] != tid]
                self.send_response(204)
                self.send_header("Date", formatdate(time.time() + state["skew"], usegmt=True))
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if m == ("GET", "/api/timesheets/active"):
                return self.send(200, [entry(e) for e in running])
            if m == ("GET", "/api/timesheets/recent"):
                done = sorted([e for e in state["entries"] if e["end"]], key=lambda e: e["begin"], reverse=True)
                return self.send(200, [entry(e) for e in done])
            if m == ("GET", "/api/projects"):
                return self.send(200, PROJECTS)
            if m == ("GET", "/api/activities"):
                return self.send(200, ACTIVITIES.get(int(q.get("project", 0)), []))
            if m == ("POST", "/api/timesheets"):
                if not body.get("project") or not body.get("activity"):
                    return self.send(400, {"code": 400, "message": "Validation Failed",
                                           "errors": {"errors": [], "children": {"project": {"errors": ["This value should not be blank."]}}}})
                return self.send(200, entry(start(body["project"], body["activity"], description=body.get("description"))))
            if self.command == "PATCH" and path.startswith("/api/timesheets/") and path.endswith("/stop"):
                tid = int(path.split("/")[3])
                for e in state["entries"]:
                    if e["id"] == tid:
                        if e["end"]:
                            return self.send(400, {"code": 400, "message": "Timesheet entry already stopped"})
                        e["end"] = datetime.now(timezone.utc).astimezone()
                        return self.send(200, entry(e))
                return self.send(404, {"code": 404, "message": "Not found"})
            return self.send(404, {"code": 404, "message": "Not found"})

    do_GET = do_POST = do_PATCH = do_DELETE = handle_any


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    seed()
    print(f"mock Kimai on http://127.0.0.1:{port}  token: {TOKEN}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
