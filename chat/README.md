# Connect Chat

<p align="center">
  <strong>A modern, real-time 1-on-1 chat application built with Flutter, Firebase, and Firebase Cloud Messaging (FCM).</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.24+-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.5+-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Firebase-Auth%20%7C%20Firestore%20%7C%20FCM-FFCA28?logo=firebase&logoColor=black" alt="Firebase" />
  <img src="https://img.shields.io/badge/Tests-17%20Passing-brightgreen" alt="Tests" />
  <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License" />
</p>

---

## Overview

**Connect Chat** (`me.sreejithc.chat`) is a production-grade 1-on-1 real-time messaging application designed for performance, safety, and cross-platform flexibility. The app strictly follows Google Play and Apple App Store safety and moderation guidelines, featuring user blocking, granular message/user reporting, client & server-side account deletion, dark/light theme switching, and real-time push notifications.

The application is engineered to work **100% on the Free Firebase Spark Plan ($0)** without mandatory paid infrastructure.

---

## Key Features

### 🔔 Push Notifications & Messaging (FCM)
- **Firebase Cloud Messaging (FCM v1):** Automatically handles foreground, background, and terminated device notifications.
- **Deep-Link Notification Tap:** Tapping an incoming notification opens the app and navigates directly to that contact's `ChatPage`.
- **Direct App-to-FCM Delivery ($0 Cost):** Integrated OAuth2 sender using Google Service Account credentials, eliminating the requirement for paid Cloud Functions.
- **Background Dispatcher:** Registered background entry-point handler (`firebaseMessagingBackgroundHandler`).
- **Token Management:** Devices register their push tokens on login (`Users/{uid}.fcmToken`) and purge them on logout to prevent orphaned notifications.

### 🔐 Authentication & Session
- **Firebase Authentication:** Secure email and password registration and login.
- **Reactive Navigation (`AuthGate`):** Real-time auth state listener that directs users to `HomePage` or `LoginOrRegister`.
- **Automated Directory Profiles:** User profiles are synced to Firestore (`Users/{uid}`) on authentication.
- **Safe Error Feedback:** User-friendly translated error messages for invalid credentials, weak passwords, and network issues.

### 💬 Real-Time 1-on-1 Chat
- **Instant Messaging:** Firestore real-time snapshot streams with server-side timestamps.
- **Canonical Room IDs:** Deterministic room generation using base64-encoded participant IDs (`chat_rooms/{roomId}`).
- **Interactive Chat Interface:**
  - Auto-scrolling to the latest message on load and keyboard toggle.
  - Distinct styled message bubbles (`ChatBubble`) for incoming and outgoing messages.
  - Character validation with a 4,000-character boundary.

### 🛡️ Store-Compliant Safety & Moderation
- **Block & Unblock Users:**
  - Block contacts directly from the chat screen menu or manage them in **Settings → Blocked users**.
  - Bidirectional communication blocks enforced at the database level via Firestore Security Rules.
  - Blocked users are automatically hidden from the active user directory.
- **Granular Reporting:**
  - Report users from chat options or **Settings → Report a user**.
  - Long-press any incoming message bubble to report that specific message.
  - Categorized reporting options (*Spam or scam*, *Harassment*, *Inappropriate content*, *Other*).
- **Self-Service Account Deletion:**
  - Accessible in **Settings → Delete account** with password verification.
  - Supports both direct client cleanup (Spark plan) and callable Cloud Functions (Blaze plan).

### 🎨 Themes & Customization
- **Dark Mode & Light Mode:** Managed centrally via `ThemeProvider` (`ChangeNotifierProvider`).
- **iOS-Style Toggle:** Smooth `CupertinoSwitch` control in the Settings screen.

---

## Project Structure

```text
chat/
├── android/                    # Android platform runner (me.sreejithc.chat)
├── assets/                     # Project assets (e.g. service-account.json)
├── functions/                  # Cloud Functions backend (optional Blaze triggers)
│   └── index.js                # Account deletion & message push triggers
├── ios/                        # iOS platform runner
├── lib/
│   ├── components/             # Reusable UI widgets
│   │   ├── chat_bubble.dart    # Styled message bubble with report gesture
│   │   ├── delete_account_dialog.dart # Password confirmation deletion dialog
│   │   ├── my_button.dart      # Custom action button
│   │   ├── my_drawer.dart      # Navigation drawer with home, settings, logout
│   │   ├── my_textfield.dart   # Styled form text field
│   │   ├── report_dialog.dart  # User & message report modal
│   │   └── user_tile.dart      # Directory contact tile
│   ├── pages/                  # Screen views
│   │   ├── blocked_users_page.dart # Blocked users list & unblock actions
│   │   ├── chat_page.dart      # 1-on-1 chat room conversation
│   │   ├── home_page.dart      # Active directory & user listing
│   │   ├── login_page.dart     # Sign-in screen
│   │   ├── register_page.dart  # Account registration screen
│   │   ├── report_user_page.dart # Directory of users for reporting
│   │   └── settings_page.dart  # Theme toggle & account management
│   ├── services/               # Business logic & services
│   │   ├── auth/
│   │   │   ├── auth_gate.dart  # Authentication routing gate
│   │   │   ├── auth_service.dart # Auth, profile sync & account deletion
│   │   │   └── login_or_register.dart # Screen switcher
│   │   ├── chat/
│   │   │   └── chat_service.dart # Messaging, blocking & reporting logic
│   │   └── notifications/
│   │       └── notification_service.dart # FCM tokens, permissions & push sender
│   ├── theme/                  # Theme definitions & provider
│   │   ├── dark_mode.dart      # Dark color palette
│   │   ├── light_mode.dart     # Light color palette
│   │   └── theme_provider.dart # Dynamic theme state management
│   ├── firebase_options.dart   # Generated Firebase configuration
│   └── main.dart               # App entry-point & global navigation key
├── test/                       # Unit & Widget test suite (17 tests)
│   ├── services/
│   │   ├── account_safety_test.dart
│   │   ├── auth_profile_test.dart
│   │   ├── chat_service_test.dart
│   │   └── notification_service_test.dart
│   ├── account_dialogs_test.dart
│   └── widget_test.dart
├── firestore.rules             # Production security rules
└── pubspec.yaml                # Project dependencies
```

---

## Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.24+ recommended)
- [Firebase CLI](https://firebase.google.com/docs/cli) (`brew install firebase-cli` or `npm install -g firebase-tools`)
- A Firebase project with **Authentication** (Email/Password) and **Cloud Firestore** enabled.

### Installation & Run

1. **Clone repository and install dependencies:**
   ```bash
   git clone https://github.com/your-username/chat.git
   cd chat
   flutter pub get
   ```

2. **Configure Firebase (if creating your own project):**
   ```bash
   flutterfire configure --project=YOUR_PROJECT_ID
   ```

3. **Deploy Firestore Security Rules:**
   ```bash
   firebase deploy --only firestore:rules
   ```

4. **Run the application:**
   ```bash
   flutter run
   ```

---

## Push Notifications Setup ($0 Free Option)

The app supports sending direct push notifications via FCM HTTP v1 without paying for Cloud Functions:

1. Go to your **[Firebase Console](https://console.firebase.google.com/)** → **Project Settings** → **Service accounts**.
2. Click **Generate new private key** (downloads a `.json` file).
3. Rename the downloaded file to `service-account.json`.
4. Place it in the `assets/` folder:
   ```text
   chat/assets/service-account.json
   ```
*(Note: `assets/*.json` is excluded in `.gitignore` to keep credentials secure).*

Now, whenever a user sends a message, a push notification is automatically delivered to the recipient's device, and clicking it immediately opens their conversation.

---

## Testing & Quality Assurance

Run the complete test suite and static analysis:

```bash
# Run static analysis (0 warnings)
flutter analyze

# Run unit & widget test suite (17 passed)
flutter test
```

---

## License

This project is open-source and available under the [MIT License](LICENSE).
