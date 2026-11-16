import 'package:chat/services/auth/auth_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

void main() {
  for (final register in [true, false]) {
    test(
      '${register ? 'registration' : 'login'} saves an authenticated public profile',
      () async {
        final firestore = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(
          mockUser: MockUser(
            uid: 'alice',
            email: 'alice@example.com',
            displayName: 'Alice',
          ),
        );
        final service = AuthService(auth: auth, firestore: firestore);
        if (register) {
          await service.signUpWithEmailPassword(
            'alice@example.com',
            'a-password',
          );
        } else {
          await service.signInWithEmailPassword(
            'alice@example.com',
            'a-password',
          );
        }

        final user = auth.currentUser!;
        final profile = await firestore.collection('Users').doc(user.uid).get();
        expect(profile.data(), {
          'uid': user.uid,
          'email': 'alice@example.com',
          'displayName': user.displayName,
        });
      },
    );
  }

  test('a profile write failure preserves successful authentication', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'alice', email: 'alice@example.com'),
    );
    final profile = firestore.collection('Users').doc('alice');
    whenCalling(Invocation.method(#set, null))
        .on(profile)
        .thenThrow(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        );
    final service = AuthService(auth: auth, firestore: firestore);

    await expectLater(
      service.signInWithEmailPassword('alice@example.com', 'a-password'),
      throwsA(
        isA<FirebaseException>()
            .having(
              (error) => error is FirebaseAuthException,
              'auth failure',
              isFalse,
            )
            .having((error) => error.code, 'code', 'permission-denied')
            .having(
              (error) => error.message,
              'message',
              contains('You are signed in'),
            ),
      ),
    );
    expect(auth.currentUser?.uid, 'alice');
    expect((await profile.get()).exists, isFalse);
  });
}
