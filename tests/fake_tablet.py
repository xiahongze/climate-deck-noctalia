#!/usr/bin/env python3
"""In-memory MyPlace fixture server; it never contacts a real tablet."""
import copy
import json
import pathlib
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlsplit

fixture = pathlib.Path(__file__).parent / "fixtures/system.json"
state = json.loads(fixture.read_text())


def merge(target, patch):
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            merge(target[key], value)
        else:
            target[key] = copy.deepcopy(value)


def apply_command(data, path, body):
    if path == "/setAircon":
        merge(data.setdefault("aircons", {}), body)
    elif path == "/setMySystem":
        merge(data.setdefault("system", {}), body)
    elif path == "/setScene":
        scene_id = body.get("id")
        if not scene_id:
            return {"ack": False, "reason": "Scene ID required"}
        section = data.setdefault("myScenes", {})
        scenes, order = section.setdefault("scenes", {}), section.setdefault("scenesOrder", [])
        if body.get("name") == "":
            scenes.pop(scene_id, None)
            if scene_id in order:
                order.remove(scene_id)
        else:
            if scene_id not in scenes and len(scenes) >= 12:
                return {"ack": True}  # the real tablet may silently discard an over-limit save
            if scene_id not in scenes:
                scenes[scene_id] = {"id": scene_id}
                order.append(scene_id)
            for key, value in body.items():
                # Map fields are whole replacements, as on the tablet.
                scenes[scene_id][key] = copy.deepcopy(value)
    elif path != "/runScene":
        return {"ack": False, "reason": "Unknown command"}
    return {"ack": True}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path)
        if path.path == "/getSystemData" and not path.query:
            body = state
        else:
            try:
                command = json.loads(parse_qs(path.query)["json"][0])
                body = apply_command(state, path.path, command)
            except (KeyError, ValueError, TypeError):
                body = {"ack": False, "reason": "Invalid command"}
        payload = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        print(urlsplit(self.path).path, flush=True)


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 18765), Handler).serve_forever()
