"""Run with: firebase emulators:exec --only firestore --project demo-chat-service \
"python3 test/firestore_rules_test.py"

Uses the emulator REST API and unsigned emulator-only tokens; no production data.
"""

import base64
import json
import os
import time
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen


PROJECT = "demo-chat-service"
HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "")
DATABASE = f"projects/{PROJECT}/databases/(default)"
DOCUMENTS = f"{DATABASE}/documents"
ROOM = "YWxpY2U.Ym9i"


def token(uid):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")

    now = int(time.time())
    claims = {
        "iss": f"https://securetoken.google.com/{PROJECT}",
        "aud": PROJECT,
        "auth_time": now,
        "user_id": uid,
        "sub": uid,
        "iat": now,
        "exp": now + 3600,
        "email": f"{uid}@example.com",
        "firebase": {"sign_in_provider": "password", "identities": {}},
    }
    return f'{encode({"alg": "none", "typ": "JWT"})}.{encode(claims)}.'


def value(data):
    if data is None:
        return {"nullValue": None}
    if isinstance(data, str):
        return {"stringValue": data}
    if isinstance(data, list):
        return {"arrayValue": {"values": [value(item) for item in data]}}
    raise TypeError(data)


def fields(data):
    return {key: value(item) for key, item in data.items()}


def request(method, path, data=None, uid=None, admin=False):
    headers = {"Content-Type": "application/json"}
    if admin or uid:
        headers["Authorization"] = f'Bearer {"owner" if admin else token(uid)}'
    body = json.dumps(data).encode() if data is not None else None
    req = Request(f"http://{HOST}/{path}", body, headers, method=method)
    try:
        with urlopen(req, timeout=15) as response:
            return response.status, json.loads(response.read() or b"null")
    except HTTPError as error:
        return error.code, json.loads(error.read())


class ChatRulesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not HOST.startswith(("127.0.0.1:", "localhost:")):
            raise RuntimeError("Start the local Firestore emulator before running these tests.")

    def setUp(self):
        status, body = request("DELETE", f"emulator/v1/{DOCUMENTS}", admin=True)
        self.assertEqual(status, 200, body)
        for uid in ("alice", "bob", "mallory"):
            status, body = self.write_profile(uid, uid)
            self.assertEqual(status, 200, body)

    def write_profile(self, actor, owner, **extra):
        data = {"uid": owner, "email": f"{owner}@example.com", "displayName": None, **extra}
        return request("PATCH", f"v1/{DOCUMENTS}/Users/{owner}", {"fields": fields(data)}, uid=actor)

    def send(self, actor="alice", sender="alice", receiver="bob", text="Hello", room=ROOM, timestamp=True):
        message = {
            "senderID": sender,
            "senderEmail": f"{sender}@example.com",
            "receiverID": receiver,
            "message": text,
        }
        message_write = {"update": {
            "name": f"{DOCUMENTS}/chat_rooms/{room}/messages/message",
            "fields": fields(message),
        }}
        if timestamp:
            message_write["updateTransforms"] = [
                {"fieldPath": "timestamp", "setToServerValue": "REQUEST_TIME"}
            ]
        else:
            message_write["update"]["fields"]["timestamp"] = {
                "timestampValue": "2000-01-01T00:00:00Z"
            }
        return request("POST", f"v1/{DOCUMENTS}:commit", {"writes": [
            {"update": {
                "name": f"{DOCUMENTS}/chat_rooms/{room}",
                "fields": fields({"participantIds": ["alice", "bob"]}),
            }},
            message_write,
        ]}, uid=actor)

    def test_profile_ownership_and_public_fields(self):
        self.assertEqual(self.write_profile("bob", "alice")[0], 403)
        self.assertEqual(self.write_profile("alice", "alice", password="secret")[0], 403)
        self.assertEqual(request("GET", f"v1/{DOCUMENTS}/Users/alice")[0], 403)
        self.assertEqual(request("GET", f"v1/{DOCUMENTS}/Users/alice", uid="bob")[0], 200)

    def test_participants_can_read_messages_and_outsiders_cannot(self):
        status, body = self.send()
        self.assertEqual(status, 200, body)
        path = f"v1/{DOCUMENTS}/chat_rooms/{ROOM}/messages/message"
        for uid in ("alice", "bob"):
            self.assertEqual(request("GET", path, uid=uid)[0], 200)
        self.assertEqual(request("GET", path, uid="mallory")[0], 403)
        self.assertEqual(request("GET", path)[0], 403)
        query = {"structuredQuery": {
            "from": [{"collectionId": "messages"}],
            "orderBy": [{"field": {"fieldPath": "timestamp"}, "direction": "DESCENDING"}],
            "limit": 50,
        }}
        query_path = f"v1/{DOCUMENTS}/chat_rooms/{ROOM}:runQuery"
        self.assertEqual(request("POST", query_path, query, uid="bob")[0], 200)
        self.assertEqual(request("POST", query_path, query, uid="mallory")[0], 403)

    def test_invalid_messages_fail_without_partially_creating_a_room(self):
        for invalid in (
            {"actor": "bob", "sender": "alice"},
            {"receiver": "mallory"},
            {"text": ""},
            {"text": "   \n "},
            {"text": "x" * 4001},
            {"timestamp": False},
        ):
            status, body = self.send(**invalid)
            self.assertEqual(status, 403, body)
            status, body = request("GET", f"v1/{DOCUMENTS}/chat_rooms/{ROOM}", admin=True)
            self.assertEqual(status, 404, body)

    def test_messages_and_membership_cannot_be_rewritten(self):
        self.assertEqual(self.send()[0], 200)
        path = f"v1/{DOCUMENTS}/chat_rooms/{ROOM}/messages/message"
        self.assertEqual(request("PATCH", path, {"fields": fields({"message": "Edited"})}, uid="alice")[0], 403)
        self.assertEqual(request("DELETE", path, uid="alice")[0], 403)
        data = {"fields": fields({"participantIds": ["alice", "mallory"]})}
        self.assertEqual(request("PATCH", f"v1/{DOCUMENTS}/chat_rooms/{ROOM}", data, uid="alice")[0], 403)

    def test_room_id_must_match_its_participants(self):
        self.assertEqual(self.send(room="unrelated-room-id")[0], 403)
        data = {"fields": fields({"participantIds": ["alice", "mallory"]})}
        self.assertEqual(request("PATCH", f"v1/{DOCUMENTS}/chat_rooms/{ROOM}", data, uid="mallory")[0], 403)

    def test_rooms_require_two_existing_distinct_profiles(self):
        for participants in (["alice", "alice"], ["alice", "unknown"]):
            data = {"fields": fields({"participantIds": participants})}
            self.assertEqual(request("PATCH", f"v1/{DOCUMENTS}/chat_rooms/invalid", data, uid="alice")[0], 403)


if __name__ == "__main__":
    unittest.main(verbosity=2)
