import 'package:chat/services/auth/auth_service.dart';
import 'package:chat/services/chat/chat_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late MockUser user;
  late MockFirebaseAuth auth;
  late ChatService chat;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    user = MockUser(uid: 'alice', email: 'alice@example.com');
    auth = MockFirebaseAuth(signedIn: true, mockUser: user);
    chat = ChatService(firestore: firestore, auth: auth);
  });

  test(
    'blocking persists privately, prevents sending and supports unblocking',
    () async {
      await chat.blockUser('bob', 'bob@example.com');
      expect((await chat.getBlockedUsers().first).single['userId'], 'bob');
      expect(
        (await firestore.collection('Users').doc('bob').get()).exists,
        isFalse,
      );
      await expectLater(chat.sendMessage('bob', 'Hello'), throwsStateError);
      expect((await firestore.collection('chat_rooms').get()).docs, isEmpty);

      await chat.unblockUser('bob');
      expect(await chat.getBlockedUsers().first, isEmpty);
      await chat.sendMessage('bob', 'Hello again');
      expect(
        (await chat.getMessages('bob').first).docs.single['message'],
        'Hello again',
      );
    },
  );

  test(
    'reports identify the signed-in reporter and preserve message references',
    () async {
      await chat.reportUser(
        'bob',
        reason: 'Harassment',
        details: '  Repeated insults  ',
        messageId: 'message-1',
      );
      final report = (await firestore.collection('reports').get()).docs.single
          .data();
      expect(report['reporterId'], 'alice');
      expect(report['reportedUserId'], 'bob');
      expect(report['roomId'], ChatService.getRoomId('alice', 'bob'));
      expect(report['messageId'], 'message-1');
      expect(report['details'], 'Repeated insults');
      expect(report['status'], 'pending');
      await expectLater(
        chat.reportUser('alice', reason: 'Harassment'),
        throwsArgumentError,
      );
      await expectLater(
        chat.reportUser('bob', reason: 'Unknown'),
        throwsArgumentError,
      );
      await expectLater(
        chat.blockUser('alice', 'alice@example.com'),
        throwsArgumentError,
      );
    },
  );

  test('account actions require authentication', () async {
    await auth.signOut();
    await expectLater(
      chat.blockUser('bob', 'bob@example.com'),
      throwsStateError,
    );
    await expectLater(
      chat.reportUser('bob', reason: 'Other'),
      throwsStateError,
    );
    await expectLater(
      AuthService(auth: auth, firestore: firestore).deleteAccount('password'),
      throwsStateError,
    );
  });

  test('wrong password prevents deletion from reaching the server', () async {
    final functions = _Functions();
    final wrongUser = MockUser(
      uid: 'wrong-password-user',
      email: 'wrong@example.com',
    );
    final wrongAuth = MockFirebaseAuth(signedIn: true, mockUser: wrongUser);
    whenCalling(Invocation.method(#reauthenticateWithCredential, null))
        .on(wrongUser)
        .thenThrow(FirebaseAuthException(code: 'wrong-password'));
    final service = AuthService(
      auth: wrongAuth,
      firestore: firestore,
      functions: functions,
    );
    await expectLater(
      service.deleteAccount('incorrect'),
      throwsA(isA<FirebaseAuthException>()),
    );
    expect(functions.calls, 0);
    expect(wrongAuth.currentUser?.uid, 'wrong-password-user');
  });

  test('failed server cleanup keeps the session available for retry', () async {
    final functions = _Functions()
      ..failure = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Offline',
      );
    final service = AuthService(
      auth: auth,
      firestore: firestore,
      functions: functions,
    );
    await expectLater(
      service.deleteAccount('password'),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    expect(auth.currentUser?.uid, 'alice');
  });

  test(
    'successful server cleanup signs out and never accepts a target account ID',
    () async {
      final functions = _Functions();
      await AuthService(
        auth: auth,
        firestore: firestore,
        functions: functions,
      ).deleteAccount('password');
      expect(functions.calls, 1);
      expect(auth.currentUser, isNull);
    },
  );
}

class _Functions implements FirebaseFunctions {
  int calls = 0;
  Object? failure;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    expect(name, 'deleteAccount');
    return _Callable(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Callable implements HttpsCallable {
  _Callable(this.functions);
  final _Functions functions;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    expect(parameters, isNull);
    functions.calls++;
    if (functions.failure != null) throw functions.failure!;
    return _Result<T>({'deleted': true} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Result<T> implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}
