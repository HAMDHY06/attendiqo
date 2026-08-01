abstract final class FirestoreCollections {
  static const users = 'users';
  static const institutes = 'institutes';
  static const instituteMembers = 'institute_members';
  static const classes = 'classes';
  static const students = 'students';
  static const classStudents = 'class_students';
  static const attendanceSessions = 'attendance_sessions';
  static const attendanceRecords = 'attendance_records';
  static const parentStudentLinks = 'parent_student_links';
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
