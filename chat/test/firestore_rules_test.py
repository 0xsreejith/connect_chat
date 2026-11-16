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


def token(uid, auth_time=None):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")

    now = int(time.time())
    claims = {
        "iss": f"https://securetoken.google.com/{PROJECT}",
        "aud": PROJECT,
        "auth_time": now if auth_time is None else auth_time,
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


def request(method, path, data=None, uid=None, admin=False, base=None, bearer=None):
    headers = {"Content-Type": "application/json"}
    if admin or uid or bearer:
        headers["Authorization"] = f'Bearer {"owner" if admin else bearer or token(uid)}'
    body = json.dumps(data).encode() if data is not None else None
    req = Request(f'{base or "http://" + HOST}/{path}', body, headers, method=method)
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

    def block(self, actor, target):
        path = f"Users/{actor}/blocked_users/{target}"
        write = {"update": {"name": f"{DOCUMENTS}/{path}", "fields": fields({
            "userId": target, "email": f"{target}@example.com",
        })}, "updateTransforms": [{"fieldPath": "createdAt", "setToServerValue": "REQUEST_TIME"}]}
        return request("POST", f"v1/{DOCUMENTS}:commit", {"writes": [write]}, uid=actor)

    def test_blocks_are_private_and_stop_both_senders_until_unblocked(self):
        self.assertEqual(self.block("alice", "bob")[0], 200)
        path = f"v1/{DOCUMENTS}/Users/alice/blocked_users/bob"
        self.assertEqual(request("GET", path, uid="alice")[0], 200)
        self.assertEqual(request("GET", path, uid="bob")[0], 403)
        self.assertEqual(request("DELETE", path, uid="bob")[0], 403)
        self.assertEqual(self.send()[0], 403)
        self.assertEqual(self.send(actor="bob", sender="bob", receiver="alice")[0], 403)
        self.assertEqual(request("DELETE", path, uid="alice")[0], 200)
        self.assertEqual(self.send()[0], 200)

    def test_reports_cannot_be_read_forged_or_modified_by_clients(self):
        data = {"reporterId": "alice", "reportedUserId": "bob", "roomId": ROOM,
                "messageId": None, "reason": "Harassment", "details": "Repeated insults", "status": "pending"}
        def report(actor, payload):
            write = {"update": {"name": f"{DOCUMENTS}/reports/report", "fields": fields(payload)},
                     "updateTransforms": [{"fieldPath": "createdAt", "setToServerValue": "REQUEST_TIME"}]}
            return request("POST", f"v1/{DOCUMENTS}:commit", {"writes": [write]}, uid=actor)
        self.assertEqual(report("bob", data)[0], 403)
        self.assertEqual(report("alice", {**data, "reportedUserId": "alice"})[0], 403)
        self.assertEqual(report("alice", {**data, "messageId": "missing-message"})[0], 403)
        self.assertEqual(report("alice", data)[0], 200)
        for uid in ("alice", "bob", "mallory"):
            self.assertEqual(request("GET", f"v1/{DOCUMENTS}/reports/report", uid=uid)[0], 403)
        self.assertEqual(report("alice", data)[0], 403)

    def test_deleted_accounts_cannot_recreate_profiles_or_send_messages(self):
        status, body = request("PATCH", f"v1/{DOCUMENTS}/account_deletions/alice",
                               {"fields": fields({"status": "deleting"})}, admin=True)
        self.assertEqual(status, 200, body)
        self.assertEqual(self.write_profile("alice", "alice")[0], 403)
        self.assertEqual(self.send()[0], 403)
        self.assertEqual(self.send(actor="bob", sender="bob", receiver="alice")[0], 403)
        self.assertEqual(self.block("bob", "alice")[0], 403)
        self.assertEqual(request("DELETE", f"v1/{DOCUMENTS}/account_deletions/alice", uid="alice")[0], 403)


@unittest.skipUnless(os.environ.get("FIREBASE_AUTH_EMULATOR_HOST"), "Requires Auth and Functions emulators")
class AccountDeletionTest(unittest.TestCase):
    def setUp(self):
        self.auth_base = 'http://' + os.environ['FIREBASE_AUTH_EMULATOR_HOST']
        if not HOST.startswith(('127.0.0.1:', 'localhost:')) or not self.auth_base.startswith(('http://127.0.0.1:', 'http://localhost:')):
            raise RuntimeError('Only local demo emulators may be used.')
        self.assertEqual(request('DELETE', f'emulator/v1/{DOCUMENTS}', admin=True)[0], 200)
        self.assertEqual(request('DELETE', f'emulator/v1/projects/{PROJECT}/accounts', base=self.auth_base, admin=True)[0], 200)
        self.accounts = {}
        for name in ('alice', 'bob'):
            status, account = request('POST', 'identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake',
                {'email': f'{name}@example.com', 'password': 'test-password', 'returnSecureToken': True}, base=self.auth_base)
            self.assertEqual(status, 200)
            self.accounts[name] = account
            uid = account['localId']
            self.assertEqual(request('PATCH', f'v1/{DOCUMENTS}/Users/{uid}',
                {'fields': fields({'uid': uid, 'email': f'{name}@example.com', 'displayName': None})}, admin=True)[0], 200)

    def call_delete(self, bearer=None, data=None):
        return request('POST', f'{PROJECT}/us-central1/deleteAccount', {'data': data or {}},
                       base='http://127.0.0.1:5001', bearer=bearer)

    def test_deletion_requires_authentication_and_recent_password_confirmation(self):
        self.assertEqual(self.call_delete()[0], 401)
        alice = self.accounts['alice']['localId']
        status, body = self.call_delete(token(alice, auth_time=int(time.time()) - 600))
        self.assertEqual(status, 400, body)
        self.assertEqual(body['error']['status'], 'FAILED_PRECONDITION')
        self.assertEqual(request('GET', f'v1/{DOCUMENTS}/Users/{alice}', admin=True)[0], 200)

    def test_deletes_all_sent_messages_and_own_data_without_deleting_other_users(self):
        alice = self.accounts['alice']['localId']
        bob = self.accounts['bob']['localId']
        encode = lambda uid: base64.urlsafe_b64encode(uid.encode()).decode().rstrip('=')
        room = '.'.join(encode(uid) for uid in sorted((alice, bob)))
        documents = {f'chat_rooms/{room}': {'participantIds': sorted((alice, bob))}}
        # More than one page proves that cleanup is not limited to a single batch.
        for index in range(251):
            documents[f'chat_rooms/{room}/messages/alice-{index}'] = {'senderID': alice, 'message': 'Delete me'}
        documents[f'chat_rooms/{room}/messages/bob-message'] = {'senderID': bob, 'message': 'Keep me'}
        documents[f'Users/{alice}/blocked_users/{bob}'] = {'userId': bob, 'email': 'bob@example.com'}
        documents[f'Users/{bob}/blocked_users/{alice}'] = {'userId': alice, 'email': 'alice@example.com'}
        documents['reports/alice-report'] = {'reporterId': alice, 'reportedUserId': bob}
        documents['reports/bob-report'] = {'reporterId': bob, 'reportedUserId': alice}
        documents['reports/other-report'] = {'reporterId': bob, 'reportedUserId': 'someone-else'}
        writes = [{'update': {'name': f'{DOCUMENTS}/{path}', 'fields': fields(data)}} for path, data in documents.items()]
        self.assertEqual(request('POST', f'v1/{DOCUMENTS}:commit', {'writes': writes}, admin=True)[0], 200)

        status, result = self.call_delete(self.accounts['alice']['idToken'], {'uid': bob})
        self.assertEqual(status, 200, result)
        self.assertTrue(result['result']['deleted'])
        self.assertEqual(request('GET', f'v1/{DOCUMENTS}/Users/{alice}', admin=True)[0], 404)
        self.assertEqual(request('GET', f'v1/{DOCUMENTS}/Users/{bob}', admin=True)[0], 200)
        status, remaining = request('GET', f'v1/{DOCUMENTS}/chat_rooms/{room}/messages', admin=True)
        self.assertEqual(status, 200)
        self.assertEqual(len(remaining['documents']), 1)
        self.assertEqual(remaining['documents'][0]['fields']['message']['stringValue'], 'Keep me')
        self.assertEqual(request('GET', f'v1/{DOCUMENTS}/Users/{bob}/blocked_users/{alice}', admin=True)[0], 404)
        self.assertEqual(request('GET', f'v1/{DOCUMENTS}/reports/alice-report', admin=True)[0], 404)
        self.assertEqual(request('GET', f'v1/{DOCUMENTS}/reports/bob-report', admin=True)[0], 404)
        self.assertEqual(request('GET', f'v1/{DOCUMENTS}/reports/other-report', admin=True)[0], 200)
        status, _ = request('POST', 'identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake',
            {'email': 'alice@example.com', 'password': 'test-password', 'returnSecureToken': True}, base=self.auth_base)
        self.assertEqual(status, 400)
        status, _ = request('POST', 'identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake',
            {'email': 'bob@example.com', 'password': 'test-password', 'returnSecureToken': True}, base=self.auth_base)
        self.assertEqual(status, 200)


if __name__ == "__main__":
    unittest.main(verbosity=2)
