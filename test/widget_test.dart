// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:enzeli_admin/main.dart';

void main() {
  testWidgets('Admin app renders login screen', (WidgetTester tester) async {
    final auth = AuthState()..loading = false; // skip async load for test

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthState>.value(
        value: auth,
        child: const AdminApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Admin Enzily'), findsOneWidget);
    expect(find.text('Log in (admin)'), findsOneWidget);
  });
}
