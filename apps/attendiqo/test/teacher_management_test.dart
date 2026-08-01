import 'package:attendiqo/features/teacher_management/application/teacher_management_controller.dart';
import 'package:attendiqo/features/teacher_management/presentation/teacher_management_screens.dart';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile profile({
  required String uid,
  UserRole role = UserRole.teacher,
  String? instituteId = 'inst-a',
  String? employeeNumber,
  bool active = true,
  bool mustChangePassword = false,
  TeacherStatus? status,
}) => UserProfile(
  uid: uid,
  email: '$uid@example.com',
  displayName: uid == 'teacher-two' ? 'Beta Teacher' : 'Alpha Teacher',
  role: role,
  instituteId: instituteId,
  active: active,
  mustChangePassword: mustChangePassword,
  createdAt: DateTime.utc(2026, 8, 1),
  createdBy: 'admin',
  updatedAt: DateTime.utc(2026, 8, 1),
  updatedBy: 'admin',
  employeeNumber: employeeNumber,
  permissions: role == UserRole.teacher ? const TeacherPermissions() : null,
  teacherStatus: role == UserRole.teacher
      ? status ?? (active ? TeacherStatus.active : TeacherStatus.disabled)
      : null,
);

class MemoryTeacherRepository implements TeacherRepository {
  MemoryTeacherRepository(this.values);
  final List<UserProfile> values;
  final List<AuditLogEntry> logs = [];
  String? requestedInstituteId;
  int permissionWrites = 0;
  Set<String> lastPermissionChanges = const {};
  Map<String, List<String>> classNames = const {};

  @override
  Future<List<UserProfile>> fetchTeachers({String? instituteId}) async {
    requestedInstituteId = instituteId;
    return values
        .where(
          (value) => instituteId == null || value.instituteId == instituteId,
        )
        .toList();
  }

  @override
  Future<Map<String, List<String>>> fetchAssignedClassNames({
    String? instituteId,
  }) async => classNames;

  @override
  Future<List<AuditLogEntry>> fetchAuditLogs({String? instituteId}) async =>
      logs
          .where(
            (value) => instituteId == null || value.instituteId == instituteId,
          )
          .toList();

  @override
  Future<void> updateTeacher(
    UserProfile teacher, {
    required UserProfile actor,
    bool verifiedSuperAdmin = false,
  }) async {
    final index = values.indexWhere((value) => value.uid == teacher.uid);
    values[index] = teacher;
    logs.add(
      AuditLogEntry(
        auditLogId: 'log-${logs.length}',
        actorUid: actor.uid,
        actorRole: actor.role,
        instituteId: teacher.instituteId,
        action: teacher.active
            ? AuditAction.teacherReactivated
            : AuditAction.teacherDisabled,
        targetType: AuditTargetType.teacher,
        targetId: teacher.uid,
        summary: 'Teacher status changed',
        createdAt: DateTime.utc(2026, 8, 1),
      ),
    );
  }

  @override
  Future<void> updateTeacherPermissions({
    required UserProfile actor,
    required String teacherUid,
    required String instituteId,
    required TeacherPermissions permissions,
    bool verifiedSuperAdmin = false,
  }) async {
    final index = values.indexWhere((value) => value.uid == teacherUid);
    final teacher = values[index];
    if (!TeacherAuthorization.canManage(
      actor,
      teacher,
      verifiedSuperAdmin: verifiedSuperAdmin,
    )) {
      throw const Failure('Denied', code: 'permission-denied');
    }
    lastPermissionChanges = teacher.effectiveTeacherPermissions.changedKeys(
      permissions,
    );
    permissionWrites++;
    values[index] = teacher.copyWithTeacher(permissions: permissions);
    logs.add(
      AuditLogEntry(
        auditLogId: 'permission-log-$permissionWrites',
        actorUid: actor.uid,
        actorRole: actor.role,
        instituteId: instituteId,
        action: AuditAction.teacherPermissionsChanged,
        targetType: AuditTargetType.teacher,
        targetId: teacherUid,
        summary:
            'Teacher permissions changed: ${lastPermissionChanges.join(', ')}',
        createdAt: DateTime.utc(2026, 8, 1),
      ),
    );
  }
}

TeacherManagementController makeController(
  MemoryTeacherRepository repository, {
  TeacherProvisioningService? provisioner,
  MockManagedPasswordResetService? reset,
  UserProfile? actor,
  bool verifiedSuperAdminClaim = false,
}) => TeacherManagementController(
  actor: actor ?? profile(uid: 'admin', role: UserRole.instituteAdmin),
  repository: repository,
  provisioningService: provisioner ?? MockTeacherProvisioningService(),
  passwordResetService: reset ?? MockManagedPasswordResetService(),
  verifiedSuperAdminClaim: verifiedSuperAdminClaim,
);

void main() {
  test(
    'loads only actor institute and supports search and status filters',
    () async {
      final repository = MemoryTeacherRepository([
        profile(uid: 'teacher-one', employeeNumber: 'A-1'),
        profile(uid: 'teacher-two', active: false),
        profile(uid: 'teacher-other', instituteId: 'inst-b'),
      ]);
      final controller = makeController(repository);
      await controller.load();
      expect(repository.requestedInstituteId, 'inst-a');
      expect(controller.teachers, hasLength(2));
      controller.setSearch('A-1');
      expect(controller.visibleTeachers.single.uid, 'teacher-one');
      controller.setSearch('');
      controller.setFilter(TeacherFilter.disabled);
      expect(controller.visibleTeachers.single.uid, 'teacher-two');
    },
  );

  test('Super Admin loads all teachers and filters by institute', () async {
    final repository = MemoryTeacherRepository([
      profile(uid: 'teacher-one'),
      profile(uid: 'teacher-other', instituteId: 'inst-b'),
    ]);
    final controller = makeController(
      repository,
      actor: profile(
        uid: 'super',
        role: UserRole.superAdmin,
        instituteId: null,
      ),
    );
    await controller.load();
    expect(repository.requestedInstituteId, isNull);
    controller.setInstituteFilter('inst-b');
    expect(controller.visibleTeachers.single.instituteId, 'inst-b');
  });

  test('create handles success and duplicate failures safely', () async {
    final repository = MemoryTeacherRepository([]);
    final success = makeController(repository);
    final created = await success.createTeacher(
      displayName: 'Teacher',
      email: 'teacher@example.com',
      permissions: const TeacherPermissions(),
    );
    expect(created?.profile.mustChangePassword, isTrue);
    expect(
      success.teachers.single.teacherStatus,
      TeacherStatus.pendingFirstLogin,
    );

    final duplicate = makeController(
      MemoryTeacherRepository([]),
      provisioner: MockTeacherProvisioningService(
        existingEmails: {'teacher@example.com'},
      ),
    );
    expect(
      await duplicate.createTeacher(
        displayName: 'Teacher',
        email: 'teacher@example.com',
        permissions: const TeacherPermissions(),
      ),
      isNull,
    );
    expect(duplicate.error, contains('already uses'));
  });

  test('disable, reactivate, reset, and audit flows preserve policy', () async {
    final teacher = profile(uid: 'teacher-one');
    final repository = MemoryTeacherRepository([teacher]);
    final reset = MockManagedPasswordResetService();
    final controller = makeController(repository, reset: reset);
    await controller.load();
    expect(await controller.setActive(teacher, false), isTrue);
    expect(controller.teachers.single.teacherStatus, TeacherStatus.disabled);
    expect(
      await controller.setActive(controller.teachers.single, true),
      isTrue,
    );
    expect(controller.teachers.single.teacherStatus, TeacherStatus.active);
    expect(
      (await controller.sendPasswordReset(
        controller.teachers.single,
      )).succeeded,
      isTrue,
    );
    expect(reset.requests.single.target.uid, teacher.uid);
    expect(
      repository.logs.map((value) => value.action),
      contains(AuditAction.teacherDisabled),
    );
  });

  testWidgets(
    'create form validates fields and shows temporary password once',
    (tester) async {
      final controller = makeController(MemoryTeacherRepository([]));
      await tester.pumpWidget(
        MaterialApp(home: CreateTeacherScreen(controller: controller)),
      );
      await tester.tap(find.byKey(const Key('submitTeacher')));
      await tester.pump();
      expect(find.text('Display name is required'), findsOneWidget);
      expect(find.text('Email is required'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('teacherDisplayName')),
        'Teacher One',
      );
      await tester.enterText(
        find.byKey(const Key('teacherEmail')),
        'teacher@example.com',
      );
      await tester.tap(find.byKey(const Key('submitTeacher')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('teacherTemporaryPassword')), findsOneWidget);
      expect(find.textContaining('shown only once'), findsOneWidget);
    },
  );

  testWidgets('disable requires confirmation and permissions can be changed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final teacher = profile(uid: 'teacher-one');
    final controller = makeController(MemoryTeacherRepository([teacher]));
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherDetailsScreen(
          controller: controller,
          initialTeacher: teacher,
        ),
      ),
    );
    await tester.tap(find.text('Disable teacher'));
    await tester.pumpAndSettle();
    expect(find.text('Disable teacher?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDisableTeacher')));
    await tester.pumpAndSettle();
    expect(find.text('Disabled'), findsWidgets);

    await tester.pumpWidget(
      const MaterialApp(
        home: TeacherPermissionsScreen(initial: TeacherPermissions()),
      ),
    );
    expect(
      find.byKey(const Key('permission-canTakeAttendance')),
      findsOneWidget,
    );
  });

  testWidgets(
    'permission switches remain local and one Save Changes persists all',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final teacher = profile(uid: 'teacher-one');
      final repository = MemoryTeacherRepository([teacher]);
      final controller = makeController(repository);
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          home: TeacherPermissionsScreen(
            initial: teacher.effectiveTeacherPermissions,
            controller: controller,
            teacher: teacher,
          ),
        ),
      );
      final save = find.byKey(const Key('savePermissionChanges'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(find.byKey(const Key('permission-canCreateClasses')));
      await tester.tap(
        find.byKey(const Key('permission-canCorrectAttendance')),
      );
      await tester.pump();
      expect(repository.permissionWrites, 0);
      expect(find.byKey(const Key('unsavedPermissionChanges')), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.drag(find.byType(ListView), const Offset(0, -240));
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repository.permissionWrites, 1);
      expect(
        repository.lastPermissionChanges,
        containsAll(['canCreateClasses', 'canCorrectAttendance']),
      );
      expect(
        repository.logs.where(
          (entry) => entry.action == AuditAction.teacherPermissionsChanged,
        ),
        hasLength(1),
      );
    },
  );

  testWidgets('permission screen warns before discarding an unsaved draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TeacherPermissionsScreen(initial: TeacherPermissions()),
      ),
    );
    await tester.tap(find.byKey(const Key('permission-canCreateClasses')));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
  });

  testWidgets('Full access preset enables every teacher permission locally', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: TeacherPermissionsScreen(initial: TeacherPermissions.noAccess),
      ),
    );
    await tester.tap(find.byKey(const Key('permissionPresetFullAccess')));
    await tester.pump();
    for (final permission in TeacherPermission.values) {
      final finder = find.byKey(Key('permission-${permission.name}'));
      await tester.scrollUntilVisible(finder, 180);
      final tile = tester.widget<SwitchListTile>(finder);
      expect(tile.value, isTrue, reason: permission.name);
    }
    await tester.scrollUntilVisible(
      find.byKey(const Key('unsavedPermissionChanges')),
      180,
    );
    expect(find.byKey(const Key('unsavedPermissionChanges')), findsOneWidget);
  });

  testWidgets('Institute Admin sees explicit full-access guidance', (
    tester,
  ) async {
    final controller = makeController(MemoryTeacherRepository([]));
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherDashboardScreen(
          controller: controller,
          onLogout: () async {},
        ),
      ),
    );
    expect(find.text('Full admin access'), findsOneWidget);
    expect(
      find.textContaining('create and edit institute classes'),
      findsOneWidget,
    );
  });

  testWidgets('edit icons follow institute and verified-role policy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ownTeacher = profile(uid: 'teacher-one');
    final otherTeacher = profile(uid: 'teacher-other', instituteId: 'inst-b');
    final ownController = makeController(MemoryTeacherRepository([ownTeacher]));
    await ownController.load();
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherDashboardScreen(
          controller: ownController,
          onLogout: () async {},
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('edit-teacher-teacher-one')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('edit-teacher-teacher-one')), findsOneWidget);

    final otherController = makeController(
      MemoryTeacherRepository([otherTeacher]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherDetailsScreen(
          controller: otherController,
          initialTeacher: otherTeacher,
        ),
      ),
    );
    expect(
      find.byKey(const Key('edit-teacher-detail-teacher-other')),
      findsNothing,
    );

    for (final role in [UserRole.teacher, UserRole.parent]) {
      final unauthorized = makeController(
        MemoryTeacherRepository([ownTeacher]),
        actor: profile(uid: 'viewer-$role', role: role),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TeacherDetailsScreen(
            controller: unauthorized,
            initialTeacher: ownTeacher,
          ),
        ),
      );
      expect(
        find.byKey(const Key('edit-teacher-detail-teacher-one')),
        findsNothing,
      );
    }

    final unverifiedSuper = makeController(
      MemoryTeacherRepository([ownTeacher]),
      actor: profile(
        uid: 'super',
        role: UserRole.superAdmin,
        instituteId: null,
      ),
    );
    expect(unverifiedSuper.canEditTeacher(ownTeacher), isFalse);
    final verifiedSuper = makeController(
      MemoryTeacherRepository([ownTeacher]),
      actor: profile(
        uid: 'super',
        role: UserRole.superAdmin,
        instituteId: null,
      ),
      verifiedSuperAdminClaim: true,
    );
    expect(verifiedSuper.canEditTeacher(ownTeacher), isTrue);
  });

  testWidgets('teacher and academic cards fit a small Android screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final teacher = profile(uid: 'teacher-one', employeeNumber: 'EMP-1');
    final controller = makeController(MemoryTeacherRepository([teacher]));
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: TeacherDashboardScreen(
          controller: controller,
          onLogout: () async {},
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
