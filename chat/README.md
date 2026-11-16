# Connect Chat

A modern, real-time 1-on-1 chat application built with **Flutter**, **Firebase Authentication**, **Cloud Firestore**, and **Cloud Functions**. Features full compliance with App Store and Google Play safety guidelines, including user blocking, content reporting, and self-service account deletion.

---

## Features

### 🔐 Authentication & Session
- **Email & Password Authentication:** Sign up and log in powered by Firebase Auth.
- **Reactive Routing (`AuthGate`):** Listens to auth state changes to seamlessly transition between the auth flow and home page.
- **Automated Directory Profiles:** Registers user profiles to Firestore (`Users/{uid}`) upon sign-up or sign-in.
- **Error Handling:** Mapped error feedback for common issues (e.g. invalid credentials, disabled accounts, weak passwords).

### 💬 Real-Time Messaging
- **Instant 1-on-1 Chat:** Firestore real-time snapshots with server-side timestamps.
- **Canonical Chat Rooms:** Deterministic room ID generation based on base64-encoded participant IDs (`chat_rooms/{roomId}`).
- **Interactive Chat UI:**
  - Auto-scroll to the bottom on load and upon keyboard activation.
  - Styled message bubbles (`ChatBubble`) distinguishing outgoing vs. incoming messages.
  - Real-time text validation with a 4,000-character limit.

### 🛡️ Safety & Moderation (Store-Compliant)
- **Block & Unblock Users:**
  - Block or unblock directly from the chat menu or via **Settings → Blocked users**.
  - Bidirectional communication block enforced at the Firestore security rules level.
  - Blocked users are automatically hidden from the active user directory on the Home screen.
- **Content & User Reporting:**
  - Report a user from the chat options menu or **Settings → Report a user**.
  - Long-press any received message bubble to submit a report directly referencing that specific message.
  - Structured categorization (*Spam or scam*, *Harassment*, *Inappropriate content*, *Other*) with optional details.
- **Self-Service Account Deletion:**
  - Accessible via **Settings → Delete account**.
  - Requires password confirmation before permanently purging user data and sent messages via Cloud Functions.

### 🎨 Themes & Customization
- **Dark Mode & Light Mode:** Managed centrally via `ThemeProvider` (`ChangeNotifierProvider`).
- **iOS-Style Toggle:** Smooth `CupertinoSwitch` control in the Settings screen.

---

## Project Structure

```text
lib/
├── components/                 # Reusable UI widgets
│   ├── chat_bubble.dart        # Incoming & outgoing message bubbles
│   ├── delete_account_dialog.dart # Password confirmation deletion dialog
│   ├── my_button.dart          # Primary action button
│   ├── my_drawer.dart          # Navigation drawer (Home, Settings, Logout)
│   ├── my_textfield.dart       # Form and composer text fields
│   ├── report_dialog.dart      # Report reason and description dialog
│   └── user_tile.dart          # Directory list tile for contacts
├── pages/                      # Application screens
│   ├── blocked_users_page.dart # Manage and unblock blocked contacts
│   ├── chat_page.dart          # Real-time messaging conversation view
│   ├── home_page.dart          # Active user list and chat directory
│   ├── login_page.dart         # Sign-in screen
│   ├── register_page.dart      # Account creation screen
│   ├── report_user_page.dart   # Directory of users available to report
│   └── settings_page.dart      # Theme toggle and account settings
├── services/                   # Business logic and external APIs
│   ├── auth/
│   │   ├── auth_gate.dart      # Authentication state router
│   │   ├── auth_service.dart   # Firebase Auth and profile management
│   │   └── login_or_register.dart # Screen switcher for auth
│   └── chat/
│       └── chat_service.dart   # Messaging, blocking, and reporting logic
├── theme/                      # Styling and color palettes
│   ├── dark_mode.dart          # Dark color scheme
│   ├── light_mode.dart         # Light color scheme
│   └── theme_provider.dart     # State manager for theme switching
├── firebase_options.dart       # Generated FlutterFire configuration
└── main.dart                   # Application entry point
```

---

## Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.24+ recommended)
- [Firebase CLI](https://firebase.google.com/docs/cli) (`npm install -g firebase-tools` or `brew install firebase-cli`)
- A Firebase project with **Authentication** (Email/Password) and **Cloud Firestore** enabled.

### Installation & Run

1. **Clone the repository and install dependencies:**
   ```bash
   git clone <repo-url>
   cd chat
   flutter pub get
   ```

2. **Configure Firebase (if setting up your own project):**
   ```bash
   flutterfire configure
   ```

3. **Run the application:**
   ```bash
   flutter run
   ```

---

## Firebase & Backend Setup

### Firestore Security Rules
Deploy the included security rules to enforce participant privacy, room validation, and blocking restrictions:
```bash
firebase deploy --only firestore:rules --project YOUR_PROJECT_ID
```

### Account Deletion Cloud Function
The account deletion feature relies on a callable Cloud Function running on Node.js 22 in `us-central1` to safely scrub data:
```bash
npm --prefix functions ci
firebase deploy --only firestore,functions:account --project YOUR_PROJECT_ID
```

---

## Quality Checks & Testing

Run analyzer and unit/widget test suites:

```bash
# Static analysis
flutter analyze

# Unit & Widget tests (14 test suites)
flutter test

# Firestore security rules integration tests (requires local emulator)
firebase emulators:exec --only firestore,auth,functions --project demo-chat-service "python3 test/firestore_rules_test.py"
```
