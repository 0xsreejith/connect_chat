# chat

A Flutter chat application using Firebase Authentication and Cloud Firestore.

## Chat service

`lib/services/chat/chat_service.dart` provides:

- `getUserStream()` — live public profiles ordered by email, excluding yourself.
- `sendMessage(receiverId, message)` — sends a validated text message.
- `getMessages(receiverId)` — the latest 50 messages, newest first.

Streams accept a `limit` between 1 and 100. Messages are trimmed and limited to
4,000 Dart string code units. Use a reversed list to display messages.

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

The rules remain local. The home page still needs a user directory and chat UI.

## Checks

```sh
flutter analyze
flutter test
firebase emulators:exec --only firestore --project demo-chat-service "python3 test/firestore_rules_test.py"
```

The rules test uses a local emulator and a demo project. Firebase CLI 15 needs
Java 21 or newer.
