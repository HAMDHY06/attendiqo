import 'package:crypto/crypto.dart';

String notificationDeviceHash(String token, String appPackage) =>
    sha256.convert('$appPackage:$token'.codeUnits).toString();

/// Parent/management-safe preference values. Security alerts cannot be disabled.
class NotificationPreferences {
  const NotificationPreferences({
    required this.attendanceEntry, required this.attendanceExit,
    required this.lateAlert, required this.absenceAlert,
    required this.scheduleChange, required this.notices,
    this.securityAlerts = true,
  });
  final bool attendanceEntry, attendanceExit, lateAlert, absenceAlert;
  final bool scheduleChange, notices, securityAlerts;
  NotificationPreferences copyWith({bool? attendanceEntry, bool? attendanceExit,
      bool? lateAlert, bool? absenceAlert, bool? scheduleChange, bool? notices}) =>
      NotificationPreferences(
        attendanceEntry: attendanceEntry ?? this.attendanceEntry,
        attendanceExit: attendanceExit ?? this.attendanceExit,
        lateAlert: lateAlert ?? this.lateAlert, absenceAlert: absenceAlert ?? this.absenceAlert,
        scheduleChange: scheduleChange ?? this.scheduleChange, notices: notices ?? this.notices,
        securityAlerts: true,
      );
  static const defaults = NotificationPreferences(
    attendanceEntry: true, attendanceExit: true, lateAlert: true,
    absenceAlert: true, scheduleChange: true, notices: true,
  );
}

class SafeNotificationRoute {
  const SafeNotificationRoute(this.value);
  final String value;
  static const allowedManagement = {'home', 'myClasses', 'attendance', 'notices', 'profile'};
  static const allowedConnect = {'home', 'attendance', 'notices', 'childProfile', 'profile'};
  static SafeNotificationRoute? parse(String value, {required bool connect}) {
    if ((connect ? allowedConnect : allowedManagement).contains(value)) return SafeNotificationRoute(value);
    return null;
  }
}

class NotificationDeviceRegistration {
  const NotificationDeviceRegistration({required this.token, required this.appPackage,
    required this.platform, required this.appVersion, required this.deviceHash});
  final String token, appPackage, platform, appVersion, deviceHash;
  bool get isValid => token.length >= 32 && token.length <= 4096
      && {'android', 'ios'}.contains(platform) && appPackage.length <= 160
      && appVersion.length <= 80 && deviceHash.length >= 16 && deviceHash.length <= 128;
}
