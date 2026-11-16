import 'package:chat/components/delete_account_dialog.dart';
import 'package:chat/components/report_dialog.dart';
import 'package:chat/services/auth/auth_service.dart';
import 'package:chat/services/chat/chat_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> openDialog(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () =>
                  showDialog(context: context, builder: (_) => dialog),
              child: const Text('Open'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'alice', email: 'alice@example.com'),
    );
  });

  testWidgets('report form saves details and closes only after submitting', (
    tester,
  ) async {
    await openDialog(
      tester,
      ReportDialog(
        userId: 'bob',
        chatService: ChatService(firestore: firestore, auth: auth),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'Repeated unwanted messages',
    );
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportDialog), findsNothing);
    final reports = await firestore.collection('reports').get();
    expect(reports.docs.single['details'], 'Repeated unwanted messages');
    expect(reports.docs.single['reporterId'], 'alice');
  });

  testWidgets('cancelling a report does not create a report', (tester) async {
    await openDialog(
      tester,
      ReportDialog(
        userId: 'bob',
        chatService: ChatService(firestore: firestore, auth: auth),
      ),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await firestore.collection('reports').get()).docs, isEmpty);
  });

  testWidgets(
    'delete account asks for a password and can be cancelled safely',
    (tester) async {
      await openDialog(
        tester,
        DeleteAccountDialog(
          authService: AuthService(auth: auth, firestore: firestore),
        ),
      );
      expect(
        find.textContaining('sent messages will be permanently deleted'),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter your password.'), findsOneWidget);
      expect(auth.currentUser?.uid, 'alice');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteAccountDialog), findsNothing);
      expect(auth.currentUser?.uid, 'alice');
    },
  );
}
