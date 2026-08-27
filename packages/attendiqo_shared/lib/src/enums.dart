enum UserRole { superAdmin, instituteAdmin, teacher, parent }

/// Lifecycle for an institute-scoped account membership.
///
/// A join code can create only a pending request. It never makes a membership
/// active by itself.
enum InstituteMembershipStatus { pending, active, rejected, suspended, revoked }

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

enum StudentStatus { active, inactive, suspended, leftInstitute }

enum AcademicClassStatus { active, inactive, archived }

enum ScheduleChangeStatus { scheduled, cancelled, completed }

enum ClassStudentAssignmentStatus { active, inactive, completed, removed }

enum Gender { female, male, other, preferNotToSay }

enum AttendanceStatus { present, absent, late, excused }

enum AttendanceEventType { entry, departure }

enum AttendanceSessionStatus { open, closed, cancelled }

enum AttendanceScanMode { entry, departure }

enum ScanMethod { qr, manual, correction }

enum ScannerResultStatus {
  accepted,
  queued,
  invalidQr,
  disabledQr,
  wrongInstitute,
  wrongClass,
  inactiveStudent,
  closedSession,
  duplicateEntry,
  departureBeforeEntry,
  duplicateDeparture,
  cooldown,
  networkError,
  permissionDenied,
  failure,
}

enum AttendanceSyncState { confirmed, queued, conflict }

enum NotificationType { arrival, departure, late, general }

/// Review-only Phase 8 event contract. Delivery requires a trusted backend.
enum PushNotificationEvent {
  parentStudentEntry,
  parentStudentExit,
  parentStudentLate,
  parentAttendanceCorrected,
  classScheduleChanged,
  classCancelled,
  instituteNotice,
  parentLinkCreated,
  parentLinkRevoked,
  teacherAssignmentChanged,
  accountSecurityAlert,
  instituteSuspended,
  instituteReactivated,
  projectionFailure,
  reconciliationFailure,
  backendHealthWarning,
}

enum NotificationPermissionState { unknown, granted, denied, permanentlyDenied }

enum NotificationDeliveryStatus { pending, sent, failed, skipped }

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

enum InstituteStatus { active, suspended, inactive }

enum TeacherStatus { active, disabled, pendingFirstLogin }

enum TeacherPermission {
  canCreateClasses,
  canEditClasses,
  canAddStudents,
  canEditStudents,
  canGenerateQrCodes,
  canTakeAttendance,
  canCorrectAttendance,
  canExportReports,
  canViewParentContacts,
  canSendManualNotifications,
}

enum AuditAction {
  instituteCreated,
  instituteUpdated,
  instituteSuspended,
  instituteActivated,
  instituteAdminCreated,
  instituteAdminDisabled,
  smsSettingChanged,
  pushSettingChanged,
  passwordResetRequested,
  teacherCreated,
  teacherUpdated,
  teacherDisabled,
  teacherReactivated,
  teacherPermissionsChanged,
  teacherPasswordResetRequested,
  teacherFirstLoginCompleted,
  classCreated,
  classUpdated,
  classActivated,
  classDeactivated,
  classArchived,
  classTeacherAssigned,
  classTeacherRemoved,
  classScheduleChanged,
  classScheduleChangeCancelled,
  studentCreated,
  studentUpdated,
  studentActivated,
  studentDeactivated,
  studentSuspended,
  studentMarkedLeft,
  studentAssignedToClass,
  studentRemovedFromClass,
  studentScheduleOverlapConfirmed,
  studentNumberChanged,
  classCodeChanged,
  studentQrRegenerated,
  studentQrDisabled,
  studentQrEnabled,
  attendanceSessionStarted,
  attendanceSessionClosed,
  attendanceSessionCancelled,
  studentEntryRecorded,
  studentDepartureRecorded,
  manualAttendanceRecorded,
  attendanceCorrected,
  duplicateScanRejected,
  invalidQrRejected,
  qrRegenerated,
  qrDisabled,
  qrEnabled,
  attendanceReportExported,
}

enum PasswordResetStatus {
  idle,
  loading,
  success,
  invalidEmail,
  disabledAccount,
  networkError,
  unauthorized,
  failure,
}

enum AuditTargetType {
  institute,
  user,
  teacher,
  academicClass,
  scheduleChange,
  student,
  classStudentAssignment,
  qrToken,
  attendanceSession,
  attendanceRecord,
  attendanceReport,
  smsSettings,
  pushSettings,
}
