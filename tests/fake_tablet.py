#!/usr/bin/env python3
"""Read-only fixture server for manual Noctalia integration tests."""
import json
import pathlib
from http.server import BaseHTTPRequestHandler, HTTPServer

fixture = pathlib.Path(__file__).parent / "fixtures/system.json"

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/getSystemData":
            body = fixture.read_bytes()
        elif self.path.startswith(("/setAircon?", "/setScene?", "/runScene?", "/setMySystem?")):
            body = json.dumps({"ack": True}).encode()
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(self.path.split("?", 1)[0], flush=True)

if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 18765), Handler).serve_forever()
