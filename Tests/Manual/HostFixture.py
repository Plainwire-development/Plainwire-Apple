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
from urllib.parse import urlsplit, parse_qs
import copy

foreign_cookies = []
image_requests = {}
image_requests_lock = threading.Lock()
image = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a47sAAAAASUVORK5CYII=")


def handler_for(name):
    forum_lock = threading.RLock()
    sequences = {"forum": 80, "thread": 800, "reply": 1000}
    forum_rows = {
        5: {"id": 5, "slug": "design-studio", "name": "Design studio", "description": "Thoughtful details, fresh perspectives, and ideas taking shape.", "owner_id": 8, "joined": False, "member_count": 42},
        6: {"id": 6, "slug": "building-together", "name": "Building together", "description": "Share what you’re making. Learn something along the way.", "owner_id": 7, "joined": True, "member_count": 68},
        7: {"id": 7, "slug": "off-the-clock", "name": "Off the clock", "description": "A little music, a good story, and a place to unwind.", "owner_id": 8, "joined": True, "member_count": 35},
    }
    people = {7: ("fixture", "Host " + name), 8: ("morgan", "Morgan Ellis"), 9: ("alex", "Alex Chen")}
    thread_rows, reply_rows = {}, {}
    for index, (forum_id, title, author, score, body) in enumerate([
        (5, "What makes a chat app feel like home?", 8, 24, "## Small details, big difference\n\nReadable text. A little breathing room. Nothing that feels slow.\n\n- Calm colors\n- A thoughtful place for every conversation\n- Spaces that feel like your own\n\nWhat details matter most to you?"),
        (5, "Share your workspace", 9, 9, "A favorite corner, a useful shortcut, or something you made yourself. Show us around."),
        (6, "What’s on your workbench?", 7, 16, "I’m making something small, useful, and a little more personal. What are you building this week?"),
        (6, "A tiny improvement you’re proud of", 8, 8, "Sometimes the smallest changes make the biggest difference. Share a recent win."),
        (7, "Your soundtrack this week", 9, 5, "What have you had on repeat? I’m collecting a few new favorites."),
    ]):
        tid = 700 + index
        username, display_name = people[author]
        thread_rows[tid] = {"id": tid, "forum_id": forum_id, "forum_name": forum_rows[forum_id]["name"], "user_id": author,
                            "username": username, "display_name": display_name, "avatar_url": "", "title": title,
                            "body": body, "raw_body": body, "created_at": 1792116000000 + index * 60000,
                            "updated_at": 1792119600000 + index * 60000, "locked": False, "pinned": index == 0,
                            "views": 120 + index * 17, "score": score, "user_vote": 0}
        reply_rows[tid] = []
    for rid, author, body in [(900, 7, "Readable text, fast avatars, and enough room to follow a good idea."),
                              (901, 9, "**Yes.** And the little things should feel effortless.\n\n> Good design leaves room for the conversation.")]:
        username, display_name = people[author]
        reply_rows[700].append({"id": rid, "thread_id": 700, "user_id": author, "username": username,
                               "display_name": display_name, "avatar_url": "", "body": body, "raw_body": body,
                               "created_at": 1792120000000 + rid, "updated_at": 1792120000000 + rid})

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

        def forum_snapshot(self, forum):
            rows = [t for t in thread_rows.values() if t["forum_id"] == forum["id"]]
            return dict(forum, thread_count=len(rows), reply_count=sum(len(reply_rows[t["id"]]) for t in rows),
                        last_at=max((t["updated_at"] for t in rows), default=None), position=forum["id"])

        def thread_snapshot(self, thread):
            forum = forum_rows[thread["forum_id"]]
            owner = forum["owner_id"] == 7
            author = thread["user_id"] == 7 and forum["joined"]
            return dict(thread, viewer_joined=forum["joined"], can_edit=author, can_delete=owner or author,
                        can_moderate=owner, reply_count=len(reply_rows[thread["id"]]))

        def forum_get(self):
            url = urlsplit(self.path)
            parts = url.path.strip("/").split("/")
            query = parse_qs(url.query)
            with forum_lock:
                if parts == ["api", "forums"]:
                    data = [self.forum_snapshot(f) for f in forum_rows.values()]
                elif parts == ["api", "threads"]:
                    forum_id = int(query.get("forum_id", [0])[0])
                    search = query.get("q", [""])[0].lower()
                    data = [self.thread_snapshot(t) for t in thread_rows.values() if t["forum_id"] == forum_id
                            and (not search or search in (t["title"] + t["body"]).lower())]
                elif len(parts) == 3 and parts[:2] == ["api", "thread"]:
                    tid = int(parts[2])
                    source_id = 700 if tid in (999, 1000) else tid
                    if source_id not in thread_rows:
                        self.reply(404, {"ok": False, "error": "not_found"})
                        return True
                    thread = self.thread_snapshot(thread_rows[source_id])
                    thread["id"] = tid
                    data = {"thread": thread, "replies": [dict(r, can_edit=r["user_id"] == 7 and thread["viewer_joined"],
                                                                 can_delete=thread["can_moderate"] or (r["user_id"] == 7 and thread["viewer_joined"]))
                                                          for r in reply_rows[source_id]]}
                else:
                    return False
                data = copy.deepcopy(data)
            if query.get("q") == ["slow"] or url.path in ("/api/thread/999", "/api/thread/1000"):
                time.sleep(0.5)
            self.reply(200, {"ok": True, "data": data})
            return True

        def forum_post(self, payload):
            parts = urlsplit(self.path).path.strip("/").split("/")
            if len(parts) < 2 or parts[1] not in ("forums", "forum", "threads", "thread"):
                return False
            if self.headers.get("X-CSRF-Token") != "csrf-" + name:
                self.reply(403, {"ok": False, "error": "csrf_invalid"})
                return True
            with forum_lock:
                if parts == ["api", "forums"]:
                    fid = sequences["forum"]
                    sequences["forum"] += 1
                    forum_rows[fid] = dict(payload, id=fid, owner_id=7, joined=True, member_count=1)
                    result = {"id": fid}
                elif len(parts) == 4 and parts[:2] == ["api", "forum"]:
                    fid = int(parts[2])
                    if fid not in forum_rows:
                        self.reply(404, {"ok": False, "error": "not_found"})
                        return True
                    if parts[3] == "delete":
                        for tid in [t["id"] for t in thread_rows.values() if t["forum_id"] == fid]:
                            del thread_rows[tid]
                            del reply_rows[tid]
                        del forum_rows[fid]
                    else:
                        joined = parts[3] == "join"
                        forum_rows[fid]["member_count"] += int(joined) - int(forum_rows[fid]["joined"])
                        forum_rows[fid]["joined"] = joined
                    result = {"id": fid}
                elif parts == ["api", "threads"]:
                    fid = int(payload["forum_id"])
                    if not forum_rows[fid]["joined"]:
                        self.reply(403, {"ok": False, "error": "forum_membership_required"})
                        return True
                    tid = sequences["thread"]
                    sequences["thread"] += 1
                    now = int(time.time() * 1000)
                    thread_rows[tid] = dict(id=tid, forum_id=fid, forum_name=forum_rows[fid]["name"], user_id=7,
                                           username="fixture", display_name="Host " + name, avatar_url="", title=payload["title"],
                                           body=payload["body"], raw_body=payload["body"], created_at=now, updated_at=now,
                                           locked=False, pinned=False, score=0, user_vote=0, views=0)
                    reply_rows[tid] = []
                    result = {"id": tid}
                elif len(parts) >= 4 and parts[:2] == ["api", "thread"]:
                    tid = int(parts[2])
                    thread = thread_rows.get(tid)
                    if thread is None:
                        self.reply(404, {"ok": False, "error": "not_found"})
                        return True
                    action = parts[3]
                    if action == "delete":
                        del thread_rows[tid]
                        del reply_rows[tid]
                        result = {"deleted": True, "id": tid}
                    elif action == "vote":
                        value = payload["value"]
                        thread["score"] += value - thread["user_vote"]
                        thread["user_vote"] = value
                        result = {"thread_id": tid, "score": thread["score"], "user_vote": value}
                    elif action == "moderate":
                        thread["locked" if payload["action"] == "lock" else "pinned"] = payload["value"]
                        result = {"updated": True}
                    elif action == "edit":
                        thread.update(title=payload["title"], body=payload["body"], raw_body=payload["body"])
                        result = {"updated": True}
                    elif action == "replies":
                        if thread["locked"] or not forum_rows[thread["forum_id"]]["joined"]:
                            self.reply(403, {"ok": False, "error": "thread_locked" if thread["locked"] else "forum_membership_required"})
                            return True
                        rid = sequences["reply"]
                        sequences["reply"] += 1
                        now = int(time.time() * 1000)
                        result = dict(id=rid, thread_id=tid, user_id=7, username="fixture", display_name="Host " + name,
                                      avatar_url="", body=payload["body"], raw_body=payload["body"], created_at=now, updated_at=now)
                        reply_rows[tid].append(result)
                    elif action == "reply" and len(parts) == 6:
                        rid = int(parts[4])
                        if parts[5] == "delete":
                            reply_rows[tid] = [r for r in reply_rows[tid] if r["id"] != rid]
                        else:
                            next(r for r in reply_rows[tid] if r["id"] == rid).update(body=payload["body"], raw_body=payload["body"])
                        result = {"updated": True}
                    else:
                        return False
                else:
                    return False
            self.reply(200, {"ok": True, "data": result})
            return True

        def do_GET(self):
            cookies = self.headers.get("Cookie", "")
            other = "B" if name == "A" else "A"
            if "pw_session=host-" + other in cookies:
                foreign_cookies.append((name, self.path))
            if self.forum_get():
                return
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
            elif self.path == "/api/notifications":
                self.reply(200, {"ok": True, "data": []})
            elif self.path.startswith("/api/messages?"):
                query = parse_qs(urlsplit(self.path).query)
                scope = query.get("scope", ["channel"])[0]
                scope_id = int(query.get("scope_id", ["801"])[0])
                bodies = ["Welcome to the community. Everything has a little more room here.",
                          "A longer message should wrap comfortably without crowding the header, composer, or member list. " * 3,
                          "The latest updates are ready to share. What are you working on today?"]
                self.reply(200, {"ok": True, "data": [
                    {"id": 9000 + index, "scope": scope, "scope_id": scope_id, "user_id": 20 + index % 3,
                     "username": ["morgan", "alex", "sam"][index % 3],
                     "display_name": ["Morgan Ellis", "Alex Chen", "Sam Rivera"][index % 3],
                     "body": bodies[index % 3], "created_at": 1792108800000 + index * 600_000}
                    for index in range(24)]})
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
            raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            payload = json.loads(raw) if raw else {}
            if self.forum_post(payload):
                return
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
        assets = Path(sys.argv[1]).resolve().parent / "Build/Products/Debug/Plainwire.app/Contents/Resources/Assets.car"
        if assets.is_file():
            (app / "Resources").mkdir()
            shutil.copy2(assets, app / "Resources/Assets.car")
        with (app / "Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleIdentifier": "org.plainwire.tests.media-hosts",
                          "CFBundleExecutable": "PlainwireSmoke", "CFBundleName": "Plainwire Smoke",
                          "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "NSAccentColorName": "AccentColor"}, file)
        subprocess.run([str(executable), *sys.argv[2:]], env=environment, check=True, timeout=90)
    if foreign_cookies:
        raise RuntimeError("A session leaked between server ports: " + repr(foreign_cookies))
finally:
    for server in servers:
        server.shutdown()
        server.server_close()
