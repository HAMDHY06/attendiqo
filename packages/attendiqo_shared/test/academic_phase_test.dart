import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 1);

  AcademicClass makeClass({
    String id = 'class-a',
    String code = 'MATH-A',
    Set<ClassWeekday> days = const {ClassWeekday.monday},
    LocalTime start = const LocalTime(8, 0),
    LocalTime end = const LocalTime(9, 0),
  }) => AcademicClass.newClass(
    classId: id,
    instituteId: 'institute-a',
    classCode: code,
    name: 'Mathematics',
    subject: 'Mathematics',
    daysOfWeek: days,
    startTime: start,
    endTime: end,
    academicYear: 2026,
    teacherIds: const ['teacher-a'],
    primaryTeacherId: 'teacher-a',
    now: now,
    actorUid: 'admin-a',
  );

  Student makeStudent() => Student(
    studentId: 'student-a',
    instituteId: 'institute-a',
    studentNumber: 'STU-A',
    fullName: 'Student A',
    primaryParentName: 'Parent A',
    primaryParentMobile: '+94771234567',
    status: StudentStatus.active,
    qrToken: List.filled(64, 'a').join(),
    createdAt: now,
    createdBy: 'admin-a',
    updatedAt: now,
  );

  UserProfile admin({String instituteId = 'institute-a'}) => UserProfile(
    uid: 'admin-a',
    email: 'admin@example.com',
    displayName: 'Institute Admin',
    role: UserRole.instituteAdmin,
    instituteId: instituteId,
    active: true,
    mustChangePassword: false,
    createdAt: now,
    createdBy: 'seed',
    updatedAt: now,
  );

  UserProfile teacher(TeacherPermissions permissions) => UserProfile(
    uid: 'teacher-a',
    email: 'teacher@example.com',
    displayName: 'Teacher',
    role: UserRole.teacher,
    instituteId: 'institute-a',
    active: true,
    mustChangePassword: false,
    createdAt: now,
    createdBy: 'admin-a',
    updatedAt: now,
    permissions: permissions,
    teacherStatus: TeacherStatus.active,
  );

  test('class model round-trips and validates safe uppercase codes', () {
    final value = makeClass();
    expect(value.validate(), isNull);
    expect(AcademicClass.tryFromMap(value.toMap())?.classCode, 'MATH-A');
    expect(ClassCodeValidator.validate('bad code!'), isNotNull);
    expect(ClassCodeValidator.normalize(' sci-a '), 'SCI-A');
  });

  test('class defaults and status transitions preserve history', () {
    final value = makeClass();
    expect(value.active, isTrue);
    expect(value.status, AcademicClassStatus.active);
    final archived = value.copyWith(
      active: false,
      status: AcademicClassStatus.archived,
      updatedAt: now.add(const Duration(days: 1)),
    );
    expect(archived.status, AcademicClassStatus.archived);
    expect(archived.createdAt, now);
  });

  test('schedule overlap is detected by day and time', () {
    final candidate = makeClass(
      id: 'candidate',
      start: const LocalTime(8, 30),
      end: const LocalTime(9, 30),
    );
    final existing = makeClass(id: 'existing');
    expect(ScheduleOverlapDetector.detect(candidate, [existing]), hasLength(1));
    final otherDay = makeClass(id: 'other', days: const {ClassWeekday.tuesday});
    expect(ScheduleOverlapDetector.detect(candidate, [otherDay]), isEmpty);
  });

  test('temporary schedule overrides only the effective date', () {
    final value = makeClass();
    final change = ClassScheduleChange(
      scheduleChangeId: 'change-a',
      instituteId: 'institute-a',
      classId: value.classId,
      effectiveDate: DateTime.utc(2026, 8, 3),
      oldStartTime: value.startTime,
      oldEndTime: value.endTime,
      newStartTime: const LocalTime(10, 0),
      newEndTime: const LocalTime(11, 0),
      oldRoomOrLocation: '',
      newRoomOrLocation: 'Lab',
      reason: 'Exam',
      status: ScheduleChangeStatus.scheduled,
      changedBy: 'admin-a',
      changedAt: now,
      updatedAt: now,
    );
    expect(
      ClassScheduleResolver.resolve(value, DateTime.utc(2026, 8, 3), [
        change,
      ]).startTime,
      const LocalTime(10, 0),
    );
    expect(
      ClassScheduleResolver.resolve(value, DateTime.utc(2026, 8, 4), [
        change,
      ]).startTime,
      value.startTime,
    );
  });

  test(
    'student requires primary mobile, permits optional secondary, and stores no photo field',
    () {
      final value = makeStudent();
      expect(value.validate(), isNull);
      expect(
        value.toMap().keys.any((key) => key.toLowerCase().contains('photo')),
        isFalse,
      );
      expect(MobileNumberValidator.validatePrimary(''), isNotNull);
      expect(MobileNumberValidator.validateSecondary(null), isNull);
    },
  );

  test('assignment records explicit overlap approval and removal metadata', () {
    final assignment = ClassStudentAssignment(
      assignmentId: 'class-a_student-a',
      instituteId: 'institute-a',
      classId: 'class-a',
      studentId: 'student-a',
      active: true,
      joinedAt: now,
      joinedBy: 'admin-a',
      status: ClassStudentAssignmentStatus.active,
      scheduleOverlapConfirmed: true,
      scheduleOverlapReason: 'Approved by admin',
      scheduleOverlapConfirmedBy: 'admin-a',
      scheduleOverlapConfirmedAt: now,
    );
    expect(
      ClassStudentAssignment.tryFromMap(
        assignment.toMap(),
      )?.scheduleOverlapConfirmed,
      isTrue,
    );
    expect(assignment.toMap()['scheduleOverlapReason'], 'Approved by admin');
  });

  test('Institute Admin capabilities are full only within own institute', () {
    expect(
      InstituteAdminCapabilities.fullWithinInstitute,
      containsAll(InstituteAdminCapability.values),
    );
    for (final capability in InstituteAdminCapability.values) {
      expect(
        InstituteAdminCapabilities.allows(admin(), 'institute-a', capability),
        isTrue,
      );
      expect(
        InstituteAdminCapabilities.allows(admin(), 'institute-b', capability),
        isFalse,
      );
    }
  });

  test(
    'Teacher class permissions require assignment and non-archived status',
    () {
      final value = makeClass();
      final allowed = teacher(
        const TeacherPermissions(canCreateClasses: true, canEditClasses: true),
      );
      expect(
        AcademicAuthorization.canCreateClass(allowed, 'institute-a'),
        isTrue,
      );
      expect(
        AcademicAuthorization.canCreateClass(allowed, 'institute-b'),
        isFalse,
      );
      expect(AcademicAuthorization.canEditClass(allowed, value), isTrue);
      expect(
        AcademicAuthorization.canEditClass(
          allowed,
          makeClass().copyWith(teacherIds: const ['teacher-b']),
        ),
        isFalse,
      );
      expect(
        AcademicAuthorization.canEditClass(
          allowed,
          value.copyWith(status: AcademicClassStatus.archived, active: false),
        ),
        isFalse,
      );
    },
  );

  test('Teacher student permissions preserve trusted backend boundary', () {
    final value = makeStudent();
    final allowed = teacher(
      const TeacherPermissions(
        canAddStudents: true,
        canEditStudents: true,
        canViewParentContacts: true,
      ),
    );
    expect(
      AcademicAuthorization.canCreateStudent(allowed, 'institute-a'),
      isFalse,
    );
    expect(
      AcademicAuthorization.canCreateStudent(
        allowed,
        'institute-a',
        trustedBackendAvailable: true,
      ),
      isTrue,
    );
    expect(
      AcademicAuthorization.canViewParentContacts(allowed, value),
      isFalse,
    );
    expect(
      AcademicAuthorization.canViewParentContacts(
        allowed,
        value,
        assignedStudentProjection: true,
      ),
      isTrue,
    );
  });
}
