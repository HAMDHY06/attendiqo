import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification routes are allowlisted per app and reject scoped payload IDs', () {
    expect(NotificationTapRoute.parse({'route': 'attendance'}, connect: true)?.destination, 'attendance');
    expect(NotificationTapRoute.parse({'route': 'monitoring'}, connect: false)?.destination, 'monitoring');
    expect(NotificationTapRoute.parse({'route': 'audit'}, connect: true), isNull);
    expect(NotificationTapRoute.parse({'route': 'childProfile', 'studentId': 'forged'}, connect: true), isNull);
  });
}
