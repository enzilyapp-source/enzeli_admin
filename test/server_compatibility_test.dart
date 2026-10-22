import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:enzeli_admin/main.dart';

void main() {
  test('Unpublished admin routes return an actionable version error', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'message': 'Cannot GET ${request.url.path}',
          'statusCode': 404,
        }),
        404,
        headers: {'content-type': 'application/json'},
      ),
    );
    final api = ApiClient(token: 'existing-session', client: client);
    for (final path in [
      '/admin/operations',
      '/admin/reports/monthly?month=2026-10',
    ]) {
      final response = await api.get(path);
      expect(response.code, 'SERVER_UPDATE_REQUIRED');
      expect(response.statusCode, 404);
      expect(response.error, contains('نشر تحديث السيرفر'));
      expect(response.error, isNot(contains('Cannot GET')));
    }
    final write = await api.patch(
      '/admin/operations/maintenance',
      body: {'enabled': false},
    );
    expect(write.code, 'SERVER_UPDATE_REQUIRED');
    client.close();
  });

  testWidgets('Unknown maintenance state cannot be saved or toggled', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'message': 'Cannot GET /api/admin/operations'}),
        404,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MaintenanceTab(
            api: ApiClient(token: 'existing-session', client: client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('نشر تحديث السيرفر'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'حفظ'))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });
}
