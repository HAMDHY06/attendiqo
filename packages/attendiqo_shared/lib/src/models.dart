import 'enums.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.instituteId,
    required this.active,
    required this.mustChangePassword,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    this.lastLoginAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final String? instituteId;
  final bool active;
  final bool mustChangePassword;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;

  bool get hasValidInstituteAssignment => switch (role) {
    UserRole.instituteAdmin ||
    UserRole.teacher => instituteId != null && instituteId!.trim().isNotEmpty,
    UserRole.superAdmin => instituteId == null,
    UserRole.parent => true,
  };

  Map<String, Object?> toMap() => {
    'uid': uid,
    'email': email,
    'displayName': displayName,
    'role': role.wireName,
    'instituteId': instituteId,
    'active': active,
    'mustChangePassword': mustChangePassword,
    'createdAt': createdAt,
    'createdBy': createdBy,
    'updatedAt': updatedAt,
    'lastLoginAt': lastLoginAt,
  };

  static UserProfile? tryFromMap(Map<String, Object?> data) {
    final role = UserRoleSerialization.tryParse(data['role']);
    if (role == null ||
        data['uid'] is! String ||
        data['email'] is! String ||
        data['displayName'] is! String ||
        data['active'] is! bool ||
        data['mustChangePassword'] is! bool ||
        data['createdAt'] is! DateTime ||
        data['createdBy'] is! String ||
        data['updatedAt'] is! DateTime ||
        (data['instituteId'] != null && data['instituteId'] is! String) ||
        (data['lastLoginAt'] != null && data['lastLoginAt'] is! DateTime)) {
      return null;
    }
    final profile = UserProfile(
      uid: data['uid']! as String,
      email: data['email']! as String,
      displayName: data['displayName']! as String,
      role: role,
      instituteId: data['instituteId'] as String?,
      active: data['active']! as bool,
      mustChangePassword: data['mustChangePassword']! as bool,
      createdAt: data['createdAt']! as DateTime,
      createdBy: data['createdBy']! as String,
      updatedAt: data['updatedAt']! as DateTime,
      lastLoginAt: data['lastLoginAt'] as DateTime?,
    );
    return profile.hasValidInstituteAssignment ? profile : null;
  }
}

class Student {
  const Student({
    required this.studentId,
    required this.instituteId,
    required this.studentNumber,
    required this.fullName,
    required this.primaryParentName,
    required this.primaryParentMobile,
    this.secondaryParentName,
    this.secondaryParentMobile,
    this.parentEmail,
    required this.status,
    required this.qrToken,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
  });

  final String studentId;
  final String instituteId;
  final String studentNumber;
  final String fullName;
  final String primaryParentName;
  final String primaryParentMobile;
  final String? secondaryParentName;
  final String? secondaryParentMobile;
  final String? parentEmail;
  final StudentStatus status;
  final String qrToken;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
}

class AttendanceSession {
  const AttendanceSession({
    required this.sessionId,
    required this.instituteId,
    required this.classId,
    required this.teacherId,
    required this.mode,
    required this.startedAt,
    this.endedAt,
  });
  final String sessionId;
  final String instituteId;
  final String classId;
  final String teacherId;
  final AttendanceEventType mode;
  final DateTime startedAt;
  final DateTime? endedAt;
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.recordId,
    required this.sessionId,
    required this.instituteId,
    required this.classId,
    required this.studentId,
    required this.status,
    required this.recordedBy,
    required this.deviceIdentifier,
    this.entryAt,
    this.departureAt,
    this.correctedBy,
    this.correctionReason,
  });
  final String recordId;
  final String sessionId;
  final String instituteId;
  final String classId;
  final String studentId;
  final AttendanceStatus status;
  final String recordedBy;
  final String deviceIdentifier;
  final DateTime? entryAt;
  final DateTime? departureAt;
  final String? correctedBy;
  final String? correctionReason;
}

class QrToken {
  const QrToken({
    required this.opaqueToken,
    required this.active,
    required this.createdAt,
  });
  final String opaqueToken;
  final bool active;
  final DateTime createdAt;
}

class FcmToken {
  const FcmToken({
    required this.userId,
    required this.deviceId,
    required this.token,
    required this.updatedAt,
  });
  final String userId;
  final String deviceId;
  final String token;
  final DateTime updatedAt;
}

class DeepLinkTarget {
  const DeepLinkTarget({required this.route, this.arguments = const {}});
  final String route;
  final Map<String, String> arguments;
}

class AttendanceNotification {
  const AttendanceNotification({
    required this.id,
    required this.instituteName,
    required this.studentName,
    required this.className,
    required this.occurredAt,
    required this.type,
    this.deepLink,
  });
  final String id;
  final String instituteName;
  final String studentName;
  final String className;
  final DateTime occurredAt;
  final NotificationType type;
  final DeepLinkTarget? deepLink;
  String get title => instituteName;
}

class ArrivalNotification extends AttendanceNotification {
  const ArrivalNotification({
    required super.id,
    required super.instituteName,
    required super.studentName,
    required super.className,
    required super.occurredAt,
    super.deepLink,
  }) : super(type: NotificationType.arrival);
}

class DepartureNotification extends AttendanceNotification {
  const DepartureNotification({
    required super.id,
    required super.instituteName,
    required super.studentName,
    required super.className,
    required super.occurredAt,
    super.deepLink,
  }) : super(type: NotificationType.departure);
}

class NotificationHistoryItem {
  const NotificationHistoryItem({
    required this.notification,
    required this.createdAt,
    this.readAt,
  });
  final AttendanceNotification notification;
  final DateTime createdAt;
  final DateTime? readAt;
}

class SmsConfiguration {
  const SmsConfiguration({
    this.enabled = false,
    this.monthlyLimit = 0,
    this.blockAfterLimit = true,
  });
  final bool enabled;
  final int monthlyLimit;
  final bool blockAfterLimit;
}

class InstituteSmsSettings {
  const InstituteSmsSettings({
    required this.instituteId,
    this.enabled = false,
    this.arrivalEnabled = true,
    this.departureEnabled = true,
    this.monthlyLimit = 0,
    this.blockAfterLimit = true,
  });
  final String instituteId;
  final bool enabled;
  final bool arrivalEnabled;
  final bool departureEnabled;
  final int monthlyLimit;
  final bool blockAfterLimit;
}

class StudentSmsPreference {
  const StudentSmsPreference({
    required this.studentId,
    this.enabled = false,
    this.consentRecorded = false,
  });
  final String studentId;
  final bool enabled;
  final bool consentRecorded;
}

class SmsUsage {
  const SmsUsage({
    required this.instituteId,
    required this.month,
    this.used = 0,
  });
  final String instituteId;
  final String month;
  final int used;
}

class SmsLog {
  const SmsLog({
    required this.id,
    required this.attendanceEventId,
    required this.type,
    required this.status,
    required this.createdAt,
    this.providerResponse,
    this.failureReason,
  });
  final String id;
  final String attendanceEventId;
  final SmsMessageType type;
  final SmsDeliveryStatus status;
  final DateTime createdAt;
  final String? providerResponse;
  final String? failureReason;
}

class NotificationTemplate {
  const NotificationTemplate({
    required this.instituteId,
    required this.type,
    required this.body,
  });
  final String instituteId;
  final SmsMessageType type;
  final String body;
}

class Failure {
  const Failure(this.message, {this.code});
  final String message;
  final String? code;
}

sealed class Result<T> {
  const Result();
}

class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

class Failed<T> extends Result<T> {
  const Failed(this.failure);
  final Failure failure;
}
