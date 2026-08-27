import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firebase-less notification fallback is safe', () async {
    const service = UnavailableNotificationService();
    expect(
      await service.requestPermission(),
      NotificationPermissionState.unknown,
    );
    expect(await service.openSystemSettings(), isFalse);
    expect(await service.taps.isEmpty, isTrue);
    expect(await service.foregroundRoutes.isEmpty, isTrue);
  });
}
