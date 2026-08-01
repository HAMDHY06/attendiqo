import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 3, 8, 5);
  final teacher = UserProfile.newTeacher(
    uid: 'teacher-a',
    email: 'teacher@example.com',
    displayName: 'Teacher',
    instituteId: 'institute-a',
    createdBy: 'admin-a',
    now: now,
    permissions: const TeacherPermissions(canCorrectAttendance: true),
  );
  AcademicClass makeClass(String id, LocalTime start) => AcademicClass.newClass(
    classId: id,
    instituteId: 'institute-a',
    classCode: id.toUpperCase(),
    name: id,
    subject: 'Subject',
    teacherIds: const ['teacher-a'],
    primaryTeacherId: 'teacher-a',
    daysOfWeek: const {ClassWeekday.monday},
    startTime: start,
    endTime: LocalTime(start.hour + 1, start.minute),
    academicYear: 2026,
    now: now,
    actorUid: 'admin-a',
  );

  test('secure QR contains only opaque random payload and hash', () {
    final service = SecureStudentQrService();
    final first = service.generate(
      studentId: 'student-a',
      instituteId: 'institute-a',
      version: 1,
      now: now,
    );
    final second = service.generate(
      studentId: 'student-a',
      instituteId: 'institute-a',
      version: 1,
      now: now,
    );
    expect(first.payload, startsWith(SecureStudentQrService.prefix));
    expect(first.payload, isNot(contains('student-a')));
    expect(first.payload, isNot(contains('institute-a')));
    expect(first.payload, isNot(equals(second.payload)));
    expect(first.credential.tokenHash, hasLength(64));
  });

  test(
    'regeneration revokes the old token and disable state is explicit',
    () async {
      final qr = MockQrAdministrationService(
        classes: [makeClass('class-a', const LocalTime(8, 0))],
        assignments: [
          ClassStudentAssignment(
            assignmentId: 'class-a_student-a',
            instituteId: 'institute-a',
            classId: 'class-a',
            studentId: 'student-a',
            active: true,
            joinedAt: now,
            joinedBy: 'admin-a',
            status: ClassStudentAssignmentStatus.active,
            scheduleOverlapConfirmed: false,
          ),
        ],
      );
      final initial = qr.qrService.generate(
        studentId: 'student-a',
        instituteId: 'institute-a',
        version: 1,
        now: now,
      );
      qr.credentials[initial.credential.tokenHash] = initial.credential;
      final student = Student(
        studentId: 'student-a',
        instituteId: 'institute-a',
        studentNumber: 'STU-A',
        fullName: 'Student A',
        primaryParentName: 'Parent',
        primaryParentMobile: '+94771234567',
        status: StudentStatus.active,
        qrToken: initial.credential.tokenHash,
        createdAt: now,
        createdBy: 'admin-a',
        updatedAt: now,
      );
      final replacement = await qr.regenerate(student: student, actor: teacher);
      expect(qr.credentials.containsKey(initial.credential.tokenHash), isFalse);
      expect(qr.revokedHashes, contains(initial.credential.tokenHash));
      expect(replacement.credential.version, 2);
      final disabled = await qr.setEnabled(
        student: student.copyWith(
          qrToken: replacement.credential.tokenHash,
          qrVersion: 2,
        ),
        enabled: false,
        actor: teacher,
      );
      expect(disabled.enabled, isFalse);
    },
  );

  test('attendance permission matrix is assignment and capability scoped', () {
    final academicClass = makeClass('class-a', const LocalTime(8, 0));
    expect(
      AttendanceAuthorization.canTakeClassAttendance(teacher, academicClass),
      isTrue,
    );
    expect(
      AttendanceAuthorization.canTakeClassAttendance(
        teacher.copyWithTeacher(
          permissions: TeacherPermissions.noAccess,
          mustChangePassword: false,
          teacherStatus: TeacherStatus.active,
        ),
        academicClass,
      ),
      isFalse,
    );
    expect(
      AttendanceAuthorization.canCorrectClassAttendance(
        teacher,
        academicClass,
        reason: '',
      ),
      isFalse,
    );
    expect(
      AttendanceAuthorization.canExportClassReport(teacher, academicClass),
      isTrue,
    );
    expect(
      AttendanceAuthorization.canSendManualNotification(teacher, academicClass),
      isFalse,
    );
  });

  group('transactional attendance mock', () {
    late SecureStudentQrService qr;
    late QrGenerationResult generated;
    late Student student;
    late AcademicClass english;
    late AcademicClass science;
    late MockAttendanceService service;

    setUp(() {
      qr = SecureStudentQrService();
      generated = qr.generate(
        studentId: 'student-a',
        instituteId: 'institute-a',
        version: 1,
        now: now,
      );
      student = Student(
        studentId: 'student-a',
        instituteId: 'institute-a',
        studentNumber: 'STU-A',
        fullName: 'Student A',
        primaryParentName: 'Parent',
        primaryParentMobile: '+94771234567',
        status: StudentStatus.active,
        qrToken: generated.credential.tokenHash,
        createdAt: now,
        createdBy: 'admin-a',
        updatedAt: now,
      );
      english = makeClass('english', const LocalTime(8, 0));
      science = makeClass('science', const LocalTime(10, 0));
      service = MockAttendanceService(
        qrService: qr,
        students: {'student-a': student},
        credentials: {generated.credential.tokenHash: generated.credential},
        assignments: [
          for (final value in [english, science])
            ClassStudentAssignment(
              assignmentId: '${value.classId}_student-a',
              instituteId: 'institute-a',
              classId: value.classId,
              studentId: 'student-a',
              active: true,
              joinedAt: now,
              joinedBy: 'admin-a',
              status: ClassStudentAssignmentStatus.active,
              scheduleOverlapConfirmed: false,
            ),
        ],
        classes: {'english': english, 'science': science},
        clock: () => now,
      );
    });

    Future<AttendanceSession> start(AcademicClass value) =>
        service.startSession(
          academicClass: value,
          schedule: EffectiveClassSchedule(
            startTime: value.startTime,
            endTime: value.endTime,
            roomOrLocation: '',
          ),
          actor: teacher,
          date: DateTime.utc(2026, 8, 3),
          totalStudents: 1,
        );

    test(
      'effective schedule is used and duplicate open session is rejected',
      () async {
        final session = await service.startSession(
          academicClass: english,
          schedule: const EffectiveClassSchedule(
            startTime: LocalTime(9, 0),
            endTime: LocalTime(10, 0),
            roomOrLocation: 'Lab',
            scheduleChangeId: 'change-a',
          ),
          actor: teacher,
          date: DateTime.utc(2026, 8, 3),
          totalStudents: 1,
        );
        expect(session.effectiveStartTime, const LocalTime(9, 0));
        expect(session.scheduleChangeId, 'change-a');
        await expectLater(start(english), throwsA(isA<Failure>()));
      },
    );

    test('same QR records separate class-specific attendance', () async {
      final first = await start(english);
      final second = await start(science);
      final englishResult = await service.recordScan(
        AttendanceScanRequest(
          payload: generated.payload,
          session: first,
          mode: AttendanceScanMode.entry,
          actor: teacher,
          deviceId: 'device',
        ),
      );
      final scienceResult = await service.recordScan(
        AttendanceScanRequest(
          payload: generated.payload,
          session: second,
          mode: AttendanceScanMode.entry,
          actor: teacher,
          deviceId: 'device',
        ),
      );
      expect(englishResult.accepted, isTrue);
      expect(scienceResult.accepted, isTrue);
      expect(
        englishResult.record!.attendanceRecordId,
        isNot(scienceResult.record!.attendanceRecordId),
      );
      expect(service.records, hasLength(2));
    });

    test('entry and departure duplicate rules are session-specific', () async {
      final session = await start(english);
      AttendanceScanRequest request(AttendanceScanMode mode) =>
          AttendanceScanRequest(
            payload: generated.payload,
            session: session,
            mode: mode,
            actor: teacher,
            deviceId: 'device',
          );
      expect(
        (await service.recordScan(
          request(AttendanceScanMode.departure),
        )).status,
        ScannerResultStatus.departureBeforeEntry,
      );
      expect(
        (await service.recordScan(request(AttendanceScanMode.entry))).status,
        ScannerResultStatus.accepted,
      );
      expect(
        (await service.recordScan(request(AttendanceScanMode.entry))).status,
        ScannerResultStatus.duplicateEntry,
      );
      expect(
        (await service.recordScan(
          request(AttendanceScanMode.departure),
        )).status,
        ScannerResultStatus.accepted,
      );
      expect(
        (await service.recordScan(
          request(AttendanceScanMode.departure),
        )).status,
        ScannerResultStatus.duplicateDeparture,
      );
    });

    test(
      'disabled, wrong institute, wrong class, and inactive student are rejected',
      () async {
        final session = await start(english);
        final request = AttendanceScanRequest(
          payload: generated.payload,
          session: session,
          mode: AttendanceScanMode.entry,
          actor: teacher,
          deviceId: 'device',
        );
        service.credentials[generated.credential.tokenHash] =
            StudentQrCredential(
              studentId: 'student-a',
              instituteId: 'institute-a',
              tokenHash: generated.credential.tokenHash,
              version: 1,
              enabled: false,
              createdAt: now,
            );
        expect(
          (await service.recordScan(request)).status,
          ScannerResultStatus.disabledQr,
        );
        service.credentials[generated.credential.tokenHash] =
            StudentQrCredential(
              studentId: 'student-a',
              instituteId: 'institute-b',
              tokenHash: generated.credential.tokenHash,
              version: 1,
              enabled: true,
              createdAt: now,
            );
        expect(
          (await service.recordScan(request)).status,
          ScannerResultStatus.wrongInstitute,
        );
        service.credentials[generated.credential.tokenHash] =
            generated.credential;
        service.assignments.clear();
        expect(
          (await service.recordScan(request)).status,
          ScannerResultStatus.wrongClass,
        );
        service.assignments.add(
          ClassStudentAssignment(
            assignmentId: 'english_student-a',
            instituteId: 'institute-a',
            classId: 'english',
            studentId: 'student-a',
            active: true,
            joinedAt: now,
            joinedBy: 'admin-a',
            status: ClassStudentAssignmentStatus.active,
            scheduleOverlapConfirmed: false,
          ),
        );
        service.students['student-a'] = student.copyWith(
          active: false,
          status: StudentStatus.suspended,
        );
        expect(
          (await service.recordScan(request)).status,
          ScannerResultStatus.inactiveStudent,
        );
      },
    );

    test(
      'closed session rejects scans and corrections require a reason',
      () async {
        final session = await start(english);
        final closed = await service.closeSession(session, teacher);
        expect(
          (await service.recordScan(
            AttendanceScanRequest(
              payload: generated.payload,
              session: closed,
              mode: AttendanceScanMode.entry,
              actor: teacher,
              deviceId: 'device',
            ),
          )).status,
          ScannerResultStatus.closedSession,
        );
        final record = AttendanceRecord(
          attendanceRecordId: 'r',
          sessionId: session.sessionId,
          instituteId: 'institute-a',
          classId: 'english',
          studentId: 'student-a',
          attendanceDate: session.date,
          status: AttendanceStatus.present,
          createdAt: now,
          updatedAt: now,
        );
        await expectLater(
          service.correctRecord(
            record: record,
            status: AttendanceStatus.excused,
            reason: '',
            actor: teacher,
          ),
          throwsA(isA<Failure>()),
        );
        final corrected = await service.correctRecord(
          record: record,
          status: AttendanceStatus.excused,
          reason: 'Approved',
          actor: teacher,
        );
        expect(corrected.manuallyCorrected, isTrue);
        expect(service.corrections.single.before['status'], 'present');
        expect(service.auditEvents, contains(AuditAction.attendanceCorrected));
      },
    );
  });

  test('cooldown is token-specific', () {
    var clock = now;
    final guard = ScanCooldownGuard(clock: () => clock);
    expect(guard.shouldProcess('a'), isTrue);
    expect(guard.shouldProcess('a'), isFalse);
    expect(guard.shouldProcess('b'), isTrue);
    clock = clock.add(const Duration(seconds: 3));
    expect(guard.shouldProcess('a'), isTrue);
  });

  test('summary percentage and CSV export include expected values', () {
    final records = [
      AttendanceRecord(
        attendanceRecordId: 'a',
        sessionId: 's',
        instituteId: 'i',
        classId: 'c',
        studentId: 'one',
        attendanceDate: now,
        status: AttendanceStatus.present,
        createdAt: now,
        updatedAt: now,
      ),
      AttendanceRecord(
        attendanceRecordId: 'b',
        sessionId: 's',
        instituteId: 'i',
        classId: 'c',
        studentId: 'two',
        attendanceDate: now,
        status: AttendanceStatus.late,
        createdAt: now,
        updatedAt: now,
      ),
      AttendanceRecord(
        attendanceRecordId: 'c',
        sessionId: 's',
        instituteId: 'i',
        classId: 'c',
        studentId: 'three',
        attendanceDate: now,
        status: AttendanceStatus.absent,
        createdAt: now,
        updatedAt: now,
      ),
    ];
    expect(
      AttendanceSummary.from(records).attendancePercentage,
      closeTo(66.67, 0.01),
    );
    final csv = AttendanceCsvExporter.build(records);
    expect(csv, contains('attendanceRecordId,sessionId'));
    expect(csv, contains('present'));
  });
}
