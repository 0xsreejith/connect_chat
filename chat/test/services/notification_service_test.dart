import 'package:chat/services/notifications/notification_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saveTokenToDatabase saves fcmToken to user document', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'user123',
        email: 'user@example.com',
      ),
      signedIn: true,
    );

    // Initial user document
    await firestore.collection('Users').doc('user123').set({
      'uid': 'user123',
      'email': 'user@example.com',
    });

    final service = NotificationService(
      firestore: firestore,
      auth: auth,
    );

    await service.saveTokenToDatabase('test-fcm-token-abc');

    final doc = await firestore.collection('Users').doc('user123').get();
    expect(doc.data()?['fcmToken'], 'test-fcm-token-abc');
  });

  test('clearToken removes fcmToken from user document', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'user123',
        email: 'user@example.com',
      ),
      signedIn: true,
    );

    // Initial user document with fcmToken
    await firestore.collection('Users').doc('user123').set({
      'uid': 'user123',
      'email': 'user@example.com',
      'fcmToken': 'test-fcm-token-abc',
    });

    final service = NotificationService(
      firestore: firestore,
      auth: auth,
    );

    await service.clearToken();

    final doc = await firestore.collection('Users').doc('user123').get();
    expect(doc.data()?.containsKey('fcmToken'), false);
  });

  test('sendPushNotification completes safely when service account file is not present', () async {
    final service = NotificationService();
    await expectLater(
      service.sendPushNotification(
        receiverToken: 'fake-token',
        title: 'Alice',
        body: 'Hello',
        data: {'senderID': 'alice'},
      ),
      completes,
    );
  });
}
