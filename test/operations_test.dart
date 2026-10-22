import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enzeli_admin/main.dart';

class FakeOperationsApi extends ApiClient {
  FakeOperationsApi() : super(token: 'test');
  final calls = <String>[];
  @override
  Future<ApiResponse> get(String path) async {
    calls.add(path);
    if (path.startsWith('/admin/reports')) {
      return ApiResponse(
        data: {
          'month': '2026-10',
          'timezone': 'Asia/Kuwait',
          'subscriptionAccountingNote': 'Credits only',
          'summary': {
            'totalAccounts': 156,
            'registeredUsers': 150,
            'testAccounts': 6,
            'newUsers': 3,
            'monthlyPlayers': 20,
            'matches': 90,
            'achievements': 5,
            'currentVipUsers': 2,
            'subscriptionPurchases': 3,
            'purchasingUsers': 2,
            'creditsCharged': 30,
          },
          'users': <dynamic>[],
        },
      );
    }
    if (path.endsWith('/games')) {
      return ApiResponse(
        data: [
          {
            'id': 'كوت',
            'name': 'كوت',
            'category': 'جنجفة',
            'mainVisible': true,
          },
        ],
      );
    }
    return ApiResponse(
      data: {'maintenanceEnabled': false, 'maintenanceMessage': 'Maintenance'},
    );
  }

  @override
  Future<ApiResponse> patch(String path, {Map<String, dynamic>? body}) async {
    calls.add('$path:$body');
    return ApiResponse(data: {});
  }
}

void main() {
  testWidgets('Admin operations pages fit phone and desktop widths', (
    tester,
  ) async {
    final api = FakeOperationsApi();
    for (final width in [390.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      for (final page in [
        ReportsTab(api: api),
        GameVisibilityTab(api: api),
        MaintenanceTab(api: api),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(padding: const EdgeInsets.all(12), child: page),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    expect(api.calls.any((p) => p.contains('/admin/reports/monthly')), isTrue);
  });
}
