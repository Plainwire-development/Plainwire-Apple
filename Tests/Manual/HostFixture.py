"""Run the native smoke tests against two independent installations on localhost."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import base64
import json
import os
import subprocess
import sys
import threading
import time
import tempfile
import shutil
import plistlib
from pathlib import Path

foreign_cookies = []
image_requests = {}
image_requests_lock = threading.Lock()
image = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a47sAAAAASUVORK5CYII=")


def handler_for(name):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, status, body, cookie=None, content_type="application/json"):
            if not isinstance(body, bytes):
                body = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            if cookie:
                self.send_header("Set-Cookie", cookie)
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def session(self):
            return {"user": {"id": 7, "username": "fixture", "display_name": "Host " + name,
                             "status": "online", "theme": "system", "avatar_url": "/image"},
                    "csrf": "csrf-" + name, "server_time": 1}

        def do_GET(self):
            cookies = self.headers.get("Cookie", "")
            other = "B" if name == "A" else "A"
            if "pw_session=host-" + other in cookies:
                foreign_cookies.append((name, self.path))
            if self.path in ("/image", "/slow-image", "/coalesced-image"):
                with image_requests_lock:
                    key = name + self.path
                    image_requests[key] = image_requests.get(key, 0) + 1
                if self.path in ("/slow-image", "/coalesced-image"):
                    time.sleep(0.5)
                self.reply(200, image, content_type="image/png")
            elif self.path == "/image-request-counts":
                with image_requests_lock:
                    counts = dict(image_requests)
                self.reply(200, counts)
            elif self.path == "/api/me":
                time.sleep(0.12)
                if "pw_session=host-" + name in cookies:
                    self.reply(200, {"ok": True, "data": self.session()})
                else:
                    self.reply(401, {"ok": False, "error": "not_authenticated"})
            elif self.path.startswith("/api/sync"):
                self.reply(200, {"ok": True, "data": {"now": 1, "conversations": [
                    {"id": 42, "owner_id": 7, "name": "Host " + name}],
                    "friends": [], "servers": [], "notifications": []}})
            elif self.path.startswith("/api/gifs/search"):
                self.reply(200, {"ok": True, "data": {"provider": "Fixture", "next": "", "results": [
                    {"id": "gif-1", "title": "Hello [friend] ||spoiler||", "url": "https://cdn.example/hello.gif",
                     "preview_url": "https://cdn.example/preview.gif"}]}})
            elif self.path == "/api/profile/7":
                profile = self.session()["user"]
                profile["display_name"] = "A person with a longer display name"
                profile["bio"] = "A long profile should stay readable when the window is small. " * 30
                self.reply(200, {"ok": True, "data": {"user": profile}})
            elif self.path == "/api/conversation/42":
                self.reply(200, {"ok": True, "data": {
                    "conversation": {"id": 42, "owner_id": 7, "name": "Layout fixture"},
                    "members": [{"user": {"id": index, "username": "member_" + str(index),
                                            "display_name": "A member with a long display name " + str(index)},
                                 "group_role": "owner" if index == 7 else "member"}
                                for index in range(7, 47)]}})
            else:
                self.reply(404, {"ok": False, "error": "not_found"})

        def do_POST(self):
            self.rfile.read(int(self.headers.get("Content-Length", "0")))
            if self.path == "/api/login":
                self.reply(200, {"ok": True, "data": self.session()},
                           "pw_session=host-" + name + "; Path=/; HttpOnly; SameSite=Lax")
            elif self.path == "/api/logout":
                self.reply(200, {"ok": True}, "pw_session=; Path=/; Max-Age=0")
            else:
                self.reply(200, {"ok": True})

    return Handler


servers = [ThreadingHTTPServer(("127.0.0.1", 0), handler_for(name)) for name in ("A", "B")]
for server in servers:
    threading.Thread(target=server.serve_forever, daemon=True).start()
environment = os.environ.copy()
for name, server in zip(("A", "B"), servers):
    environment["PLAINWIRE_FIXTURE_HOST_" + name] = "http://127.0.0.1:" + str(server.server_port)
try:
    # UserNotifications requires a bundle identity even when only querying
    # settings or clearing badges. Keep the smoke binary in its own test app.
    with tempfile.TemporaryDirectory(prefix="plainwire-host-smoke-") as scratch:
        app = Path(scratch) / "PlainwireSmoke.app" / "Contents"
        (app / "MacOS").mkdir(parents=True)
        executable = app / "MacOS" / "PlainwireSmoke"
        shutil.copy2(sys.argv[1], executable)
        with (app / "Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleIdentifier": "org.plainwire.tests.media-hosts",
                          "CFBundleExecutable": "PlainwireSmoke", "CFBundleName": "Plainwire Smoke",
                          "CFBundlePackageType": "APPL", "CFBundleVersion": "1"}, file)
        subprocess.run([str(executable), *sys.argv[2:]], env=environment, check=True, timeout=90)
    if foreign_cookies:
        raise RuntimeError("A session leaked between server ports: " + repr(foreign_cookies))
finally:
    for server in servers:
        server.shutdown()
        server.server_close()
