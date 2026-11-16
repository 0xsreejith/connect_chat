# chat

A Flutter chat application using Firebase Authentication and Cloud Firestore.

## Chat service

`lib/services/chat/chat_service.dart` provides:

- `getUserStream()` — live public profiles; the home page hides yourself and blocked users.
- `sendMessage(receiverId, message)` — sends a validated text message.
- `getMessages(receiverId)` — the latest 50 messages, newest first.

Message queries accept a `limit` between 1 and 100. Messages are trimmed and
limited to 4,000 Dart string code units. Use a reversed list to display messages.

Profiles are stored at `Users/{uid}` with `uid`, `email`, and `displayName`.
Sign-in and registration save these public profiles. Existing accounts should
sign in again to appear in the directory. Never store passwords here.

Messages live at `chat_rooms/{roomId}/messages/{messageId}`. Both participants
must have a saved profile. The service uses authenticated sender details and
server timestamps. Handle Firebase errors in the calling screen.

```dart
final chat = ChatService();
await chat.sendMessage(receiverId, 'Hello!');
final messages = chat.getMessages(receiverId);
```

## Setup

Enable Email/Password authentication and create a Firestore database in your
Firebase project. The included rules restrict messages to participants and
profile writes to their owner. Deploy them when ready:

```sh
firebase deploy --only firestore:rules --project YOUR_PROJECT_ID
```

After adding a native Firebase plugin, stop the app and run `flutter run` again.

## Account settings

- Use a chat's menu to block, unblock, or report its participant. Long-press a
  received message to report that message.
- Settings → Blocked users lists blocked accounts and allows unblocking.
- Settings → Report a user allows selecting an account, including blocked users.
- Blocking stops new messages in both directions through Firestore rules.
  Existing history remains readable. Block lists are private to their owner.
- Reports are stored in `reports` with a reason, optional details, and optional
  message reference. Only Admin access can review them, for example through the
  Firebase Console. Submitting a report does not automatically block the user.
- Settings → Delete account requires the current password. The server removes
  the Firebase Auth account, profile, block lists, related reports, and all sent
  messages. Other participants' messages and accounts are preserved.

The `deleteAccount` callable function derives the account ID from verified
authentication and requires a sign-in within the last five minutes. An Admin-only
deletion marker prevents new writes during cleanup and after deletion. If a
cleanup attempt is interrupted, retry account deletion to finish it.

Cloud Functions deployment requires a billing-enabled Firebase project. Install
the backend dependencies and deploy the function, rules, and cleanup index:

```sh
npm --prefix functions ci
firebase deploy --only firestore,functions:account --project YOUR_PROJECT_ID
```

The function runs in `us-central1` on Node.js 22. The app uses the same region.

## Checks

```sh
flutter analyze
flutter test
firebase emulators:exec --only firestore,auth,functions --project demo-chat-service "python3 test/firestore_rules_test.py"
```

The emulator tests use a demo project and disposable accounts. They cover private
reports, bidirectional blocking, recent authentication, and deleting 251 sent
messages across multiple batches without deleting another account's data.
Firebase CLI 15 needs Java 21 or newer.
