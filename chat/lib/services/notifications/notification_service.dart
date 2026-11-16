import 'dart:convert';
import 'package:chat/pages/chat_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:material_ui/material_ui.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handles background notifications when app is terminated or in background
  debugPrint("Handling background notification: ${message.messageId}");
}

class NotificationService {
  final FirebaseMessaging? _customMessaging;
  final FirebaseFirestore? _customFirestore;
  final FirebaseAuth? _customAuth;

  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _customMessaging = messaging,
        _customFirestore = firestore,
        _customAuth = auth;

  FirebaseMessaging? get _firebaseMessaging {
    if (_customMessaging != null) return _customMessaging;
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }
  FirebaseFirestore get _firestore =>
      _customFirestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;

  /// Initializes notification permissions, listeners, and token registration.
  Future<void> initNotifications() async {
    final messaging = _firebaseMessaging;
    if (messaging == null) return;

    // Request user permission (Critical for iOS and Android 13+)
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Listen for token registrations / refreshes
      messaging.onRegistered.listen((token) async {
        await saveTokenToDatabase(token);
      });

      // On iOS, APNs token is required before registering with FCM.
      // iOS Simulator does not support APNs; skip gracefully.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final apnsToken = await messaging.getAPNSToken();
        if (apnsToken == null) {
          debugPrint(
            'Notice: APNs token is not available (running on iOS Simulator or no APNs key configured). '
            'Push notification registration skipped.',
          );
          return;
        }
      }

      // Register device with Firebase Cloud Messaging
      try {
        await messaging.register();
      } catch (e) {
        debugPrint('FCM registration notice: $e');
      }

      // Handle foreground notifications
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          'Foreground notification: ${message.notification?.title} - ${message.notification?.body}',
        );
      });
    }
  }

  /// Saves the FCM token in the user's Firestore profile.
  Future<void> saveTokenToDatabase(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('Users').doc(user.uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  /// Removes the FCM token when the user signs out.
  Future<void> clearToken() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore.collection('Users').doc(user.uid).update({
          'fcmToken': FieldValue.delete(),
        });
      } catch (e) {
        debugPrint('Error clearing FCM token from Firestore: $e');
      }
    }

    try {
      await _firebaseMessaging?.unregister();
    } catch (e) {
      debugPrint('Error unregistering FCM: $e');
    }
  }

  /// Sets up listeners for when the user taps on a notification to open the chat directly.
  void setupNotificationTapHandlers(GlobalKey<NavigatorState> navKey) {
    final messaging = _firebaseMessaging;
    if (messaging == null) return;

    void handleMessage(RemoteMessage? message) {
      if (message == null) return;
      final senderID = message.data['senderID'];
      final senderEmail = message.data['senderEmail'];

      if (senderID != null && senderEmail != null) {
        navKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => ChatPage(
              receiverEmail: senderEmail.toString(),
              receiverID: senderID.toString(),
            ),
          ),
        );
      }
    }

    // Handles tapping notification when app is launched from terminated state
    messaging.getInitialMessage().then(handleMessage);

    // Handles tapping notification when app is running in background
    FirebaseMessaging.onMessageOpenedApp.listen(handleMessage);
  }

  /// Sends a push notification directly to [receiverToken] using Google OAuth2 and FCM v1 HTTP API.
  /// Reads `assets/service-account.json` to authenticate for $0 without Cloud Functions.
  Future<void> sendPushNotification({
    required String receiverToken,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    try {
      // 1. Check if service-account.json is present in assets
      String jsonStr;
      try {
        jsonStr = await rootBundle.loadString('assets/service-account.json');
      } catch (_) {
        debugPrint(
          'Notice: assets/service-account.json not found. Push notification skipped.',
        );
        return;
      }

      final serviceAccount = jsonDecode(jsonStr) as Map<String, dynamic>;
      final projectId = serviceAccount['project_id'] ?? 'connect-message-27117';

      // 2. Obtain Google OAuth2 access token for FCM
      final accountCredentials =
          auth.ServiceAccountCredentials.fromJson(serviceAccount);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

      final client =
          await auth.clientViaServiceAccount(accountCredentials, scopes);

      // 3. Send FCM v1 POST request
      final url = Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
      );

      final payload = {
        'message': {
          'token': receiverToken,
          'notification': {
            'title': title,
            'body': body,
          },
          'data': data,
        }
      };

      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'FCM send status: ${response.statusCode} - ${response.body}',
        );
      } else {
        debugPrint('FCM notification sent successfully to receiver!');
      }

      client.close();
    } catch (e) {
      debugPrint('Error sending push notification: $e');
    }
  }
}
