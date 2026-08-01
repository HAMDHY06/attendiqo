import 'enums.dart';

class TeacherPermissions {
  const TeacherPermissions({
    this.canCreateClasses = false,
    this.canEditClasses = false,
    this.canAddStudents = true,
    this.canEditStudents = true,
    this.canGenerateQrCodes = true,
    this.canTakeAttendance = true,
    this.canCorrectAttendance = false,
    this.canExportReports = true,
    this.canViewParentContacts = true,
    this.canSendManualNotifications = false,
  });

  static const fullAccess = TeacherPermissions(
    canCreateClasses: true,
    canEditClasses: true,
    canAddStudents: true,
    canEditStudents: true,
    canGenerateQrCodes: true,
    canTakeAttendance: true,
    canCorrectAttendance: true,
    canExportReports: true,
    canViewParentContacts: true,
    canSendManualNotifications: true,
  );

  static const attendanceAccess = TeacherPermissions(
    canAddStudents: false,
    canEditStudents: false,
    canGenerateQrCodes: false,
    canTakeAttendance: true,
    canExportReports: true,
    canViewParentContacts: false,
  );

  static const noAccess = TeacherPermissions(
    canAddStudents: false,
    canEditStudents: false,
    canGenerateQrCodes: false,
    canTakeAttendance: false,
    canExportReports: false,
    canViewParentContacts: false,
  );

  final bool canCreateClasses;
  final bool canEditClasses;
  final bool canAddStudents;
  final bool canEditStudents;
  final bool canGenerateQrCodes;
  final bool canTakeAttendance;
  final bool canCorrectAttendance;
  final bool canExportReports;
  final bool canViewParentContacts;
  final bool canSendManualNotifications;

  bool allows(TeacherPermission permission) => switch (permission) {
    TeacherPermission.canCreateClasses => canCreateClasses,
    TeacherPermission.canEditClasses => canEditClasses,
    TeacherPermission.canAddStudents => canAddStudents,
    TeacherPermission.canEditStudents => canEditStudents,
    TeacherPermission.canGenerateQrCodes => canGenerateQrCodes,
    TeacherPermission.canTakeAttendance => canTakeAttendance,
    TeacherPermission.canCorrectAttendance => canCorrectAttendance,
    TeacherPermission.canExportReports => canExportReports,
    TeacherPermission.canViewParentContacts => canViewParentContacts,
    TeacherPermission.canSendManualNotifications => canSendManualNotifications,
  };

  TeacherPermissions copyWith({
    bool? canCreateClasses,
    bool? canEditClasses,
    bool? canAddStudents,
    bool? canEditStudents,
    bool? canGenerateQrCodes,
    bool? canTakeAttendance,
    bool? canCorrectAttendance,
    bool? canExportReports,
    bool? canViewParentContacts,
    bool? canSendManualNotifications,
  }) => TeacherPermissions(
    canCreateClasses: canCreateClasses ?? this.canCreateClasses,
    canEditClasses: canEditClasses ?? this.canEditClasses,
    canAddStudents: canAddStudents ?? this.canAddStudents,
    canEditStudents: canEditStudents ?? this.canEditStudents,
    canGenerateQrCodes: canGenerateQrCodes ?? this.canGenerateQrCodes,
    canTakeAttendance: canTakeAttendance ?? this.canTakeAttendance,
    canCorrectAttendance: canCorrectAttendance ?? this.canCorrectAttendance,
    canExportReports: canExportReports ?? this.canExportReports,
    canViewParentContacts: canViewParentContacts ?? this.canViewParentContacts,
    canSendManualNotifications:
        canSendManualNotifications ?? this.canSendManualNotifications,
  );

  Map<String, bool> toMap() => {
    for (final permission in TeacherPermission.values)
      permission.name: allows(permission),
  };

  Set<String> changedKeys(TeacherPermissions other) => {
    for (final permission in TeacherPermission.values)
      if (allows(permission) != other.allows(permission)) permission.name,
  };

  @override
  bool operator ==(Object other) =>
      other is TeacherPermissions && changedKeys(other).isEmpty;

  @override
  int get hashCode => Object.hashAll(
    TeacherPermission.values.map((permission) => allows(permission)),
  );

  static TeacherPermissions? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final values = <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
    final expected = TeacherPermission.values
        .map((value) => value.name)
        .toSet();
    if (values.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(values.keys.toSet()).isNotEmpty ||
        values.values.any((value) => value is! bool)) {
      return null;
    }
    return TeacherPermissions(
      canCreateClasses: values['canCreateClasses']! as bool,
      canEditClasses: values['canEditClasses']! as bool,
      canAddStudents: values['canAddStudents']! as bool,
      canEditStudents: values['canEditStudents']! as bool,
      canGenerateQrCodes: values['canGenerateQrCodes']! as bool,
      canTakeAttendance: values['canTakeAttendance']! as bool,
      canCorrectAttendance: values['canCorrectAttendance']! as bool,
      canExportReports: values['canExportReports']! as bool,
      canViewParentContacts: values['canViewParentContacts']! as bool,
      canSendManualNotifications: values['canSendManualNotifications']! as bool,
    );
  }
}

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
    this.updatedBy,
    this.phoneNumber,
    this.employeeNumber,
    this.permissions,
    this.teacherStatus,
  });

  factory UserProfile.newTeacher({
    required String uid,
    required String email,
    required String displayName,
    required String instituteId,
    required String createdBy,
    required DateTime now,
    String? phoneNumber,
    String? employeeNumber,
    TeacherPermissions permissions = const TeacherPermissions(),
  }) => UserProfile(
    uid: uid,
    email: email.trim().toLowerCase(),
    displayName: displayName.trim(),
    role: UserRole.teacher,
    instituteId: instituteId,
    active: true,
    mustChangePassword: true,
    createdAt: now,
    createdBy: createdBy,
    updatedAt: now,
    updatedBy: createdBy,
    phoneNumber: phoneNumber?.trim().isEmpty == true
        ? null
        : phoneNumber?.trim(),
    employeeNumber: employeeNumber?.trim().isEmpty == true
        ? null
        : employeeNumber?.trim().toUpperCase(),
    permissions: permissions,
    teacherStatus: TeacherStatus.pendingFirstLogin,
  );

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
  final String? updatedBy;
  final String? phoneNumber;
  final String? employeeNumber;
  final TeacherPermissions? permissions;
  final TeacherStatus? teacherStatus;

  bool get isTeacher => role == UserRole.teacher;
  TeacherPermissions get effectiveTeacherPermissions =>
      permissions ?? const TeacherPermissions();
  TeacherStatus? get effectiveTeacherStatus => !isTeacher
      ? null
      : teacherStatus ??
            (!active
                ? TeacherStatus.disabled
                : mustChangePassword
                ? TeacherStatus.pendingFirstLogin
                : TeacherStatus.active);

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
    if (isTeacher) ...{
      'updatedBy': updatedBy ?? createdBy,
      'phoneNumber': phoneNumber,
      'employeeNumber': employeeNumber,
      'permissions': effectiveTeacherPermissions.toMap(),
      'status': effectiveTeacherStatus!.name,
    },
  };

  UserProfile copyWithTeacher({
    String? displayName,
    String? phoneNumber,
    bool clearPhoneNumber = false,
    String? employeeNumber,
    bool clearEmployeeNumber = false,
    bool? active,
    bool? mustChangePassword,
    TeacherPermissions? permissions,
    TeacherStatus? teacherStatus,
    DateTime? updatedAt,
    String? updatedBy,
    DateTime? lastLoginAt,
  }) => UserProfile(
    uid: uid,
    email: email,
    displayName: displayName ?? this.displayName,
    role: role,
    instituteId: instituteId,
    active: active ?? this.active,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    createdAt: createdAt,
    createdBy: createdBy,
    updatedAt: updatedAt ?? this.updatedAt,
    lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    updatedBy: updatedBy ?? this.updatedBy,
    phoneNumber: clearPhoneNumber ? null : phoneNumber ?? this.phoneNumber,
    employeeNumber: clearEmployeeNumber
        ? null
        : employeeNumber ?? this.employeeNumber,
    permissions: permissions ?? this.permissions,
    teacherStatus: teacherStatus ?? this.teacherStatus,
  );

  static UserProfile? tryFromMap(Map<String, Object?> data) {
    final role = UserRoleSerialization.tryParse(data['role']);
    final permissions = data['permissions'] == null
        ? null
        : TeacherPermissions.tryFromMap(data['permissions']);
    final teacherStatus = data['status'] is String
        ? TeacherStatus.values
              .where((value) => value.name == data['status'])
              .firstOrNull
        : null;
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
        (data['lastLoginAt'] != null && data['lastLoginAt'] is! DateTime) ||
        (data['updatedBy'] != null && data['updatedBy'] is! String) ||
        (data['phoneNumber'] != null && data['phoneNumber'] is! String) ||
        (data['employeeNumber'] != null && data['employeeNumber'] is! String) ||
        (data['permissions'] != null && permissions == null) ||
        (data['status'] != null && teacherStatus == null)) {
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
      updatedBy: (data['updatedBy'] as String?) ?? data['createdBy']! as String,
      phoneNumber: data['phoneNumber'] as String?,
      employeeNumber: data['employeeNumber'] as String?,
      permissions: role == UserRole.teacher
          ? permissions ?? const TeacherPermissions()
          : null,
      teacherStatus: role == UserRole.teacher
          ? teacherStatus ??
                (!(data['active']! as bool)
                    ? TeacherStatus.disabled
                    : data['mustChangePassword']! as bool
                    ? TeacherStatus.pendingFirstLogin
                    : TeacherStatus.active)
          : null,
    );
    if (!profile.hasValidInstituteAssignment) return null;
    if (role == UserRole.teacher) {
      final expected = !profile.active
          ? TeacherStatus.disabled
          : profile.mustChangePassword
          ? TeacherStatus.pendingFirstLogin
          : TeacherStatus.active;
      if (profile.email.trim().isEmpty ||
          profile.displayName.trim().isEmpty ||
          profile.effectiveTeacherStatus != expected) {
        return null;
      }
    }
    return profile;
  }
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
