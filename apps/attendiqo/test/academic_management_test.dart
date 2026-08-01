import 'dart:async';

import 'package:attendiqo/features/academic_management/application/academic_management_controller.dart';
import 'package:attendiqo/features/academic_management/presentation/academic_management_screens.dart';
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
      List.of(students);
  @override
  Future<Student> createStudent(Student value, UserProfile actor) async {
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
