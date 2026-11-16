import 'dart:async';

import 'package:chat/services/chat/chat_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streams users and updates when a profile is added', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ChatService(firestore: firestore);
    final users = StreamIterator(service.getUserStream());
    addTearDown(users.cancel);

    expect(await users.moveNext(), isTrue);
    expect(users.current, isEmpty);

    final profile = {'uid': 'alice', 'email': 'alice@example.com'};
    await firestore.collection('Users').doc('alice').set(profile);

    expect(await users.moveNext(), isTrue);
    expect(users.current, [profile]);
  });
}
