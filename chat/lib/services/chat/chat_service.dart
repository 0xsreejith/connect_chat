import 'dart:convert';

import 'package:chat/services/notifications/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  static const reportReasons = [
    'Spam or scam',
    'Harassment',
    'Inappropriate content',
    'Other',
  ];

  ChatService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    NotificationService? notificationService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _customAuth = auth,
        _customNotificationService = notificationService;

  final FirebaseFirestore _firestore;
  final FirebaseAuth? _customAuth;
  final NotificationService? _customNotificationService;

  FirebaseAuth get _effectiveAuth => _customAuth ?? FirebaseAuth.instance;
  NotificationService get _effectiveNotificationService =>
      _customNotificationService ?? NotificationService();

  /// Live public profiles ordered by email.
  Stream<List<Map<String, dynamic>>> getUserStream() {
    return _firestore.collection('Users').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => {...doc.data(), 'uid': doc.id})
          .toList();
    });
  }

  User _requireUser() {
    final user = _effectiveAuth.currentUser;
    if (user == null) throw StateError('Please sign in to continue.');
    return user;
  }

  CollectionReference<Map<String, dynamic>> _blockedUsers() {
    return _firestore
        .collection('Users')
        .doc(_requireUser().uid)
        .collection('blocked_users');
  }

  Stream<List<Map<String, dynamic>>> getBlockedUsers() {
    return _blockedUsers().snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => {...doc.data(), 'userId': doc.id})
          .toList();
    });
  }

  Future<void> blockUser(String userId, String email) async {
    if (userId.isEmpty ||
        userId == _requireUser().uid ||
        userId.contains('/')) {
      throw ArgumentError('Please select another user.');
    }
    await _blockedUsers().doc(userId).set({
      'userId': userId,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unblockUser(String userId) =>
      _blockedUsers().doc(userId).delete();

  Future<void> reportUser(
    String userId, {
    required String reason,
    String details = '',
    String? messageId,
  }) async {
    final reporter = _requireUser();
    if (userId.isEmpty || userId == reporter.uid || userId.contains('/')) {
      throw ArgumentError('Please select another user.');
    }
    if (!reportReasons.contains(reason) || details.trim().length > 1000) {
      throw ArgumentError(
        'Choose a reason and keep the description under 1,000 characters.',
      );
    }
    await _firestore.collection('reports').add({
      'reporterId': reporter.uid,
      'reportedUserId': userId,
      'roomId': getRoomId(reporter.uid, userId),
      'messageId': messageId,
      'reason': reason,
      'details': details.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  /// Generates the canonical room ID for two participants.
  static String getRoomId(String userId1, String userId2) {
    final sorted = [userId1, userId2]..sort();
    final p0 = base64Url.encode(utf8.encode(sorted[0])).replaceAll('=', '');
    final p1 = base64Url.encode(utf8.encode(sorted[1])).replaceAll('=', '');
    return '$p0.$p1';
  }

  /// Sends a validated text message to [receiverId].
  Future<void> sendMessage(String receiverId, String message) async {
    final currentUser = _requireUser();
    if (receiverId.isEmpty ||
        receiverId == currentUser.uid ||
        receiverId.contains('/')) {
      throw ArgumentError('Please select another user.');
    }

    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > 4000) {
      throw ArgumentError('Message exceeds maximum length of 4000 characters.');
    }

    if ((await _blockedUsers().doc(receiverId).get()).exists) {
      throw StateError('Unblock this user before sending a message.');
    }

    final currentUserId = currentUser.uid;
    final currentUserEmail = currentUser.email ?? '';

    final sorted = [currentUserId, receiverId]..sort();
    final roomId = getRoomId(currentUserId, receiverId);

    final roomRef = _firestore.collection('chat_rooms').doc(roomId);
    final messageRef = roomRef.collection('messages').doc();

    final batch = _firestore.batch();
    batch.set(roomRef, {'participantIds': sorted}, SetOptions(merge: true));

    batch.set(messageRef, {
      'senderID': currentUserId,
      'senderEmail': currentUserEmail,
      'receiverID': receiverId,
      'message': trimmed,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Send push notification directly to receiver for $0
    try {
      final receiverDoc =
          await _firestore.collection('Users').doc(receiverId).get();
      final receiverToken = receiverDoc.data()?['fcmToken'];
      if (receiverToken != null &&
          receiverToken is String &&
          receiverToken.isNotEmpty) {
        _effectiveNotificationService.sendPushNotification(
          receiverToken: receiverToken,
          title: currentUserEmail,
          body: trimmed,
          data: {
            'senderID': currentUser.uid,
            'senderEmail': currentUserEmail,
            'roomId': roomId,
          },
        );
      }
    } catch (_) {
      // Notification failure should never affect message sending
    }
  }

  /// Streams the latest messages with [receiverId], newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> getMessages(
    String receiverId, {
    int limit = 50,
  }) {
    final currentUserId = _effectiveAuth.currentUser?.uid;
    if (currentUserId == null) {
      return const Stream.empty();
    }

    final roomId = getRoomId(currentUserId, receiverId);
    final clampedLimit = limit.clamp(1, 100);

    return _firestore
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(clampedLimit)
        .snapshots();
  }
}
