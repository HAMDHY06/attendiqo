abstract final class FirestoreCollections {
  static const users = 'users';
  static const institutes = 'institutes';
  static const instituteCodes = 'institute_codes';
  static const teacherEmployeeNumbers = 'teacher_employee_numbers';
  static const instituteMembers = 'institute_members';
  static const classes = 'classes';
  static const classCodes = 'class_codes';
  static const classScheduleChanges = 'class_schedule_changes';
  static const students = 'students';
  static const studentNumbers = 'student_numbers';
  static const classStudents = 'class_students';
  static const attendanceSessions = 'attendance_sessions';
  static const attendanceRecords = 'attendance_records';
  static const attendanceCorrections = 'attendance_corrections';
  static const qrTokens = 'qr_tokens';
  static const parentStudentLinks = 'parent_student_links';
  static const parentAccessScopes = 'parent_access_scopes';
  static const parentStudentProfiles = 'parent_student_profiles';
  static const parentClassProfiles = 'parent_class_profiles';
  static const parentAttendanceSummaries = 'parent_attendance_summaries';
  static const institutePublicProfiles = 'institute_public_profiles';
  static const parentNotices = 'parent_notices';
  static const notificationTokens = 'notification_tokens';
  static const notifications = 'notifications';
  static const smsLogs = 'sms_logs';
  static const smsUsage = 'sms_usage';
  static const smsSettings = 'sms_settings';
  static const notificationTemplates = 'notification_templates';
  static const auditLogs = 'audit_logs';
  static const systemSettings = 'system_settings';
}

abstract final class BrandColors {
  static const attendiqoPrimary = 0xFF4338CA;
  static const attendiqoSecondary = 0xFF2563EB;
  static const attendiqoAccent = 0xFF06B6D4;
  static const connectPrimary = 0xFF4F46E5;
  static const connectSecondary = 0xFF8B5CF6;
  static const connectAccent = 0xFF14B8A6;
}

abstract final class DateTimeUtilities {
  static DateTime dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}
