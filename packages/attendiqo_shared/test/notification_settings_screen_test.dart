import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLifecycle implements AppNotificationLifecycle {
  _FakeLifecycle(this.value, {this.opensSettings = true});
  final NotificationPermissionState value;
  final bool opensSettings;
  var requested = false;
  @override
  Future<void> clearForSignOut() async {}
  @override
  Stream<NotificationTapRoute> get foregroundRoutes => const Stream.empty();
  @override
  Future<bool> openSystemSettings() async => opensSettings;
  @override
  Stream<NotificationPermissionState> get permissionStates =>
      const Stream.empty();
  @override
  Future<NotificationPermissionState> requestPermission() async {
    requested = true;
    return value;
  }

  @override
  Future<void> start() async {}
  @override
  Stream<NotificationTapRoute> get taps => const Stream.empty();
}

void main() {
  testWidgets('denied permissions show safe system-settings guidance', (
    tester,
  ) async {
    final service = _FakeLifecycle(NotificationPermissionState.denied);
    await tester.pumpWidget(
      MaterialApp(home: NotificationSettingsScreen(service: service)),
    );
    await tester.tap(find.text('Request permission'));
    await tester.pump();
    expect(service.requested, isTrue);
    expect(find.text('Open system settings'), findsOneWidget);
    expect(
      find.text('Security alerts are required and cannot be turned off.'),
      findsOneWidget,
    );
  });

  testWidgets('settings failure displays a safe error', (tester) async {
    final service = _FakeLifecycle(
      NotificationPermissionState.permanentlyDenied,
      opensSettings: false,
    );
    await tester.pumpWidget(
      MaterialApp(home: NotificationSettingsScreen(service: service)),
    );
    await tester.tap(find.text('Request permission'));
    await tester.pump();
    await tester.tap(find.text('Open system settings'));
    await tester.pump();
    expect(
      find.text('System notification settings are unavailable on this device.'),
      findsOneWidget,
    );
  });
}
