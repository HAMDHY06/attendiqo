import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'academic.dart';
import 'enums.dart';
import 'models.dart';

class StudentQrCredential {
  const StudentQrCredential({
    required this.studentId,
    required this.instituteId,
    required this.tokenHash,
    required this.version,
    required this.enabled,
    required this.createdAt,
  });
  final String studentId;
  final String instituteId;
  final String tokenHash;
  final int version;
  final bool enabled;
  final DateTime createdAt;
  Map<String, Object?> toMap() => {
    'studentId': studentId,
    'instituteId': instituteId,
    'tokenHash': tokenHash,
    'version': version,
    'enabled': enabled,
    'createdAt': createdAt,
  };
}

/// Legacy QR value retained for source compatibility. New code must use
/// [StudentQrCredential] and store only a token hash.
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

class QrGenerationResult {
  const QrGenerationResult({required this.payload, required this.credential});
  final String payload;
  final StudentQrCredential credential;
}

abstract interface class QrAdministrationService {
  Future<QrGenerationResult> regenerate({
    required Student student,
    required UserProfile actor,
  });
  Future<StudentQrCredential> setEnabled({
    required Student student,
    required bool enabled,
    required UserProfile actor,
  });
}

abstract final class AttendanceAuthorization {
  static bool canGenerateStudentQr(
    UserProfile actor,
    Student student, {
    required Iterable<AcademicClass> classes,
    required Iterable<ClassStudentAssignment> assignments,
    bool trustedBackendAvailable = true,
  }) {
    if (!trustedBackendAvailable || !actor.active) return false;
    if (actor.role == UserRole.superAdmin) return true;
    if (InstituteAdminCapabilities.allows(
      actor,
      student.instituteId,
      InstituteAdminCapability.manageStudentQr,
    )) {
      return true;
    }
    if (actor.role != UserRole.teacher ||
        actor.instituteId != student.instituteId ||
        !actor.effectiveTeacherPermissions.canGenerateQrCodes) {
      return false;
    }
    final assignedClassIds = classes
        .where((value) => value.teacherIds.contains(actor.uid))
        .map((value) => value.classId)
        .toSet();
    return assignments.any(
      (value) =>
          value.active &&
          value.studentId == student.studentId &&
          assignedClassIds.contains(value.classId),
    );
  }

  static bool canTakeClassAttendance(
    UserProfile actor,
    AcademicClass value, {
    bool trustedBackendAvailable = true,
  }) =>
      trustedBackendAvailable &&
      value.canStartAttendance &&
      (actor.role == UserRole.superAdmin ||
          InstituteAdminCapabilities.allows(
            actor,
            value.instituteId,
            InstituteAdminCapability.takeAttendance,
          ) ||
          (actor.active &&
              actor.role == UserRole.teacher &&
              actor.instituteId == value.instituteId &&
              value.teacherIds.contains(actor.uid) &&
              actor.effectiveTeacherPermissions.canTakeAttendance));

  static bool canCorrectClassAttendance(
    UserProfile actor,
    AcademicClass value, {
    String? reason,
    bool trustedBackendAvailable = true,
  }) =>
      trustedBackendAvailable &&
      (reason == null || reason.trim().isNotEmpty) &&
      (actor.role == UserRole.superAdmin ||
          InstituteAdminCapabilities.allows(
            actor,
            value.instituteId,
            InstituteAdminCapability.correctAttendance,
          ) ||
          (actor.active &&
              actor.role == UserRole.teacher &&
              actor.instituteId == value.instituteId &&
              value.teacherIds.contains(actor.uid) &&
              actor.effectiveTeacherPermissions.canCorrectAttendance));

  static bool canExportClassReport(UserProfile actor, AcademicClass value) =>
      actor.role == UserRole.superAdmin ||
      InstituteAdminCapabilities.allows(
        actor,
        value.instituteId,
        InstituteAdminCapability.exportReports,
      ) ||
      (actor.active &&
          actor.role == UserRole.teacher &&
          actor.instituteId == value.instituteId &&
          value.teacherIds.contains(actor.uid) &&
          actor.effectiveTeacherPermissions.canExportReports);

  static bool canSendManualNotification(
    UserProfile actor,
    AcademicClass value, {
    bool backendAvailable = false,
  }) =>
      backendAvailable &&
      actor.active &&
      actor.role == UserRole.teacher &&
      actor.instituteId == value.instituteId &&
      value.teacherIds.contains(actor.uid) &&
      actor.effectiveTeacherPermissions.canSendManualNotifications;
}

class UnavailableQrAdministrationService implements QrAdministrationService {
  const UnavailableQrAdministrationService();
  Never _fail() => throw const Failure(
    'Trusted QR administration backend is not deployed.',
    code: 'backend-unavailable',
  );
  @override
  Future<QrGenerationResult> regenerate({
    required Student student,
    required UserProfile actor,
  }) async => _fail();
  @override
  Future<StudentQrCredential> setEnabled({
    required Student student,
    required bool enabled,
    required UserProfile actor,
  }) async => _fail();
}

class MockQrAdministrationService implements QrAdministrationService {
  MockQrAdministrationService({
    StudentQrService? qrService,
    this.classes = const [],
    this.assignments = const [],
  }) : qrService = qrService ?? SecureStudentQrService();
  final StudentQrService qrService;
  final List<AcademicClass> classes;
  final List<ClassStudentAssignment> assignments;
  final Map<String, StudentQrCredential> credentials = {};
  final Set<String> revokedHashes = {};

  bool _allowed(UserProfile actor, Student student) =>
      AttendanceAuthorization.canGenerateStudentQr(
        actor,
        student,
        classes: classes,
        assignments: assignments,
      );

  @override
  Future<QrGenerationResult> regenerate({
    required Student student,
    required UserProfile actor,
  }) async {
    if (!_allowed(actor, student)) {
      throw const Failure(
        'QR generation permission is required.',
        code: 'unauthorized',
      );
    }
    if (student.qrToken.isNotEmpty) {
      revokedHashes.add(student.qrToken);
      credentials.remove(student.qrToken);
    }
    final result = qrService.generate(
      studentId: student.studentId,
      instituteId: student.instituteId,
      version: student.qrVersion + 1,
    );
    credentials[result.credential.tokenHash] = result.credential;
    return result;
  }

  @override
  Future<StudentQrCredential> setEnabled({
    required Student student,
    required bool enabled,
    required UserProfile actor,
  }) async {
    if (!_allowed(actor, student)) {
      throw const Failure(
        'QR administration permission is required.',
        code: 'unauthorized',
      );
    }
    final value = StudentQrCredential(
      studentId: student.studentId,
      instituteId: student.instituteId,
      tokenHash: student.qrToken,
      version: student.qrVersion,
      enabled: enabled,
      createdAt: DateTime.now().toUtc(),
    );
    credentials[value.tokenHash] = value;
    return value;
  }
}

abstract interface class StudentQrService {
  QrGenerationResult generate({
    required String studentId,
    required String instituteId,
    required int version,
    DateTime? now,
  });
  String tokenHashFromPayload(String payload);
}

class SecureStudentQrService implements StudentQrService {
  SecureStudentQrService({Random? random})
    : _random = random ?? Random.secure();
  final Random _random;
  static const prefix = 'attendiqo://student/';

  @override
  QrGenerationResult generate({
    required String studentId,
    required String instituteId,
    required int version,
    DateTime? now,
  }) {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    final payload = '$prefix$token';
    return QrGenerationResult(
      payload: payload,
      credential: StudentQrCredential(
        studentId: studentId,
        instituteId: instituteId,
        tokenHash: sha256.convert(utf8.encode(token)).toString(),
        version: version,
        enabled: true,
        createdAt: now ?? DateTime.now().toUtc(),
      ),
    );
  }

  @override
  String tokenHashFromPayload(String payload) {
    if (!payload.startsWith(prefix) || payload.length <= prefix.length) {
      return '';
    }
    return sha256
        .convert(utf8.encode(payload.substring(prefix.length)))
        .toString();
  }
}

class AttendanceSession {
  const AttendanceSession({
    required this.sessionId,
    required this.instituteId,
    required this.classId,
    required this.date,
    required this.sessionType,
    required this.status,
    required this.startedAt,
    required this.startedBy,
    this.closedAt,
    this.closedBy,
    required this.expectedStartTime,
    required this.expectedEndTime,
    required this.effectiveStartTime,
    required this.effectiveEndTime,
    this.scheduleChangeId,
    required this.entryModeEnabled,
    required this.departureModeEnabled,
    required this.totalStudents,
    required this.presentCount,
    required this.lateCount,
    required this.absentCount,
    required this.createdAt,
    required this.updatedAt,
  });
  final String sessionId;
  final String instituteId;
  final String classId;
  final DateTime date;
  final AttendanceScanMode sessionType;
  final AttendanceSessionStatus status;
  final DateTime startedAt;
  final String startedBy;
  final DateTime? closedAt;
  final String? closedBy;
  final LocalTime expectedStartTime;
  final LocalTime expectedEndTime;
  final LocalTime effectiveStartTime;
  final LocalTime effectiveEndTime;
  final String? scheduleChangeId;
  final bool entryModeEnabled;
  final bool departureModeEnabled;
  final int totalStudents;
  final int presentCount;
  final int lateCount;
  final int absentCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  bool get acceptsScans => status == AttendanceSessionStatus.open;
  AttendanceSession close(String actorUid, DateTime now) => copyWith(
    status: AttendanceSessionStatus.closed,
    closedAt: now,
    closedBy: actorUid,
    updatedAt: now,
  );
  AttendanceSession copyWith({
    AttendanceSessionStatus? status,
    DateTime? closedAt,
    String? closedBy,
    int? presentCount,
    int? lateCount,
    int? absentCount,
    DateTime? updatedAt,
  }) => AttendanceSession(
    sessionId: sessionId,
    instituteId: instituteId,
    classId: classId,
    date: date,
    sessionType: sessionType,
    status: status ?? this.status,
    startedAt: startedAt,
    startedBy: startedBy,
    closedAt: closedAt ?? this.closedAt,
    closedBy: closedBy ?? this.closedBy,
    expectedStartTime: expectedStartTime,
    expectedEndTime: expectedEndTime,
    effectiveStartTime: effectiveStartTime,
    effectiveEndTime: effectiveEndTime,
    scheduleChangeId: scheduleChangeId,
    entryModeEnabled: entryModeEnabled,
    departureModeEnabled: departureModeEnabled,
    totalStudents: totalStudents,
    presentCount: presentCount ?? this.presentCount,
    lateCount: lateCount ?? this.lateCount,
    absentCount: absentCount ?? this.absentCount,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Map<String, Object?> toMap() => {
    'sessionId': sessionId,
    'instituteId': instituteId,
    'classId': classId,
    'date': date,
    'sessionType': sessionType.name,
    'status': status.name,
    'startedAt': startedAt,
    'startedBy': startedBy,
    'closedAt': closedAt,
    'closedBy': closedBy,
    'expectedStartTime': expectedStartTime.wireValue,
    'expectedEndTime': expectedEndTime.wireValue,
    'effectiveStartTime': effectiveStartTime.wireValue,
    'effectiveEndTime': effectiveEndTime.wireValue,
    'scheduleChangeId': scheduleChangeId,
    'entryModeEnabled': entryModeEnabled,
    'departureModeEnabled': departureModeEnabled,
    'totalStudents': totalStudents,
    'presentCount': presentCount,
    'lateCount': lateCount,
    'absentCount': absentCount,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

class AttendanceRecord {
  AttendanceRecord({
    String? attendanceRecordId,
    String? recordId,
    required this.sessionId,
    required this.instituteId,
    required this.classId,
    required this.studentId,
    DateTime? attendanceDate,
    DateTime? entryTime,
    DateTime? departureTime,
    required this.status,
    this.lateMinutes = 0,
    String? entryMarkedBy,
    this.departureMarkedBy,
    String? entryDeviceId,
    this.departureDeviceId,
    this.scanMethod = ScanMethod.qr,
    this.manuallyCorrected = false,
    this.correctionReason,
    this.correctedBy,
    this.correctedAt,
    this.syncState = AttendanceSyncState.confirmed,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? recordedBy,
    String? deviceIdentifier,
    DateTime? entryAt,
    DateTime? departureAt,
  }) : attendanceRecordId = attendanceRecordId ?? recordId ?? '',
       attendanceDate =
           attendanceDate ??
           entryAt ??
           DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
       entryTime = entryTime ?? entryAt,
       departureTime = departureTime ?? departureAt,
       entryMarkedBy = entryMarkedBy ?? recordedBy,
       entryDeviceId = entryDeviceId ?? deviceIdentifier,
       createdAt =
           createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
       updatedAt =
           updatedAt ??
           createdAt ??
           DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final String attendanceRecordId;
  final String sessionId;
  final String instituteId;
  final String classId;
  final String studentId;
  final DateTime attendanceDate;
  final DateTime? entryTime;
  final DateTime? departureTime;
  final AttendanceStatus status;
  final int lateMinutes;
  final String? entryMarkedBy;
  final String? departureMarkedBy;
  final String? entryDeviceId;
  final String? departureDeviceId;
  final ScanMethod scanMethod;
  final bool manuallyCorrected;
  final String? correctionReason;
  final String? correctedBy;
  final DateTime? correctedAt;
  final AttendanceSyncState syncState;
  final DateTime createdAt;
  final DateTime updatedAt;
  String get recordId => attendanceRecordId;

  AttendanceRecord withDeparture({
    required DateTime time,
    required String actorUid,
    required String deviceId,
  }) => AttendanceRecord(
    attendanceRecordId: attendanceRecordId,
    sessionId: sessionId,
    instituteId: instituteId,
    classId: classId,
    studentId: studentId,
    attendanceDate: attendanceDate,
    entryTime: entryTime,
    departureTime: time,
    status: status,
    lateMinutes: lateMinutes,
    entryMarkedBy: entryMarkedBy,
    departureMarkedBy: actorUid,
    entryDeviceId: entryDeviceId,
    departureDeviceId: deviceId,
    scanMethod: scanMethod,
    manuallyCorrected: manuallyCorrected,
    correctionReason: correctionReason,
    correctedBy: correctedBy,
    correctedAt: correctedAt,
    syncState: AttendanceSyncState.confirmed,
    createdAt: createdAt,
    updatedAt: time,
  );
  Map<String, Object?> toMap() => {
    'attendanceRecordId': attendanceRecordId,
    'sessionId': sessionId,
    'instituteId': instituteId,
    'classId': classId,
    'studentId': studentId,
    'attendanceDate': attendanceDate,
    'entryTime': entryTime,
    'departureTime': departureTime,
    'status': status.name,
    'lateMinutes': lateMinutes,
    'entryMarkedBy': entryMarkedBy,
    'departureMarkedBy': departureMarkedBy,
    'entryDeviceId': entryDeviceId,
    'departureDeviceId': departureDeviceId,
    'scanMethod': scanMethod.name,
    'manuallyCorrected': manuallyCorrected,
    'correctionReason': correctionReason,
    'correctedBy': correctedBy,
    'correctedAt': correctedAt,
    'syncState': syncState.name,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

class AttendanceCorrection {
  const AttendanceCorrection({
    required this.correctionId,
    required this.attendanceRecordId,
    required this.instituteId,
    required this.classId,
    required this.studentId,
    required this.before,
    required this.after,
    required this.reason,
    required this.correctedBy,
    required this.correctedAt,
  });
  final String correctionId;
  final String attendanceRecordId;
  final String instituteId;
  final String classId;
  final String studentId;
  final Map<String, Object?> before;
  final Map<String, Object?> after;
  final String reason;
  final String correctedBy;
  final DateTime correctedAt;
  String? validate() =>
      reason.trim().isEmpty ? 'Correction reason is required' : null;
}

class AttendanceScanRequest {
  const AttendanceScanRequest({
    required this.payload,
    required this.session,
    required this.mode,
    required this.actor,
    required this.deviceId,
  });
  final String payload;
  final AttendanceSession session;
  final AttendanceScanMode mode;
  final UserProfile actor;
  final String deviceId;
}

class AttendanceScanResult {
  const AttendanceScanResult(
    this.status,
    this.message, {
    this.student,
    this.record,
    this.confirmed = false,
  });
  final ScannerResultStatus status;
  final String message;
  final Student? student;
  final AttendanceRecord? record;
  final bool confirmed;
  bool get accepted => status == ScannerResultStatus.accepted;
}

abstract interface class AttendanceService {
  Future<AttendanceSession> startSession({
    required AcademicClass academicClass,
    required EffectiveClassSchedule schedule,
    required UserProfile actor,
    required DateTime date,
    required int totalStudents,
  });
  Future<AttendanceScanResult> recordScan(AttendanceScanRequest request);
  Future<AttendanceSession> closeSession(
    AttendanceSession session,
    UserProfile actor,
  );
  Future<AttendanceSession> cancelSession(
    AttendanceSession session,
    UserProfile actor,
  );
  Future<AttendanceRecord> recordManual({
    required AttendanceSession session,
    required Student student,
    required AttendanceStatus status,
    required String reason,
    required UserProfile actor,
  });
  Future<AttendanceRecord> correctRecord({
    required AttendanceRecord record,
    required AttendanceStatus status,
    required String reason,
    required UserProfile actor,
    DateTime? entryTime,
    DateTime? departureTime,
  });
}

class UnavailableAttendanceService implements AttendanceService {
  const UnavailableAttendanceService();
  Never _fail() => throw const Failure(
    'Trusted attendance backend is not deployed.',
    code: 'backend-unavailable',
  );
  @override
  Future<AttendanceSession> startSession({
    required AcademicClass academicClass,
    required EffectiveClassSchedule schedule,
    required UserProfile actor,
    required DateTime date,
    required int totalStudents,
  }) async => _fail();
  @override
  Future<AttendanceScanResult> recordScan(
    AttendanceScanRequest request,
  ) async => _fail();
  @override
  Future<AttendanceSession> closeSession(
    AttendanceSession session,
    UserProfile actor,
  ) async => _fail();
  @override
  Future<AttendanceSession> cancelSession(
    AttendanceSession session,
    UserProfile actor,
  ) async => _fail();
  @override
  Future<AttendanceRecord> recordManual({
    required AttendanceSession session,
    required Student student,
    required AttendanceStatus status,
    required String reason,
    required UserProfile actor,
  }) async => _fail();
  @override
  Future<AttendanceRecord> correctRecord({
    required AttendanceRecord record,
    required AttendanceStatus status,
    required String reason,
    required UserProfile actor,
    DateTime? entryTime,
    DateTime? departureTime,
  }) async => _fail();
}

class MockAttendanceService implements AttendanceService {
  MockAttendanceService({
    required this.qrService,
    required this.students,
    required this.credentials,
    required this.assignments,
    required this.classes,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());
  final StudentQrService qrService;
  final Map<String, Student> students;
  final Map<String, StudentQrCredential> credentials;
  final List<ClassStudentAssignment> assignments;
  final Map<String, AcademicClass> classes;
  final DateTime Function() _clock;
  final Map<String, AttendanceRecord> records = {};
  final Map<String, AttendanceSession> sessions = {};
  final List<AttendanceCorrection> corrections = [];
  final List<AuditAction> auditEvents = [];

  @override
  Future<AttendanceSession> startSession({
    required AcademicClass academicClass,
    required EffectiveClassSchedule schedule,
    required UserProfile actor,
    required DateTime date,
    required int totalStudents,
  }) async {
    if (!academicClass.canStartAttendance) {
      throw const Failure(
        'Class is not ready for attendance.',
        code: 'class-inactive',
      );
    }
    if (!AttendanceAuthorization.canTakeClassAttendance(actor, academicClass)) {
      throw const Failure(
        'Attendance permission is required.',
        code: 'unauthorized',
      );
    }
    final now = _clock();
    final sessionId =
        '${academicClass.classId}_${date.toIso8601String().substring(0, 10)}';
    if (sessions[sessionId]?.status == AttendanceSessionStatus.open) {
      throw const Failure(
        'An attendance session is already open for this class and date.',
        code: 'session-exists',
      );
    }
    final session = AttendanceSession(
      sessionId: sessionId,
      instituteId: academicClass.instituteId,
      classId: academicClass.classId,
      date: date,
      sessionType: AttendanceScanMode.entry,
      status: AttendanceSessionStatus.open,
      startedAt: now,
      startedBy: actor.uid,
      expectedStartTime: academicClass.startTime,
      expectedEndTime: academicClass.endTime,
      effectiveStartTime: schedule.startTime,
      effectiveEndTime: schedule.endTime,
      scheduleChangeId: schedule.scheduleChangeId,
      entryModeEnabled: true,
      departureModeEnabled: true,
      totalStudents: totalStudents,
      presentCount: 0,
      lateCount: 0,
      absentCount: totalStudents,
      createdAt: now,
      updatedAt: now,
    );
    sessions[session.sessionId] = session;
    auditEvents.add(AuditAction.attendanceSessionStarted);
    return session;
  }

  @override
  Future<AttendanceScanResult> recordScan(AttendanceScanRequest request) async {
    if (!request.session.acceptsScans) {
      return const AttendanceScanResult(
        ScannerResultStatus.closedSession,
        'Session is closed.',
      );
    }
    final academicClass = classes[request.session.classId];
    if (academicClass == null ||
        !AttendanceAuthorization.canTakeClassAttendance(
          request.actor,
          academicClass,
        )) {
      return const AttendanceScanResult(
        ScannerResultStatus.permissionDenied,
        'You cannot record attendance for this class.',
      );
    }
    final hash = qrService.tokenHashFromPayload(request.payload);
    if (hash.isEmpty) {
      return const AttendanceScanResult(
        ScannerResultStatus.invalidQr,
        'Invalid Attendiqo QR code.',
      );
    }
    final credential = credentials[hash];
    if (credential == null) {
      return const AttendanceScanResult(
        ScannerResultStatus.invalidQr,
        'Invalid or replaced QR code.',
      );
    }
    if (!credential.enabled) {
      return const AttendanceScanResult(
        ScannerResultStatus.disabledQr,
        'This QR code is disabled.',
      );
    }
    if (credential.instituteId != request.session.instituteId) {
      return const AttendanceScanResult(
        ScannerResultStatus.wrongInstitute,
        'Student belongs to another institute.',
      );
    }
    final student = students[credential.studentId];
    if (student == null ||
        !student.scannerEligible ||
        student.qrVersion != credential.version) {
      return AttendanceScanResult(
        ScannerResultStatus.inactiveStudent,
        'Student or QR is inactive.',
        student: student,
      );
    }
    final enrolled = assignments.any(
      (value) =>
          value.studentId == student.studentId &&
          value.classId == request.session.classId &&
          value.instituteId == request.session.instituteId &&
          value.active,
    );
    if (!enrolled) {
      return AttendanceScanResult(
        ScannerResultStatus.wrongClass,
        'Student is not enrolled in this class.',
        student: student,
      );
    }
    final key = '${request.session.sessionId}_${student.studentId}';
    final existing = records[key];
    final now = _clock();
    if (request.mode == AttendanceScanMode.entry) {
      if (existing?.entryTime != null) {
        return AttendanceScanResult(
          ScannerResultStatus.duplicateEntry,
          'Entry already recorded.',
          student: student,
          record: existing,
        );
      }
      final scheduled = DateTime.utc(
        now.year,
        now.month,
        now.day,
        request.session.effectiveStartTime.hour,
        request.session.effectiveStartTime.minute,
      );
      final lateMinutes = max(0, now.difference(scheduled).inMinutes);
      final record = AttendanceRecord(
        attendanceRecordId: key,
        sessionId: request.session.sessionId,
        instituteId: request.session.instituteId,
        classId: request.session.classId,
        studentId: student.studentId,
        attendanceDate: request.session.date,
        entryTime: now,
        status: lateMinutes > 0
            ? AttendanceStatus.late
            : AttendanceStatus.present,
        lateMinutes: lateMinutes,
        entryMarkedBy: request.actor.uid,
        entryDeviceId: request.deviceId,
        scanMethod: ScanMethod.qr,
        manuallyCorrected: false,
        syncState: AttendanceSyncState.confirmed,
        createdAt: now,
        updatedAt: now,
      );
      records[key] = record;
      auditEvents.add(AuditAction.studentEntryRecorded);
      return AttendanceScanResult(
        ScannerResultStatus.accepted,
        'Entry recorded.',
        student: student,
        record: record,
        confirmed: true,
      );
    }
    if (existing?.entryTime == null) {
      return AttendanceScanResult(
        ScannerResultStatus.departureBeforeEntry,
        'Record entry before departure.',
        student: student,
      );
    }
    if (existing!.departureTime != null) {
      return AttendanceScanResult(
        ScannerResultStatus.duplicateDeparture,
        'Departure already recorded.',
        student: student,
        record: existing,
      );
    }
    final updated = existing.withDeparture(
      time: now,
      actorUid: request.actor.uid,
      deviceId: request.deviceId,
    );
    records[key] = updated;
    auditEvents.add(AuditAction.studentDepartureRecorded);
    return AttendanceScanResult(
      ScannerResultStatus.accepted,
      'Departure recorded.',
      student: student,
      record: updated,
      confirmed: true,
    );
  }

  @override
  Future<AttendanceSession> closeSession(
    AttendanceSession session,
    UserProfile actor,
  ) async {
    final academicClass = classes[session.classId];
    if (academicClass == null ||
        !AttendanceAuthorization.canTakeClassAttendance(actor, academicClass)) {
      throw const Failure(
        'Attendance permission is required.',
        code: 'unauthorized',
      );
    }
    final value = session.close(actor.uid, _clock());
    sessions[value.sessionId] = value;
    auditEvents.add(AuditAction.attendanceSessionClosed);
    return value;
  }

  @override
  Future<AttendanceSession> cancelSession(
    AttendanceSession session,
    UserProfile actor,
  ) async {
    final academicClass = classes[session.classId];
    if (academicClass == null ||
        !AttendanceAuthorization.canTakeClassAttendance(actor, academicClass)) {
      throw const Failure(
        'Attendance permission is required.',
        code: 'unauthorized',
      );
    }
    final now = _clock();
    final value = session.copyWith(
      status: AttendanceSessionStatus.cancelled,
      closedAt: now,
      closedBy: actor.uid,
      updatedAt: now,
    );
    sessions[value.sessionId] = value;
    auditEvents.add(AuditAction.attendanceSessionCancelled);
    return value;
  }

  @override
  Future<AttendanceRecord> recordManual({
    required AttendanceSession session,
    required Student student,
    required AttendanceStatus status,
    required String reason,
    required UserProfile actor,
  }) async {
    if (reason.trim().isEmpty) {
      throw const Failure(
        'A reason is required for manual attendance.',
        code: 'reason-required',
      );
    }
    final academicClass = classes[session.classId];
    final canCorrect =
        academicClass != null &&
        AttendanceAuthorization.canCorrectClassAttendance(
          actor,
          academicClass,
          reason: reason,
        );
    if (!canCorrect) {
      throw const Failure(
        'Correction permission is required.',
        code: 'unauthorized',
      );
    }
    if (!session.acceptsScans) {
      throw const Failure('Session is closed.', code: 'session-closed');
    }
    final enrolled = assignments.any(
      (value) =>
          value.studentId == student.studentId &&
          value.classId == session.classId &&
          value.active,
    );
    if (!enrolled || !student.active) {
      throw const Failure(
        'Student is not eligible for this class.',
        code: 'student-ineligible',
      );
    }
    final now = _clock();
    final key = '${session.sessionId}_${student.studentId}';
    final record = AttendanceRecord(
      attendanceRecordId: key,
      sessionId: session.sessionId,
      instituteId: session.instituteId,
      classId: session.classId,
      studentId: student.studentId,
      attendanceDate: session.date,
      entryTime: status == AttendanceStatus.absent ? null : now,
      status: status,
      lateMinutes: status == AttendanceStatus.late ? 1 : 0,
      entryMarkedBy: actor.uid,
      entryDeviceId: 'manual',
      scanMethod: ScanMethod.manual,
      manuallyCorrected: true,
      correctionReason: reason.trim(),
      correctedBy: actor.uid,
      correctedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    records[key] = record;
    auditEvents.add(AuditAction.manualAttendanceRecorded);
    return record;
  }

  @override
  Future<AttendanceRecord> correctRecord({
    required AttendanceRecord record,
    required AttendanceStatus status,
    required String reason,
    required UserProfile actor,
    DateTime? entryTime,
    DateTime? departureTime,
  }) async {
    if (reason.trim().isEmpty) {
      throw const Failure(
        'Correction reason is required.',
        code: 'reason-required',
      );
    }
    final value = classes[record.classId];
    final allowed =
        value != null &&
        AttendanceAuthorization.canCorrectClassAttendance(
          actor,
          value,
          reason: reason,
        );
    if (!allowed) {
      throw const Failure(
        'Correction permission is required.',
        code: 'unauthorized',
      );
    }
    final now = _clock();
    final corrected = AttendanceRecord(
      attendanceRecordId: record.attendanceRecordId,
      sessionId: record.sessionId,
      instituteId: record.instituteId,
      classId: record.classId,
      studentId: record.studentId,
      attendanceDate: record.attendanceDate,
      entryTime: entryTime ?? record.entryTime,
      departureTime: departureTime ?? record.departureTime,
      status: status,
      lateMinutes: status == AttendanceStatus.late ? record.lateMinutes : 0,
      entryMarkedBy: record.entryMarkedBy,
      departureMarkedBy: record.departureMarkedBy,
      entryDeviceId: record.entryDeviceId,
      departureDeviceId: record.departureDeviceId,
      scanMethod: ScanMethod.correction,
      manuallyCorrected: true,
      correctionReason: reason.trim(),
      correctedBy: actor.uid,
      correctedAt: now,
      syncState: AttendanceSyncState.confirmed,
      createdAt: record.createdAt,
      updatedAt: now,
    );
    corrections.add(
      AttendanceCorrection(
        correctionId: 'correction-${corrections.length + 1}',
        attendanceRecordId: record.attendanceRecordId,
        instituteId: record.instituteId,
        classId: record.classId,
        studentId: record.studentId,
        before: record.toMap(),
        after: corrected.toMap(),
        reason: reason.trim(),
        correctedBy: actor.uid,
        correctedAt: now,
      ),
    );
    records['${record.sessionId}_${record.studentId}'] = corrected;
    auditEvents.add(AuditAction.attendanceCorrected);
    return corrected;
  }
}

class ScanCooldownGuard {
  ScanCooldownGuard({
    this.duration = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());
  final Duration duration;
  final DateTime Function() _clock;
  final Map<String, DateTime> _acceptedAt = {};
  bool shouldProcess(String tokenHash) {
    final now = _clock();
    final prior = _acceptedAt[tokenHash];
    if (prior != null && now.difference(prior) < duration) return false;
    _acceptedAt[tokenHash] = now;
    return true;
  }
}

class AttendanceSummary {
  const AttendanceSummary({
    required this.total,
    required this.present,
    required this.late,
    required this.absent,
    required this.excused,
  });
  final int total;
  final int present;
  final int late;
  final int absent;
  final int excused;
  double get attendancePercentage =>
      total == 0 ? 0 : ((present + late) / total) * 100;
  static AttendanceSummary from(Iterable<AttendanceRecord> records) {
    final values = records.toList();
    return AttendanceSummary(
      total: values.length,
      present: values.where((e) => e.status == AttendanceStatus.present).length,
      late: values.where((e) => e.status == AttendanceStatus.late).length,
      absent: values.where((e) => e.status == AttendanceStatus.absent).length,
      excused: values.where((e) => e.status == AttendanceStatus.excused).length,
    );
  }
}

abstract interface class AttendanceExportService {
  String buildCsv(Iterable<AttendanceRecord> records);
  Future<List<int>> buildPdf({
    required String title,
    required Iterable<AttendanceRecord> records,
  });
}

abstract final class AttendanceCsvExporter {
  static String build(Iterable<AttendanceRecord> records) {
    String escape(Object? value) =>
        '"${(value ?? '').toString().replaceAll('"', '""')}"';
    final lines = <String>[
      'attendanceRecordId,sessionId,classId,studentId,date,entry,departure,status,lateMinutes',
    ];
    for (final record in records) {
      lines.add(
        [
          record.attendanceRecordId,
          record.sessionId,
          record.classId,
          record.studentId,
          record.attendanceDate.toIso8601String(),
          record.entryTime?.toIso8601String(),
          record.departureTime?.toIso8601String(),
          record.status.name,
          record.lateMinutes,
        ].map(escape).join(','),
      );
    }
    return lines.join('\n');
  }
}
