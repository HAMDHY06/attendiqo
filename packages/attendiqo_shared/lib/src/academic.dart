import 'enums.dart';
import 'institute.dart';
import 'models.dart';
import 'validation.dart';

enum ClassWeekday {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday,
}

class LocalTime implements Comparable<LocalTime> {
  const LocalTime(this.hour, this.minute)
    : assert(hour >= 0 && hour <= 23),
      assert(minute >= 0 && minute <= 59);

  final int hour;
  final int minute;
  int get minutesSinceMidnight => hour * 60 + minute;
  String get wireValue =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static LocalTime? tryParse(Object? value) {
    if (value is! String || !RegExp(r'^\d{2}:\d{2}$').hasMatch(value)) {
      return null;
    }
    final parts = value.split(':').map(int.parse).toList();
    if (parts[0] > 23 || parts[1] > 59) return null;
    return LocalTime(parts[0], parts[1]);
  }

  @override
  int compareTo(LocalTime other) =>
      minutesSinceMidnight.compareTo(other.minutesSinceMidnight);
}

class AcademicClass {
  const AcademicClass({
    required this.classId,
    required this.instituteId,
    required this.classCode,
    required this.name,
    required this.subject,
    required this.grade,
    required this.description,
    required this.primaryTeacherId,
    required this.teacherIds,
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    required this.roomOrLocation,
    required this.academicYear,
    required this.active,
    required this.status,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
  });

  factory AcademicClass.newClass({
    required String classId,
    required String instituteId,
    required String classCode,
    required String name,
    required String subject,
    String? grade,
    String description = '',
    String? primaryTeacherId,
    List<String> teacherIds = const [],
    Set<ClassWeekday> daysOfWeek = const {},
    required LocalTime startTime,
    required LocalTime endTime,
    String roomOrLocation = '',
    required int academicYear,
    required DateTime now,
    required String actorUid,
  }) => AcademicClass(
    classId: classId,
    instituteId: instituteId,
    classCode: ClassCodeValidator.normalize(classCode),
    name: name.trim(),
    subject: subject.trim(),
    grade: grade?.trim().isEmpty == true ? null : grade?.trim(),
    description: description.trim(),
    primaryTeacherId: primaryTeacherId,
    teacherIds: List.unmodifiable(teacherIds.toSet()),
    daysOfWeek: Set.unmodifiable(daysOfWeek),
    startTime: startTime,
    endTime: endTime,
    roomOrLocation: roomOrLocation.trim(),
    academicYear: academicYear,
    active: true,
    status: AcademicClassStatus.active,
    createdAt: now,
    createdBy: actorUid,
    updatedAt: now,
    updatedBy: actorUid,
  );

  final String classId;
  final String instituteId;
  final String classCode;
  final String name;
  final String subject;
  final String? grade;
  final String description;
  final String? primaryTeacherId;
  final List<String> teacherIds;
  final Set<ClassWeekday> daysOfWeek;
  final LocalTime startTime;
  final LocalTime endTime;
  final String roomOrLocation;
  final int academicYear;
  final bool active;
  final AcademicClassStatus status;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;
  String get scheduleLabel =>
      '${daysOfWeek.map((e) => e.name.substring(0, 3)).join(', ')} • ${startTime.wireValue}–${endTime.wireValue}';

  bool get canStartAttendance =>
      active && status == AcademicClassStatus.active && teacherIds.isNotEmpty;

  String? validate() {
    if (instituteId.trim().isEmpty) return 'Institute is required';
    final codeError = ClassCodeValidator.validate(classCode);
    if (codeError != null) return codeError;
    final nameError = FieldValidators.required(name, label: 'Class name');
    if (nameError != null) return nameError;
    final subjectError = FieldValidators.required(subject, label: 'Subject');
    if (subjectError != null) return subjectError;
    if (endTime.compareTo(startTime) <= 0) {
      return 'End time must be after start time';
    }
    if (primaryTeacherId != null && !teacherIds.contains(primaryTeacherId)) {
      return 'Primary teacher must be assigned to the class';
    }
    return null;
  }

  AcademicClass copyWith({
    String? name,
    String? subject,
    String? grade,
    bool clearGrade = false,
    String? description,
    String? primaryTeacherId,
    bool clearPrimaryTeacher = false,
    List<String>? teacherIds,
    Set<ClassWeekday>? daysOfWeek,
    LocalTime? startTime,
    LocalTime? endTime,
    String? roomOrLocation,
    int? academicYear,
    bool? active,
    AcademicClassStatus? status,
    DateTime? updatedAt,
    String? updatedBy,
  }) => AcademicClass(
    classId: classId,
    instituteId: instituteId,
    classCode: classCode,
    name: name ?? this.name,
    subject: subject ?? this.subject,
    grade: clearGrade ? null : grade ?? this.grade,
    description: description ?? this.description,
    primaryTeacherId: clearPrimaryTeacher
        ? null
        : primaryTeacherId ?? this.primaryTeacherId,
    teacherIds: List.unmodifiable(teacherIds ?? this.teacherIds),
    daysOfWeek: Set.unmodifiable(daysOfWeek ?? this.daysOfWeek),
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    roomOrLocation: roomOrLocation ?? this.roomOrLocation,
    academicYear: academicYear ?? this.academicYear,
    active: active ?? this.active,
    status: status ?? this.status,
    createdAt: createdAt,
    createdBy: createdBy,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );

  Map<String, Object?> toMap() => {
    'classId': classId,
    'instituteId': instituteId,
    'classCode': classCode,
    'name': name,
    'subject': subject,
    'grade': grade,
    'description': description,
    'primaryTeacherId': primaryTeacherId,
    'teacherIds': teacherIds,
    'daysOfWeek': daysOfWeek.map((value) => value.name).toList(),
    'startTime': startTime.wireValue,
    'endTime': endTime.wireValue,
    'roomOrLocation': roomOrLocation,
    'academicYear': academicYear,
    'active': active,
    'status': status.name,
    'createdAt': createdAt,
    'createdBy': createdBy,
    'updatedAt': updatedAt,
    'updatedBy': updatedBy,
  };

  static AcademicClass? tryFromMap(Map<String, Object?> data) {
    final start = LocalTime.tryParse(data['startTime']);
    final end = LocalTime.tryParse(data['endTime']);
    final status = AcademicClassStatus.values
        .where((e) => e.name == data['status'])
        .firstOrNull;
    final teacherIds = (data['teacherIds'] as List?)
        ?.whereType<String>()
        .toList();
    final dayNames = (data['daysOfWeek'] as List?)
        ?.whereType<String>()
        .toList();
    final days = dayNames
        ?.map(
          (name) =>
              ClassWeekday.values.where((e) => e.name == name).firstOrNull,
        )
        .toList();
    if (data['classId'] is! String ||
        data['instituteId'] is! String ||
        data['classCode'] is! String ||
        data['name'] is! String ||
        data['subject'] is! String ||
        data['description'] is! String ||
        teacherIds == null ||
        dayNames == null ||
        days!.contains(null) ||
        start == null ||
        end == null ||
        data['roomOrLocation'] is! String ||
        data['academicYear'] is! int ||
        data['active'] is! bool ||
        status == null ||
        data['createdAt'] is! DateTime ||
        data['createdBy'] is! String ||
        data['updatedAt'] is! DateTime ||
        data['updatedBy'] is! String) {
      return null;
    }
    final result = AcademicClass(
      classId: data['classId']! as String,
      instituteId: data['instituteId']! as String,
      classCode: data['classCode']! as String,
      name: data['name']! as String,
      subject: data['subject']! as String,
      grade: data['grade'] as String?,
      description: data['description']! as String,
      primaryTeacherId: data['primaryTeacherId'] as String?,
      teacherIds: teacherIds,
      daysOfWeek: days.whereType<ClassWeekday>().toSet(),
      startTime: start,
      endTime: end,
      roomOrLocation: data['roomOrLocation']! as String,
      academicYear: data['academicYear']! as int,
      active: data['active']! as bool,
      status: status,
      createdAt: data['createdAt']! as DateTime,
      createdBy: data['createdBy']! as String,
      updatedAt: data['updatedAt']! as DateTime,
      updatedBy: data['updatedBy']! as String,
    );
    return result.validate() == null &&
            result.active == (result.status == AcademicClassStatus.active)
        ? result
        : null;
  }
}

class ClassScheduleChange {
  const ClassScheduleChange({
    required this.scheduleChangeId,
    required this.instituteId,
    required this.classId,
    required this.effectiveDate,
    required this.oldStartTime,
    required this.oldEndTime,
    required this.newStartTime,
    required this.newEndTime,
    required this.oldRoomOrLocation,
    required this.newRoomOrLocation,
    required this.reason,
    required this.status,
    required this.changedBy,
    required this.changedAt,
    required this.updatedAt,
  });
  final String scheduleChangeId;
  final String instituteId;
  final String classId;
  final DateTime effectiveDate;
  final LocalTime oldStartTime;
  final LocalTime oldEndTime;
  final LocalTime newStartTime;
  final LocalTime newEndTime;
  final String oldRoomOrLocation;
  final String newRoomOrLocation;
  final String reason;
  final ScheduleChangeStatus status;
  final String changedBy;
  final DateTime changedAt;
  final DateTime updatedAt;

  String? validate() {
    if (FieldValidators.required(reason, label: 'Reason') != null) {
      return 'Reason is required';
    }
    if (newEndTime.compareTo(newStartTime) <= 0) {
      return 'New end time must be after start time';
    }
    return null;
  }

  ClassScheduleChange cancel(DateTime now) => ClassScheduleChange(
    scheduleChangeId: scheduleChangeId,
    instituteId: instituteId,
    classId: classId,
    effectiveDate: effectiveDate,
    oldStartTime: oldStartTime,
    oldEndTime: oldEndTime,
    newStartTime: newStartTime,
    newEndTime: newEndTime,
    oldRoomOrLocation: oldRoomOrLocation,
    newRoomOrLocation: newRoomOrLocation,
    reason: reason,
    status: ScheduleChangeStatus.cancelled,
    changedBy: changedBy,
    changedAt: changedAt,
    updatedAt: now,
  );

  Map<String, Object?> toMap() => {
    'scheduleChangeId': scheduleChangeId,
    'instituteId': instituteId,
    'classId': classId,
    'effectiveDate': effectiveDate,
    'oldStartTime': oldStartTime.wireValue,
    'oldEndTime': oldEndTime.wireValue,
    'newStartTime': newStartTime.wireValue,
    'newEndTime': newEndTime.wireValue,
    'oldRoomOrLocation': oldRoomOrLocation,
    'newRoomOrLocation': newRoomOrLocation,
    'reason': reason,
    'status': status.name,
    'changedBy': changedBy,
    'changedAt': changedAt,
    'updatedAt': updatedAt,
  };

  static ClassScheduleChange? tryFromMap(Map<String, Object?> data) {
    final oldStart = LocalTime.tryParse(data['oldStartTime']);
    final oldEnd = LocalTime.tryParse(data['oldEndTime']);
    final newStart = LocalTime.tryParse(data['newStartTime']);
    final newEnd = LocalTime.tryParse(data['newEndTime']);
    final status = ScheduleChangeStatus.values
        .where((e) => e.name == data['status'])
        .firstOrNull;
    if (data['scheduleChangeId'] is! String ||
        data['instituteId'] is! String ||
        data['classId'] is! String ||
        data['effectiveDate'] is! DateTime ||
        oldStart == null ||
        oldEnd == null ||
        newStart == null ||
        newEnd == null ||
        data['oldRoomOrLocation'] is! String ||
        data['newRoomOrLocation'] is! String ||
        data['reason'] is! String ||
        status == null ||
        data['changedBy'] is! String ||
        data['changedAt'] is! DateTime ||
        data['updatedAt'] is! DateTime) {
      return null;
    }
    return ClassScheduleChange(
      scheduleChangeId: data['scheduleChangeId']! as String,
      instituteId: data['instituteId']! as String,
      classId: data['classId']! as String,
      effectiveDate: data['effectiveDate']! as DateTime,
      oldStartTime: oldStart,
      oldEndTime: oldEnd,
      newStartTime: newStart,
      newEndTime: newEnd,
      oldRoomOrLocation: data['oldRoomOrLocation']! as String,
      newRoomOrLocation: data['newRoomOrLocation']! as String,
      reason: data['reason']! as String,
      status: status,
      changedBy: data['changedBy']! as String,
      changedAt: data['changedAt']! as DateTime,
      updatedAt: data['updatedAt']! as DateTime,
    );
  }
}

class EffectiveClassSchedule {
  const EffectiveClassSchedule({
    required this.startTime,
    required this.endTime,
    required this.roomOrLocation,
    this.scheduleChangeId,
  });
  final LocalTime startTime;
  final LocalTime endTime;
  final String roomOrLocation;
  final String? scheduleChangeId;
  bool get isTemporary => scheduleChangeId != null;
}

abstract final class ClassScheduleResolver {
  static EffectiveClassSchedule resolve(
    AcademicClass value,
    DateTime date,
    Iterable<ClassScheduleChange> changes,
  ) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final activeChange = changes
        .where(
          (change) =>
              change.classId == value.classId &&
              change.status == ScheduleChangeStatus.scheduled &&
              DateTime.utc(
                    change.effectiveDate.year,
                    change.effectiveDate.month,
                    change.effectiveDate.day,
                  ) ==
                  day,
        )
        .firstOrNull;
    return activeChange == null
        ? EffectiveClassSchedule(
            startTime: value.startTime,
            endTime: value.endTime,
            roomOrLocation: value.roomOrLocation,
          )
        : EffectiveClassSchedule(
            startTime: activeChange.newStartTime,
            endTime: activeChange.newEndTime,
            roomOrLocation: activeChange.newRoomOrLocation,
            scheduleChangeId: activeChange.scheduleChangeId,
          );
  }
}

class Student {
  const Student({
    required this.studentId,
    required this.instituteId,
    required this.studentNumber,
    required this.fullName,
    this.preferredName,
    this.dateOfBirth,
    this.gender,
    this.address = '',
    required this.primaryParentName,
    required this.primaryParentMobile,
    this.secondaryParentName,
    this.secondaryParentMobile,
    this.parentEmail,
    this.emergencyContactName,
    this.emergencyContactMobile,
    required this.status,
    this.active = true,
    required this.qrToken,
    this.qrVersion = 1,
    this.qrEnabled = true,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    String? updatedBy,
  }) : updatedBy = updatedBy ?? createdBy;
  final String studentId;
  final String instituteId;
  final String studentNumber;
  final String fullName;
  final String? preferredName;
  final DateTime? dateOfBirth;
  final Gender? gender;
  final String address;
  final String primaryParentName;
  final String primaryParentMobile;
  final String? secondaryParentName;
  final String? secondaryParentMobile;
  final String? parentEmail;
  final String? emergencyContactName;
  final String? emergencyContactMobile;
  final StudentStatus status;
  final bool active;
  final String qrToken;
  final int qrVersion;
  final bool qrEnabled;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;
  bool get scannerEligible =>
      active && status == StudentStatus.active && qrEnabled;

  String? validate() {
    final numberError = StudentNumberValidator.validate(studentNumber);
    if (numberError != null) return numberError;
    final nameError = FieldValidators.required(fullName, label: 'Full name');
    if (nameError != null) return nameError;
    final parentError = FieldValidators.required(
      primaryParentName,
      label: 'Primary parent name',
    );
    if (parentError != null) return parentError;
    final mobileError = MobileNumberValidator.validatePrimary(
      primaryParentMobile,
    );
    if (mobileError != null) return mobileError;
    final secondaryError = MobileNumberValidator.validateSecondary(
      secondaryParentMobile,
    );
    if (secondaryError != null) return secondaryError;
    final emergencyError = MobileNumberValidator.validateSecondary(
      emergencyContactMobile,
    );
    if (emergencyError != null) return emergencyError;
    return FieldValidators.optionalEmail(parentEmail);
  }

  Student copyWith({
    String? studentNumber,
    String? fullName,
    String? preferredName,
    bool clearPreferredName = false,
    DateTime? dateOfBirth,
    bool clearDateOfBirth = false,
    Gender? gender,
    bool clearGender = false,
    String? address,
    String? primaryParentName,
    String? primaryParentMobile,
    String? secondaryParentName,
    bool clearSecondaryParentName = false,
    String? secondaryParentMobile,
    bool clearSecondaryParentMobile = false,
    String? parentEmail,
    bool clearParentEmail = false,
    String? emergencyContactName,
    bool clearEmergencyContactName = false,
    String? emergencyContactMobile,
    bool clearEmergencyContactMobile = false,
    StudentStatus? status,
    bool? active,
    String? qrToken,
    int? qrVersion,
    bool? qrEnabled,
    DateTime? updatedAt,
    String? updatedBy,
  }) => Student(
    studentId: studentId,
    instituteId: instituteId,
    studentNumber: studentNumber ?? this.studentNumber,
    fullName: fullName ?? this.fullName,
    preferredName: clearPreferredName
        ? null
        : preferredName ?? this.preferredName,
    dateOfBirth: clearDateOfBirth ? null : dateOfBirth ?? this.dateOfBirth,
    gender: clearGender ? null : gender ?? this.gender,
    address: address ?? this.address,
    primaryParentName: primaryParentName ?? this.primaryParentName,
    primaryParentMobile: primaryParentMobile ?? this.primaryParentMobile,
    secondaryParentName: clearSecondaryParentName
        ? null
        : secondaryParentName ?? this.secondaryParentName,
    secondaryParentMobile: clearSecondaryParentMobile
        ? null
        : secondaryParentMobile ?? this.secondaryParentMobile,
    parentEmail: clearParentEmail ? null : parentEmail ?? this.parentEmail,
    emergencyContactName: clearEmergencyContactName
        ? null
        : emergencyContactName ?? this.emergencyContactName,
    emergencyContactMobile: clearEmergencyContactMobile
        ? null
        : emergencyContactMobile ?? this.emergencyContactMobile,
    status: status ?? this.status,
    active: active ?? this.active,
    qrToken: qrToken ?? this.qrToken,
    qrVersion: qrVersion ?? this.qrVersion,
    qrEnabled: qrEnabled ?? this.qrEnabled,
    createdAt: createdAt,
    createdBy: createdBy,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );

  Map<String, Object?> toMap() => {
    'studentId': studentId,
    'instituteId': instituteId,
    'studentNumber': studentNumber,
    'fullName': fullName,
    'preferredName': preferredName,
    'dateOfBirth': dateOfBirth,
    'gender': gender?.name,
    'address': address,
    'primaryParentName': primaryParentName,
    'primaryParentMobile': primaryParentMobile,
    'secondaryParentName': secondaryParentName,
    'secondaryParentMobile': secondaryParentMobile,
    'parentEmail': parentEmail,
    'emergencyContactName': emergencyContactName,
    'emergencyContactMobile': emergencyContactMobile,
    'status': status.name,
    'active': active,
    'qrTokenHash': qrToken,
    'qrVersion': qrVersion,
    'qrEnabled': qrEnabled,
    'createdAt': createdAt,
    'createdBy': createdBy,
    'updatedAt': updatedAt,
    'updatedBy': updatedBy,
  };

  static Student? tryFromMap(Map<String, Object?> data) {
    final status = StudentStatus.values
        .where((e) => e.name == data['status'])
        .firstOrNull;
    final gender = data['gender'] == null
        ? null
        : Gender.values.where((e) => e.name == data['gender']).firstOrNull;
    if (data['studentId'] is! String ||
        data['instituteId'] is! String ||
        data['studentNumber'] is! String ||
        data['fullName'] is! String ||
        data['address'] is! String ||
        data['primaryParentName'] is! String ||
        data['primaryParentMobile'] is! String ||
        status == null ||
        data['active'] is! bool ||
        data['qrTokenHash'] is! String ||
        data['qrVersion'] is! int ||
        data['qrEnabled'] is! bool ||
        data['createdAt'] is! DateTime ||
        data['createdBy'] is! String ||
        data['updatedAt'] is! DateTime ||
        data['updatedBy'] is! String ||
        (data['gender'] != null && gender == null)) {
      return null;
    }
    final student = Student(
      studentId: data['studentId']! as String,
      instituteId: data['instituteId']! as String,
      studentNumber: data['studentNumber']! as String,
      fullName: data['fullName']! as String,
      preferredName: data['preferredName'] as String?,
      dateOfBirth: data['dateOfBirth'] as DateTime?,
      gender: gender,
      address: data['address']! as String,
      primaryParentName: data['primaryParentName']! as String,
      primaryParentMobile: data['primaryParentMobile']! as String,
      secondaryParentName: data['secondaryParentName'] as String?,
      secondaryParentMobile: data['secondaryParentMobile'] as String?,
      parentEmail: data['parentEmail'] as String?,
      emergencyContactName: data['emergencyContactName'] as String?,
      emergencyContactMobile: data['emergencyContactMobile'] as String?,
      status: status,
      active: data['active']! as bool,
      qrToken: data['qrTokenHash']! as String,
      qrVersion: data['qrVersion']! as int,
      qrEnabled: data['qrEnabled']! as bool,
      createdAt: data['createdAt']! as DateTime,
      createdBy: data['createdBy']! as String,
      updatedAt: data['updatedAt']! as DateTime,
      updatedBy: data['updatedBy']! as String,
    );
    return student.validate() == null ? student : null;
  }
}

class ClassStudentAssignment {
  const ClassStudentAssignment({
    required this.assignmentId,
    required this.instituteId,
    required this.classId,
    required this.studentId,
    required this.active,
    required this.joinedAt,
    required this.joinedBy,
    this.leftAt,
    this.leftBy,
    required this.status,
    required this.scheduleOverlapConfirmed,
    this.scheduleOverlapReason,
    this.scheduleOverlapConfirmedBy,
    this.scheduleOverlapConfirmedAt,
  });
  final String assignmentId;
  final String instituteId;
  final String classId;
  final String studentId;
  final bool active;
  final DateTime joinedAt;
  final String joinedBy;
  final DateTime? leftAt;
  final String? leftBy;
  final ClassStudentAssignmentStatus status;
  final bool scheduleOverlapConfirmed;
  final String? scheduleOverlapReason;
  final String? scheduleOverlapConfirmedBy;
  final DateTime? scheduleOverlapConfirmedAt;
  Map<String, Object?> toMap() => {
    'assignmentId': assignmentId,
    'instituteId': instituteId,
    'classId': classId,
    'studentId': studentId,
    'active': active,
    'joinedAt': joinedAt,
    'joinedBy': joinedBy,
    'leftAt': leftAt,
    'leftBy': leftBy,
    'status': status.name,
    'scheduleOverlapConfirmed': scheduleOverlapConfirmed,
    'scheduleOverlapReason': scheduleOverlapReason,
    'scheduleOverlapConfirmedBy': scheduleOverlapConfirmedBy,
    'scheduleOverlapConfirmedAt': scheduleOverlapConfirmedAt,
  };
  static ClassStudentAssignment? tryFromMap(Map<String, Object?> data) {
    final status = ClassStudentAssignmentStatus.values
        .where((e) => e.name == data['status'])
        .firstOrNull;
    if (data['assignmentId'] is! String ||
        data['instituteId'] is! String ||
        data['classId'] is! String ||
        data['studentId'] is! String ||
        data['active'] is! bool ||
        data['joinedAt'] is! DateTime ||
        data['joinedBy'] is! String ||
        status == null ||
        data['scheduleOverlapConfirmed'] is! bool) {
      return null;
    }
    return ClassStudentAssignment(
      assignmentId: data['assignmentId']! as String,
      instituteId: data['instituteId']! as String,
      classId: data['classId']! as String,
      studentId: data['studentId']! as String,
      active: data['active']! as bool,
      joinedAt: data['joinedAt']! as DateTime,
      joinedBy: data['joinedBy']! as String,
      leftAt: data['leftAt'] as DateTime?,
      leftBy: data['leftBy'] as String?,
      status: status,
      scheduleOverlapConfirmed: data['scheduleOverlapConfirmed']! as bool,
      scheduleOverlapReason: data['scheduleOverlapReason'] as String?,
      scheduleOverlapConfirmedBy: data['scheduleOverlapConfirmedBy'] as String?,
      scheduleOverlapConfirmedAt:
          data['scheduleOverlapConfirmedAt'] as DateTime?,
    );
  }
}

class ScheduleOverlap {
  const ScheduleOverlap(this.firstClassId, this.secondClassId, this.days);
  final String firstClassId;
  final String secondClassId;
  final Set<ClassWeekday> days;
}

abstract final class ScheduleOverlapDetector {
  static List<ScheduleOverlap> detect(
    AcademicClass candidate,
    Iterable<AcademicClass> assignedClasses,
  ) => assignedClasses
      .where((other) => other.classId != candidate.classId && other.active)
      .map((other) {
        final days = candidate.daysOfWeek.intersection(other.daysOfWeek);
        final overlaps =
            candidate.startTime.compareTo(other.endTime) < 0 &&
            other.startTime.compareTo(candidate.endTime) < 0;
        return days.isNotEmpty && overlaps
            ? ScheduleOverlap(candidate.classId, other.classId, days)
            : null;
      })
      .whereType<ScheduleOverlap>()
      .toList();
}

enum InstituteAdminCapability {
  createClasses,
  editClasses,
  changeClassStatus,
  assignTeachers,
  createStudents,
  editStudents,
  changeStudentStatus,
  assignStudents,
  approveScheduleOverlaps,
  manageScheduleChanges,
  manageStudentQr,
  takeAttendance,
  correctAttendance,
  exportReports,
  viewParentContacts,
  manageTeachers,
  manageTeacherPermissions,
  resetTeacherPasswords,
  viewAuditLogs,
}

/// Institute Admins do not use Teacher permission switches. Their management
/// authority comes from their active role and is always scoped to one active
/// institute. Firestore Rules and trusted services must repeat the same scope.
abstract final class InstituteAdminCapabilities {
  static const Set<InstituteAdminCapability> fullWithinInstitute = {
    ...InstituteAdminCapability.values,
  };

  static bool allows(
    UserProfile actor,
    String instituteId,
    InstituteAdminCapability capability, {
    bool instituteActive = true,
  }) =>
      fullWithinInstitute.contains(capability) &&
      actor.active &&
      instituteActive &&
      actor.role == UserRole.instituteAdmin &&
      actor.instituteId == instituteId;
}

abstract final class AcademicAuthorization {
  static bool _isSuperAdmin(UserProfile actor) =>
      actor.active && actor.role == UserRole.superAdmin;

  static bool canCreateClasses(
    UserProfile actor, {
    bool instituteActive = true,
  }) =>
      _isSuperAdmin(actor) ||
      (actor.instituteId != null &&
          (InstituteAdminCapabilities.allows(
                actor,
                actor.instituteId!,
                InstituteAdminCapability.createClasses,
                instituteActive: instituteActive,
              ) ||
              (actor.active &&
                  instituteActive &&
                  actor.role == UserRole.teacher &&
                  actor.effectiveTeacherPermissions.canCreateClasses)));

  static bool canManageClasses(UserProfile actor) =>
      _isSuperAdmin(actor) ||
      (actor.role == UserRole.instituteAdmin && actor.active) ||
      (actor.role == UserRole.teacher &&
          actor.active &&
          (actor.effectiveTeacherPermissions.canCreateClasses ||
              actor.effectiveTeacherPermissions.canEditClasses));

  static bool canManageStudents(UserProfile actor) =>
      _isSuperAdmin(actor) ||
      (actor.role == UserRole.instituteAdmin && actor.active) ||
      (actor.role == UserRole.teacher &&
          actor.active &&
          (actor.effectiveTeacherPermissions.canAddStudents ||
              actor.effectiveTeacherPermissions.canEditStudents));

  static bool canViewClass(UserProfile actor, AcademicClass value) =>
      _isSuperAdmin(actor) ||
      (actor.active &&
          actor.instituteId == value.instituteId &&
          (actor.role == UserRole.instituteAdmin ||
              (actor.role == UserRole.teacher &&
                  value.teacherIds.contains(actor.uid))));

  static bool canCreateClass(
    UserProfile actor,
    String instituteId, {
    bool instituteActive = true,
  }) =>
      _isSuperAdmin(actor) ||
      InstituteAdminCapabilities.allows(
        actor,
        instituteId,
        InstituteAdminCapability.createClasses,
        instituteActive: instituteActive,
      ) ||
      (actor.active &&
          instituteActive &&
          actor.role == UserRole.teacher &&
          actor.instituteId == instituteId &&
          actor.effectiveTeacherPermissions.canCreateClasses);

  static bool canEditClass(
    UserProfile actor,
    AcademicClass value, {
    bool instituteActive = true,
  }) =>
      _isSuperAdmin(actor) ||
      InstituteAdminCapabilities.allows(
        actor,
        value.instituteId,
        InstituteAdminCapability.editClasses,
        instituteActive: instituteActive,
      ) ||
      (actor.active &&
          instituteActive &&
          actor.role == UserRole.teacher &&
          actor.instituteId == value.instituteId &&
          value.status != AcademicClassStatus.archived &&
          value.teacherIds.contains(actor.uid) &&
          actor.effectiveTeacherPermissions.canEditClasses);

  static bool canManageClass(
    UserProfile actor,
    AcademicClass value, {
    bool creating = false,
    bool instituteActive = true,
  }) => creating
      ? canCreateClass(
          actor,
          value.instituteId,
          instituteActive: instituteActive,
        )
      : canEditClass(actor, value, instituteActive: instituteActive);

  static bool canChangeClassStatus(UserProfile actor, AcademicClass value) =>
      _isSuperAdmin(actor) ||
      InstituteAdminCapabilities.allows(
        actor,
        value.instituteId,
        InstituteAdminCapability.changeClassStatus,
      );

  static bool canAssignTeachers(UserProfile actor, AcademicClass value) =>
      _isSuperAdmin(actor) ||
      InstituteAdminCapabilities.allows(
        actor,
        value.instituteId,
        InstituteAdminCapability.assignTeachers,
      );

  /// Full student documents include parent contact details. Teacher writes
  /// therefore require a trusted service even when the typed permission is on.
  static bool canCreateStudent(
    UserProfile actor,
    String instituteId, {
    bool trustedBackendAvailable = false,
  }) =>
      _isSuperAdmin(actor) ||
      InstituteAdminCapabilities.allows(
        actor,
        instituteId,
        InstituteAdminCapability.createStudents,
      ) ||
      (trustedBackendAvailable &&
          actor.active &&
          actor.role == UserRole.teacher &&
          actor.instituteId == instituteId &&
          actor.effectiveTeacherPermissions.canAddStudents);

  static bool canEditStudent(
    UserProfile actor,
    Student student, {
    Iterable<AcademicClass> assignedClasses = const [],
    bool trustedBackendAvailable = false,
  }) =>
      _isSuperAdmin(actor) ||
      InstituteAdminCapabilities.allows(
        actor,
        student.instituteId,
        InstituteAdminCapability.editStudents,
      ) ||
      (trustedBackendAvailable &&
          actor.active &&
          actor.role == UserRole.teacher &&
          actor.instituteId == student.instituteId &&
          actor.effectiveTeacherPermissions.canEditStudents &&
          assignedClasses.any((value) => value.teacherIds.contains(actor.uid)));

  static bool canAssignStudents(UserProfile actor, AcademicClass value) =>
      _isSuperAdmin(actor) ||
      InstituteAdminCapabilities.allows(
        actor,
        value.instituteId,
        InstituteAdminCapability.assignStudents,
      );

  static bool canManageScheduleChange(UserProfile actor, AcademicClass value) =>
      canEditClass(actor, value);

  static bool canViewParentContacts(
    UserProfile actor,
    Student student, {
    bool assignedStudentProjection = false,
  }) =>
      _isSuperAdmin(actor) ||
      InstituteAdminCapabilities.allows(
        actor,
        student.instituteId,
        InstituteAdminCapability.viewParentContacts,
      ) ||
      (assignedStudentProjection &&
          actor.active &&
          actor.role == UserRole.teacher &&
          actor.instituteId == student.instituteId &&
          actor.effectiveTeacherPermissions.canViewParentContacts);
}

abstract interface class AcademicRepository implements AuditLogRepository {
  Future<List<UserProfile>> fetchTeachersForAcademic(UserProfile actor);
  Future<List<AcademicClass>> fetchClasses(UserProfile actor);
  Future<AcademicClass> createClass(AcademicClass value, UserProfile actor);
  Future<void> updateClass(AcademicClass value, UserProfile actor);
  Future<List<ClassScheduleChange>> fetchScheduleChanges(
    UserProfile actor, {
    String? classId,
  });
  Future<void> saveScheduleChange(ClassScheduleChange value, UserProfile actor);
  Future<List<Student>> fetchStudents(UserProfile actor);
  Future<Student> createStudent(Student value, UserProfile actor);
  Future<void> updateStudent(Student value, UserProfile actor);
  Future<List<ClassStudentAssignment>> fetchAssignments(
    UserProfile actor, {
    String? classId,
    String? studentId,
  });
  Future<void> saveAssignment(ClassStudentAssignment value, UserProfile actor);
}
