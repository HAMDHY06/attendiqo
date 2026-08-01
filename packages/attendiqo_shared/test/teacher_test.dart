import 'dart:math';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile actor({
  UserRole role = UserRole.instituteAdmin,
  String? instituteId = 'inst-a',
  bool active = true,
}) => UserProfile(
  uid: 'actor',
  email: 'actor@example.com',
  displayName: 'Actor',
  role: role,
  instituteId: instituteId,
  active: active,
  mustChangePassword: false,
  createdAt: DateTime.utc(2026, 8, 1),
  createdBy: 'seed',
  updatedAt: DateTime.utc(2026, 8, 1),
);

void main() {
  test('teacher permission drafts compare values and report changed keys', () {
    const initial = TeacherPermissions();
    final changed = initial.copyWith(
      canCreateClasses: true,
      canCorrectAttendance: true,
    );
    expect(initial, isNot(changed));
    expect(initial.changedKeys(changed), {
      'canCreateClasses',
      'canCorrectAttendance',
    });
    expect(TeacherPermissions.tryFromMap(changed.toMap()), changed);
    expect(
      TeacherPermissions.tryFromMap({...changed.toMap(), 'unknown': true}),
      isNull,
    );
  });

  test('teacher permission presets expose explicit full and no access', () {
    expect(
      TeacherPermission.values.every(TeacherPermissions.fullAccess.allows),
      isTrue,
    );
    expect(
      TeacherPermission.values.any(TeacherPermissions.noAccess.allows),
      isFalse,
    );
    expect(TeacherPermissions.attendanceAccess.canTakeAttendance, isTrue);
    expect(TeacherPermissions.attendanceAccess.canCreateClasses, isFalse);
  });

  test('safe error mapper never exposes raw backend messages', () {
    const failure = Failure(
      'FirebaseException: secret internal detail',
      code: 'permission-denied',
    );
    final message = SafeErrorMapper.fromFailure(failure);
    expect(message, contains('do not have permission'));
    expect(message, isNot(contains('FirebaseException')));
    expect(
      SafeErrorMapper.fromCode('duplicate-class-code'),
      contains('class code'),
    );
    expect(
      SafeErrorMapper.fromCode('backend-unavailable'),
      contains('not configured'),
    );
  });

  test('teacher status enum exposes the supported lifecycle', () {
    expect(TeacherStatus.values.map((value) => value.name), [
      'active',
      'disabled',
      'pendingFirstLogin',
    ]);
  });

  test('permission defaults match policy and reject unknown fields', () {
    const permissions = TeacherPermissions();
    expect(permissions.canTakeAttendance, isTrue);
    expect(permissions.canAddStudents, isTrue);
    expect(permissions.canCreateClasses, isFalse);
    expect(permissions.canCorrectAttendance, isFalse);
    expect(permissions.canSendManualNotifications, isFalse);
    expect(
      TeacherPermissions.tryFromMap({...permissions.toMap(), 'admin': true}),
      isNull,
    );
  });

  test(
    'new teacher profile is normalized, pending, and contains no password',
    () {
      final profile = UserProfile.newTeacher(
        uid: 'teacher-1',
        email: ' Teacher@Example.COM ',
        displayName: ' Teacher One ',
        instituteId: 'inst-a',
        createdBy: 'actor',
        now: DateTime.utc(2026, 8, 1),
        employeeNumber: ' emp-01 ',
      );
      expect(profile.email, 'teacher@example.com');
      expect(profile.employeeNumber, 'EMP-01');
      expect(profile.teacherStatus, TeacherStatus.pendingFirstLogin);
      expect(profile.mustChangePassword, isTrue);
      expect(profile.toMap().keys, isNot(contains('password')));
      expect(UserProfile.tryFromMap(profile.toMap())?.uid, profile.uid);
    },
  );

  test('authorization enforces institute scope and permission checks', () {
    final teacher = UserProfile.newTeacher(
      uid: 'teacher-1',
      email: 'teacher@example.com',
      displayName: 'Teacher',
      instituteId: 'inst-a',
      createdBy: 'actor',
      now: DateTime.utc(2026, 8, 1),
    );
    expect(TeacherAuthorization.canManage(actor(), teacher), isTrue);
    expect(
      TeacherAuthorization.canManage(actor(instituteId: 'inst-b'), teacher),
      isFalse,
    );
    expect(
      TeacherAuthorization.canView(
        actor(role: UserRole.superAdmin, instituteId: null),
        teacher,
      ),
      isFalse,
    );
    expect(
      TeacherAuthorization.canView(
        actor(role: UserRole.superAdmin, instituteId: null),
        teacher,
        verifiedSuperAdmin: true,
      ),
      isTrue,
    );
    expect(
      TeacherAuthorization.hasPermission(
        teacher,
        TeacherPermission.canTakeAttendance,
      ),
      isTrue,
    );
  });

  test('mock provisioning succeeds with one-time policy password', () async {
    final service = MockTeacherProvisioningService(random: Random(3));
    final result = await service.createTeacher(
      TeacherCreationRequest(
        actor: actor(),
        instituteId: 'inst-a',
        email: 'T@EXAMPLE.COM',
        displayName: 'Teacher',
        employeeNumber: 'e-1',
        permissions: const TeacherPermissions(),
      ),
    );
    expect(result.profile.role, UserRole.teacher);
    expect(result.profile.teacherStatus, TeacherStatus.pendingFirstLogin);
    expect(
      PasswordValidator.validateForCreation(result.oneTimeTemporaryPassword),
      isNull,
    );
  });

  test(
    'mock provisioning rejects duplicate email and employee number',
    () async {
      final duplicateEmail = MockTeacherProvisioningService(
        existingEmails: {'t@example.com'},
      );
      final request = TeacherCreationRequest(
        actor: actor(),
        instituteId: 'inst-a',
        email: 'T@example.com',
        displayName: 'Teacher',
        employeeNumber: 'E-1',
        permissions: const TeacherPermissions(),
      );
      await expectLater(
        duplicateEmail.createTeacher(request),
        throwsA(
          isA<Failure>().having((e) => e.code, 'code', 'duplicate-email'),
        ),
      );
      final duplicateEmployee = MockTeacherProvisioningService(
        existingEmployeeNumbers: {'inst-a_E-1'},
      );
      await expectLater(
        duplicateEmployee.createTeacher(request),
        throwsA(
          isA<Failure>().having(
            (e) => e.code,
            'code',
            'duplicate-employee-number',
          ),
        ),
      );
    },
  );

  test(
    'mock provisioning rejects cross-institute and inactive actors',
    () async {
      final service = MockTeacherProvisioningService();
      for (final invalidActor in [
        actor(instituteId: 'inst-b'),
        actor(active: false),
      ]) {
        await expectLater(
          service.createTeacher(
            TeacherCreationRequest(
              actor: invalidActor,
              instituteId: 'inst-a',
              email: 't@example.com',
              displayName: 'Teacher',
              permissions: const TeacherPermissions(),
            ),
          ),
          throwsA(isA<Failure>().having((e) => e.code, 'code', 'unauthorized')),
        );
      }
    },
  );
}
