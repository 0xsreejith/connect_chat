import 'package:chat/services/auth/login_or_register.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('login and registration screens can be toggled', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginOrRegister()));
    expect(find.text('Login'), findsOneWidget);

    await tester.tap(find.text('Register now'));
    await tester.pumpAndSettle();
    expect(find.text('Register'), findsOneWidget);

    await tester.tap(find.text('Login now'));
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
  });
}
