enum UserRole { superAdmin, instituteAdmin, teacher, parent }

extension UserRoleSerialization on UserRole {
  String get wireName => name;

  static UserRole? tryParse(Object? value) {
    if (value is! String) return null;
    for (final role in UserRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }
}

extension UserRoleAuthorization on UserRole {
  bool get canManageInstitutes => this == UserRole.superAdmin;
  bool get canManageInstitute =>
      this == UserRole.superAdmin || this == UserRole.instituteAdmin;
  bool get canRecordAttendance =>
      this == UserRole.instituteAdmin || this == UserRole.teacher;
  bool get isParent => this == UserRole.parent;
}

enum StudentStatus { active, inactive, archived }

enum AttendanceStatus { present, absent, late, excused }

enum AttendanceEventType { entry, departure }

enum NotificationType { arrival, departure, late, general }

enum SmsMessageType { arrival, departure }

enum SmsDeliveryStatus { pending, sent, delivered, failed, skipped }

enum AppAudience { management, connect }

enum AuthDestination {
  signedOut,
  superAdminDashboard,
  instituteAdminDashboard,
  teacherDashboard,
  parentDashboard,
  changePassword,
}

enum AuthenticationStatus {
  checking,
  authenticating,
  signedOut,
  authenticated,
  mustChangePassword,
  blocked,
  failure,
}

enum AuthFailureCode {
  invalidEmail,
  invalidCredentials,
  userNotFound,
  userDisabled,
  tooManyRequests,
  network,
  permissionDenied,
  missingProfile,
  unsupportedRole,
  inactiveProfile,
  requiresRecentLogin,
  resetFailed,
  unknown,
}
