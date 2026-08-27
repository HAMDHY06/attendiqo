class ParentStudentLink {
  const ParentStudentLink({
    required this.parentUid,
    required this.studentId,
    required this.instituteId,
    required this.relationship,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.sourceVersion,
    this.revokedAt,
    this.revokedBy,
  });
  final String parentUid;
  final String studentId;
  final String instituteId;
  final String relationship;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final DateTime? revokedAt;
  final String? revokedBy;
  final int sourceVersion;
  String get linkId => '${parentUid}_$studentId';
}

class ParentStudentProfile {
  const ParentStudentProfile({
    required this.studentId,
    required this.instituteId,
    required this.fullName,
    required this.studentNumber,
    required this.grade,
    required this.active,
    this.classNames = const [],
    this.classIds = const [],
    this.publicProfileImageUrl,
    required this.updatedAt,
    required this.sourceVersion,
  });
  final String studentId;
  final String instituteId;
  final String fullName;
  final String studentNumber;
  final String? grade;
  final bool active;
  final List<String> classNames;
  final List<String> classIds;
  final String? publicProfileImageUrl;
  final DateTime updatedAt;
  final int sourceVersion;
}

class ParentClassProfile {
  const ParentClassProfile({
    required this.classId,
    required this.instituteId,
    required this.className,
    required this.subject,
    required this.active,
    required this.updatedAt,
    required this.sourceVersion,
    this.grade,
    this.teacherDisplayName,
    this.room,
    this.normalSchedule = const {},
    this.effectiveSchedule,
  });
  final String classId;
  final String instituteId;
  final String className;
  final String subject;
  final String? grade;
  final String? teacherDisplayName;
  final String? room;
  final Map<String, Object?> normalSchedule;
  final Map<String, Object?>? effectiveSchedule;
  final bool active;
  final DateTime updatedAt;
  final int sourceVersion;
}

class ParentAttendanceSummary {
  const ParentAttendanceSummary({
    required this.summaryId,
    required this.studentId,
    required this.instituteId,
    required this.classId,
    required this.attendanceDate,
    required this.status,
    required this.late,
    required this.currentPresenceState,
    required this.updatedAt,
    required this.sourceVersion,
    this.entryTime,
    this.exitTime,
  });
  final String summaryId;
  final String studentId;
  final String instituteId;
  final String classId;
  final DateTime attendanceDate;
  final String status;
  final DateTime? entryTime;
  final DateTime? exitTime;
  final bool late;
  final String currentPresenceState;
  final DateTime updatedAt;
  final int sourceVersion;
}

class InstitutePublicProfile {
  const InstitutePublicProfile({
    required this.instituteId,
    required this.displayName,
    required this.status,
    required this.updatedAt,
    required this.sourceVersion,
    this.logoUrl,
    this.publicPhone,
    this.publicEmail,
    this.publicAddress,
  });
  final String instituteId;
  final String displayName;
  final String status;
  final DateTime updatedAt;
  final int sourceVersion;
  final String? logoUrl;
  final String? publicPhone;
  final String? publicEmail;
  final String? publicAddress;
}

enum ParentNoticePriority { normal, important }

enum ParentNoticeTargetType { instituteParents, student, classTarget }

class ParentNotice {
  const ParentNotice({
    required this.noticeId,
    required this.instituteId,
    required this.title,
    required this.message,
    required this.publishedAt,
    required this.priority,
    required this.active,
    required this.targetType,
    required this.updatedAt,
    required this.sourceVersion,
    this.targetStudentIds = const [],
    this.targetClassIds = const [],
    this.expiresAt,
  });
  final String noticeId;
  final String instituteId;
  final String title;
  final String message;
  final DateTime publishedAt;
  final ParentNoticePriority priority;
  final DateTime? expiresAt;
  final bool active;
  final ParentNoticeTargetType targetType;
  final List<String> targetStudentIds;
  final List<String> targetClassIds;
  final DateTime updatedAt;
  final int sourceVersion;
}

abstract interface class ParentConnectRepository {
  Future<List<ParentStudentLink>> fetchActiveLinks(String parentUid);
  Future<List<ParentStudentProfile>> fetchChildProfiles(
    List<ParentStudentLink> links,
  );
  Future<InstitutePublicProfile?> fetchInstitutePublicProfile(
    String instituteId,
  );
  Future<List<ParentNotice>> fetchNotices(List<ParentStudentLink> links);
}
