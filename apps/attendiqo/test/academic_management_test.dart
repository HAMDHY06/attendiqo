import 'dart:async';

import 'package:attendiqo/features/academic_management/application/academic_management_controller.dart';
import 'package:attendiqo/features/academic_management/presentation/academic_management_screens.dart';
import 'package:attendiqo/core/widgets/app_components.dart';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryAcademicRepository implements AcademicRepository {
  final classes = <AcademicClass>[];
  final students = <Student>[];
  final assignments = <ClassStudentAssignment>[];
  final changes = <ClassScheduleChange>[];
  final teacherProfiles = <UserProfile>[];
  Failure? createFailure;
  Completer<void>? createBlocker;
  int createCalls = 0;
  int classFetches = 0;
  Failure? createStudentFailure;
  Completer<void>? createStudentBlocker;
  int createStudentCalls = 0;
  int studentFetches = 0;

  @override
  Future<List<AcademicClass>> fetchClasses(UserProfile actor) async =>
      (classFetches++, List.of(classes)).$2;
  @override
  Future<AcademicClass> createClass(
    AcademicClass value,
    UserProfile actor,
  ) async {
    createCalls++;
    if (createBlocker != null) await createBlocker!.future;
    if (createFailure != null) throw createFailure!;
    classes.add(value);
    return value;
  }

  @override
  Future<void> updateClass(AcademicClass value, UserProfile actor) async {
    classes[classes.indexWhere((e) => e.classId == value.classId)] = value;
  }

  @override
  Future<List<Student>> fetchStudents(UserProfile actor) async =>
      (studentFetches++, List.of(students)).$2;
  @override
  Future<Student> createStudent(Student value, UserProfile actor) async {
    createStudentCalls++;
    if (createStudentBlocker != null) await createStudentBlocker!.future;
    if (createStudentFailure != null) throw createStudentFailure!;
    students.add(value);
    return value;
  }

  @override
  Future<void> updateStudent(Student value, UserProfile actor) async {
    students[students.indexWhere((e) => e.studentId == value.studentId)] =
        value;
  }

  @override
  Future<List<ClassStudentAssignment>> fetchAssignments(
    UserProfile actor, {
    String? classId,
    String? studentId,
  }) async => List.of(assignments);
  @override
  Future<void> saveAssignment(
    ClassStudentAssignment value,
    UserProfile actor,
  ) async {
    final index = assignments.indexWhere(
      (e) => e.assignmentId == value.assignmentId,
    );
    if (index < 0) {
      assignments.add(value);
    } else {
      assignments[index] = value;
    }
  }

  @override
  Future<List<ClassScheduleChange>> fetchScheduleChanges(
    UserProfile actor, {
    String? classId,
  }) async => List.of(changes);
  @override
  Future<void> saveScheduleChange(
    ClassScheduleChange value,
    UserProfile actor,
  ) async => changes.add(value);
  @override
  Future<List<UserProfile>> fetchTeachersForAcademic(UserProfile actor) async =>
      teacherProfiles.isEmpty ? const [] : List.of(teacherProfiles);
  @override
  Future<List<AuditLogEntry>> fetchAuditLogs({String? instituteId}) async =>
      const [];
}

void main() {
  final now = DateTime.utc(2026, 8, 1);
  final actor = UserProfile(
    uid: 'admin-a',
    email: 'admin@example.com',
    displayName: 'Admin',
    role: UserRole.instituteAdmin,
    instituteId: 'institute-a',
    active: true,
    mustChangePassword: false,
    createdAt: now,
    createdBy: 'super',
    updatedAt: now,
  );

  AcademicClass makeClass(String id, String name, AcademicClassStatus status) =>
      AcademicClass.newClass(
        classId: id,
        instituteId: 'institute-a',
        classCode: id.toUpperCase(),
        name: name,
        subject: 'Science',
        daysOfWeek: const {ClassWeekday.monday},
        startTime: const LocalTime(8, 0),
        endTime: const LocalTime(9, 0),
        academicYear: 2026,
        now: now,
        actorUid: actor.uid,
      ).copyWith(active: status == AcademicClassStatus.active, status: status);

  test('class search and status filtering are deterministic', () async {
    final repository = _MemoryAcademicRepository()
      ..classes.addAll([
        makeClass('CLS-A', 'Alpha', AcademicClassStatus.active),
        makeClass('CLS-B', 'Beta', AcademicClassStatus.archived),
      ]);
    final controller = AcademicManagementController(
      actor: actor,
      repository: repository,
    );
    await controller.load();
    controller.setClassSearch('alpha');
    expect(controller.visibleClasses.single.name, 'Alpha');
    controller.setClassSearch('');
    controller.setClassFilter(AcademicClassFilter.archived);
    expect(controller.visibleClasses.single.name, 'Beta');
  });

  testWidgets('overview metric grid always uses two columns', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OverviewMetricGrid(
            children: [
              StatisticCard(label: 'One', value: '1', icon: Icons.one_k),
              StatisticCard(label: 'Two', value: '2', icon: Icons.two_k),
              StatisticCard(label: 'Three', value: '3', icon: Icons.three_k),
            ],
          ),
        ),
      ),
    );
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
  });

  test('student enrolment overlap requires explicit reason', () async {
    final repository = _MemoryAcademicRepository();
    final first = makeClass('CLS-A', 'Alpha', AcademicClassStatus.active);
    final second = makeClass('CLS-B', 'Beta', AcademicClassStatus.active);
    final student = Student(
      studentId: 'student-a',
      instituteId: 'institute-a',
      studentNumber: 'STU-A',
      fullName: 'Student A',
      primaryParentName: 'Parent',
      primaryParentMobile: '+94771234567',
      status: StudentStatus.active,
      qrToken: List.filled(64, 'a').join(),
      createdAt: now,
      createdBy: actor.uid,
      updatedAt: now,
    );
    repository.classes.addAll([first, second]);
    repository.students.add(student);
    repository.assignments.add(
      ClassStudentAssignment(
        assignmentId: 'CLS-A_student-a',
        instituteId: 'institute-a',
        classId: first.classId,
        studentId: student.studentId,
        active: true,
        joinedAt: now,
        joinedBy: actor.uid,
        status: ClassStudentAssignmentStatus.active,
        scheduleOverlapConfirmed: false,
      ),
    );
    final controller = AcademicManagementController(
      actor: actor,
      repository: repository,
    );
    await controller.load();
    expect(
      await controller.assignStudent(student: student, academicClass: second),
      isFalse,
    );
    expect(
      await controller.assignStudent(
        student: student,
        academicClass: second,
        overlapConfirmed: true,
        overlapReason: 'Approved',
      ),
      isTrue,
    );
  });

  test('student creation safely normalizes null optional fields', () async {
    final repository = _MemoryAcademicRepository();
    final controller = AcademicManagementController(
      actor: actor,
      repository: repository,
    );
    final student = await controller.createStudent(
      studentNumber: 'STU-NEW',
      fullName: 'Student New',
      primaryParentName: 'Primary Parent',
      primaryParentMobile: '0771234567',
    );
    expect(student, isNotNull);
    expect(student!.secondaryParentMobile, isNull);
    expect(student.emergencyContactMobile, isNull);
    expect(repository.createStudentCalls, 1);
    expect(controller.error, isNull);
  });

  test(
    'student creation with a missing institute is safe and visible',
    () async {
      final superAdminWithoutInstitute = UserProfile(
        uid: 'super-a',
        email: 'super@example.com',
        displayName: 'Super',
        role: UserRole.superAdmin,
        instituteId: null,
        active: true,
        mustChangePassword: false,
        createdAt: now,
        createdBy: 'system',
        updatedAt: now,
      );
      final controller = AcademicManagementController(
        actor: superAdminWithoutInstitute,
        repository: _MemoryAcademicRepository(),
      );
      final student = await controller.createStudent(
        studentNumber: 'STU-NEW',
        fullName: 'Student New',
        primaryParentName: 'Primary Parent',
        primaryParentMobile: '0771234567',
      );
      expect(student, isNull);
      expect(controller.error, 'Your account is not assigned to an institute.');
    },
  );

  test('student creation rejects a missing profile identity safely', () async {
    final missingIdentity = UserProfile(
      uid: '',
      email: 'missing@example.com',
      displayName: 'Missing',
      role: UserRole.instituteAdmin,
      instituteId: 'institute-a',
      active: true,
      mustChangePassword: false,
      createdAt: now,
      createdBy: 'system',
      updatedAt: now,
    );
    final controller = AcademicManagementController(
      actor: missingIdentity,
      repository: _MemoryAcademicRepository(),
    );
    final student = await controller.createStudent(
      studentNumber: 'STU-MISSING',
      fullName: 'Student Missing',
      primaryParentName: 'Primary Parent',
      primaryParentMobile: '0771234567',
    );
    expect(student, isNull);
    expect(
      controller.error,
      'Your account profile is unavailable. Please sign in again.',
    );
  });

  test(
    'student creation blocks a duplicate submission and resets loading',
    () async {
      final repository = _MemoryAcademicRepository()
        ..createStudentBlocker = Completer<void>();
      final controller = AcademicManagementController(
        actor: actor,
        repository: repository,
      );
      final first = controller.createStudent(
        studentNumber: 'STU-ONE',
        fullName: 'Student One',
        primaryParentName: 'Primary Parent',
        primaryParentMobile: '0771234567',
      );
      expect(controller.saving, isTrue);
      expect(
        await controller.createStudent(
          studentNumber: 'STU-TWO',
          fullName: 'Student Two',
          primaryParentName: 'Primary Parent',
          primaryParentMobile: '0771234567',
        ),
        isNull,
      );
      expect(repository.createStudentCalls, 1);
      repository.createStudentBlocker!.complete();
      expect(await first, isNotNull);
      expect(controller.saving, isFalse);
    },
  );

  test('student creation maps duplicate numbers to a safe error', () async {
    final repository = _MemoryAcademicRepository()
      ..createStudentFailure = const Failure(
        'FirebaseException: permission-denied internal detail',
        code: 'duplicate-student-number',
      );
    final controller = AcademicManagementController(
      actor: actor,
      repository: repository,
    );
    final student = await controller.createStudent(
      studentNumber: 'STU-DUP',
      fullName: 'Student Duplicate',
      primaryParentName: 'Primary Parent',
      primaryParentMobile: '0771234567',
    );
    expect(student, isNull);
    expect(controller.error, contains('already used'));
    expect(controller.error, isNot(contains('FirebaseException')));
    expect(controller.saving, isFalse);
  });

  testWidgets(
    'academic shell shows empty states and reaches create-class form',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = AcademicManagementController(
        actor: actor,
        repository: _MemoryAcademicRepository(),
      );
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          home: AcademicManagementShell(
            controller: controller,
            onLogout: () async {},
          ),
        ),
      );
      await tester.tap(find.text('Classes'));
      await tester.pumpAndSettle();
      expect(
        find.text('No classes match this search and filter.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Create class'));
      await tester.pumpAndSettle();
      expect(find.text('Create class'), findsWidgets);
      final submit = find.byKey(const Key('submitClassButton')).last;
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('Class code is required'), findsOneWidget);
      expect(find.text('Class name is required'), findsOneWidget);
    },
  );

  testWidgets(
    'student form validates required fields and shows safe failures',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _MemoryAcademicRepository()
        ..createStudentFailure = const Failure(
          'FirebaseException: permission-denied raw detail',
          code: 'permission-denied',
        );
      final controller = AcademicManagementController(
        actor: actor,
        repository: repository,
      );
      await tester.pumpWidget(
        MaterialApp(home: CreateStudentScreen(controller: controller)),
      );
      await tester.tap(find.byKey(const Key('submitStudentButton')));
      await tester.pump();
      expect(find.text('Student number is required'), findsOneWidget);
      expect(find.text('This field is required'), findsNWidgets(2));
      expect(
        find.text('Primary parent mobile number is required'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Student number'),
        'STU-UI',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full name'),
        'Student UI',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Primary parent/guardian name'),
        'Primary Parent',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Primary parent mobile'),
        '0771234567',
      );
      await tester.ensureVisible(find.byKey(const Key('submitStudentButton')));
      await tester.tap(find.byKey(const Key('submitStudentButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('createStudentError')), findsOneWidget);
      expect(find.textContaining('do not have permission'), findsWidgets);
      expect(find.textContaining('FirebaseException'), findsNothing);
      expect(find.text('Student UI'), findsOneWidget);
      expect(controller.saving, isFalse);
    },
  );

  testWidgets('successful class creation refreshes and updates the list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryAcademicRepository();
    final controller = AcademicManagementController(
      actor: actor,
      repository: repository,
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: AcademicManagementShell(
          controller: controller,
          onLogout: () async {},
        ),
      ),
    );
    await tester.tap(find.text('Classes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openCreateClassButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Class code'),
      'SCI-1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Class name'),
      'Science One',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Subject'),
      'Science',
    );
    await tester.ensureVisible(find.byKey(const Key('submitClassButton')));
    await tester.tap(find.byKey(const Key('submitClassButton')));
    await tester.pumpAndSettle();
    expect(find.text('Science One'), findsWidgets);
    expect(repository.createCalls, 1);
    expect(repository.classFetches, greaterThanOrEqualTo(2));
  });

  testWidgets('failed class creation shows a safe error and keeps form data', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryAcademicRepository()
      ..createFailure = const Failure(
        'FirebaseException: permission-denied raw detail',
        code: 'permission-denied',
      );
    final controller = AcademicManagementController(
      actor: actor,
      repository: repository,
    );
    await tester.pumpWidget(
      MaterialApp(home: CreateClassScreen(controller: controller)),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Class code'),
      'SCI-2',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Class name'),
      'Preserved name',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Subject'),
      'Science',
    );
    await tester.ensureVisible(find.byKey(const Key('submitClassButton')));
    await tester.tap(find.byKey(const Key('submitClassButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('createClassError')), findsOneWidget);
    expect(find.textContaining('do not have permission'), findsWidgets);
    expect(find.textContaining('FirebaseException'), findsNothing);
    expect(find.text('Preserved name'), findsOneWidget);
    expect(controller.saving, isFalse);
  });

  test('double class submission is blocked and loading resets', () async {
    final repository = _MemoryAcademicRepository()
      ..createBlocker = Completer<void>();
    final controller = AcademicManagementController(
      actor: actor,
      repository: repository,
    );
    final first = controller.createClass(
      code: 'SCI-3',
      name: 'Science',
      subject: 'Science',
      start: const LocalTime(8, 0),
      end: const LocalTime(9, 0),
      days: const {ClassWeekday.monday},
      academicYear: 2026,
      teacherIds: const [],
    );
    expect(controller.saving, isTrue);
    expect(
      await controller.createClass(
        code: 'SCI-4',
        name: 'Other',
        subject: 'Science',
        start: const LocalTime(8, 0),
        end: const LocalTime(9, 0),
        days: const {ClassWeekday.monday},
        academicYear: 2026,
        teacherIds: const [],
      ),
      isNull,
    );
    expect(repository.createCalls, 1);
    repository.createBlocker!.complete();
    expect(await first, isNotNull);
    expect(controller.saving, isFalse);
  });

  testWidgets('academic class list has no overflow on a small Android screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemoryAcademicRepository()
      ..classes.add(makeClass('CLS-A', 'Alpha', AcademicClassStatus.active));
    final controller = AcademicManagementController(
      actor: actor,
      repository: repository,
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: AcademicManagementShell(
          controller: controller,
          onLogout: () async {},
        ),
      ),
    );
    await tester.tap(find.text('Classes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('teacher permission refresh enables Create Class', (
    tester,
  ) async {
    final teacher = UserProfile(
      uid: 'teacher-a',
      email: 'teacher@example.com',
      displayName: 'Teacher A',
      role: UserRole.teacher,
      instituteId: 'institute-a',
      active: true,
      mustChangePassword: false,
      createdAt: now,
      createdBy: actor.uid,
      updatedAt: now,
      updatedBy: actor.uid,
      permissions: TeacherPermissions.noAccess,
      teacherStatus: TeacherStatus.active,
    );
    final repository = _MemoryAcademicRepository()
      ..teacherProfiles.add(teacher);
    final controller = AcademicManagementController(
      actor: teacher,
      repository: repository,
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: AcademicManagementShell(
          controller: controller,
          onLogout: () async {},
        ),
      ),
    );
    await tester.tap(find.text('Classes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('openCreateClassButton')), findsNothing);

    repository.teacherProfiles[0] = teacher.copyWithTeacher(
      permissions: TeacherPermissions.fullAccess,
    );
    await controller.load();
    await tester.pump();
    expect(find.byKey(const Key('openCreateClassButton')), findsOneWidget);
  });

  test(
    'Teacher class creation auto-assigns self and denies unassigned edits',
    () async {
      final teacher = UserProfile(
        uid: 'teacher-a',
        email: 'teacher@example.com',
        displayName: 'Teacher A',
        role: UserRole.teacher,
        instituteId: 'institute-a',
        active: true,
        mustChangePassword: false,
        createdAt: now,
        createdBy: actor.uid,
        updatedAt: now,
        updatedBy: actor.uid,
        permissions: const TeacherPermissions(
          canCreateClasses: true,
          canEditClasses: true,
        ),
        teacherStatus: TeacherStatus.active,
      );
      final repository = _MemoryAcademicRepository();
      final controller = AcademicManagementController(
        actor: teacher,
        repository: repository,
      );
      final created = await controller.createClass(
        code: 'OWN-1',
        name: 'Teacher class',
        subject: 'Science',
        start: const LocalTime(8, 0),
        end: const LocalTime(9, 0),
        days: const {ClassWeekday.monday},
        academicYear: 2026,
        teacherIds: const ['unrelated-teacher'],
        primaryTeacherId: 'unrelated-teacher',
      );
      expect(created, isNotNull);
      expect(created!.teacherIds, ['teacher-a']);
      expect(created.primaryTeacherId, 'teacher-a');
      expect(created.createdBy, 'teacher-a');

      final unrelated =
          makeClass(
            'UNASSIGNED',
            'Unassigned',
            AcademicClassStatus.active,
          ).copyWith(
            teacherIds: const ['teacher-b'],
            primaryTeacherId: 'teacher-b',
          );
      expect(await controller.updateClass(unrelated), isFalse);
      expect(controller.error, contains('assigned'));
    },
  );

  testWidgets('Teacher navigation hides unauthorized destinations', (
    tester,
  ) async {
    final teacher = UserProfile(
      uid: 'teacher-a',
      email: 'teacher@example.com',
      displayName: 'Teacher A',
      role: UserRole.teacher,
      instituteId: 'institute-a',
      active: true,
      mustChangePassword: false,
      createdAt: now,
      createdBy: actor.uid,
      updatedAt: now,
      permissions: TeacherPermissions.noAccess,
      teacherStatus: TeacherStatus.active,
    );
    final controller = AcademicManagementController(
      actor: teacher,
      repository: _MemoryAcademicRepository(),
    );
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: AcademicManagementShell(
          controller: controller,
          onLogout: () async {},
        ),
      ),
    );
    expect(find.text('Students'), findsNothing);
    expect(find.text('Attendance'), findsNothing);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Profile'), findsOneWidget);
  });
}
