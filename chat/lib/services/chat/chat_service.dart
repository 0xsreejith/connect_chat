import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  ChatService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _customAuth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth? _customAuth;

  FirebaseAuth get _effectiveAuth => _customAuth ?? FirebaseAuth.instance;

  /// Live public profiles ordered by email.
  Stream<List<Map<String, dynamic>>> getUserStream() {
    return _firestore.collection('Users').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()).toList();
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
    final currentUser = _effectiveAuth.currentUser;
    if (currentUser == null) {
      throw StateError('User must be authenticated to send messages.');
    }

    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > 4000) {
      throw ArgumentError(
        'Message exceeds maximum length of 4000 characters.',
      );
    }

    final currentUserId = currentUser.uid;
    final currentUserEmail = currentUser.email ?? '';

    final sorted = [currentUserId, receiverId]..sort();
    final roomId = getRoomId(currentUserId, receiverId);

    final roomRef = _firestore.collection('chat_rooms').doc(roomId);
    final messageRef = roomRef.collection('messages').doc();

    final batch = _firestore.batch();
    batch.set(roomRef, {
      'participantIds': sorted,
    }, SetOptions(merge: true));

    batch.set(messageRef, {
      'senderID': currentUserId,
      'senderEmail': currentUserEmail,
      'receiverID': receiverId,
      'message': trimmed,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await batch.commit();
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
