import 'dart:async';

import 'package:attendiqo/features/password_recovery/application/managed_password_reset_controller.dart';
import 'package:attendiqo/features/password_recovery/data/firestore_teacher_password_recovery_repository.dart';
import 'package:attendiqo/features/password_recovery/presentation/institute_admin_password_recovery_screen.dart';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryTeacherRecoveryRepository
    implements TeacherPasswordRecoveryRepository {
  MemoryTeacherRecoveryRepository(this.values);
  final List<UserProfile> values;
  @override
  Future<List<UserProfile>> fetchTeachers(String instituteId) async => values;
}

class DelayedResetService implements ManagedPasswordResetService {
  final completer = Completer<PasswordResetResult>();
  @override
  Future<PasswordResetResult> sendPasswordResetEmail(
    ManagedPasswordResetRequest request,
  ) => completer.future;
}

class NoopAuthenticationRepository implements AuthenticationRepository {
  @override
  Stream<AuthenticatedUser?> authStateChanges() => const Stream.empty();
  @override
  Future<void> clearMustChangePassword(String uid) async {}
  @override
  Future<UserProfile?> loadProfile(String uid) async => null;
  @override
  Future<void> markLastLogin(String uid) async {}
  @override
  Future<void> sendPasswordResetEmail(String email) async {}
  @override
  Future<AuthenticatedUser> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<void> signOut() async {}
  @override
  Future<void> updatePassword(String newPassword) async {}
}

UserProfile profile({
  required String uid,
  required UserRole role,
  bool active = true,
  String email = 'user@example.com',
}) => UserProfile(
  uid: uid,
  email: email,
  displayName: uid,
  role: role,
  instituteId: role == UserRole.superAdmin ? null : 'i1',
  active: active,
  mustChangePassword: false,
  createdAt: DateTime.utc(2026, 8, 1),
  createdBy: 'super',
  updatedAt: DateTime.utc(2026, 8, 1),
);

void main() {
  testWidgets('Institute Admin reset action shows loading and safe success', (
    tester,
  ) async {
    final actor = profile(uid: 'admin', role: UserRole.instituteAdmin);
    final teacher = profile(uid: 'teacher', role: UserRole.teacher);
    final service = DelayedResetService();
    final controller = ManagedPasswordResetController(
      actor: actor,
      service: service,
      teacherRepository: MemoryTeacherRecoveryRepository([teacher]),
    );
    final auth = AuthenticationController(
      repository: NoopAuthenticationRepository(),
      audience: AppAudience.management,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InstituteAdminArea(
          authController: auth,
          resetController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send Password Reset Email'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    service.completer.complete(PasswordResetResult.safeSuccess);
    await tester.pumpAndSettle();
    expect(find.text(PasswordResetResult.safeSuccess.message), findsOneWidget);
    expect(find.textContaining('existing password'), findsOneWidget);
  });

  testWidgets('disabled Teacher account has a disabled reset action', (
    tester,
  ) async {
    final actor = profile(uid: 'admin', role: UserRole.instituteAdmin);
    final teacher = profile(
      uid: 'teacher',
      role: UserRole.teacher,
      active: false,
    );
    final controller = ManagedPasswordResetController(
      actor: actor,
      service: MockManagedPasswordResetService(),
      teacherRepository: MemoryTeacherRecoveryRepository([teacher]),
    );
    final auth = AuthenticationController(
      repository: NoopAuthenticationRepository(),
      audience: AppAudience.management,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InstituteAdminArea(
          authController: auth,
          resetController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send Password Reset Email'),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('Disabled'), findsOneWidget);
  });

  test('controller exposes network and invalid-email states', () async {
    final actor = profile(uid: 'admin', role: UserRole.instituteAdmin);
    final networkService = MockManagedPasswordResetService(
      nextStatus: PasswordResetStatus.networkError,
    );
    final controller = ManagedPasswordResetController(
      actor: actor,
      service: networkService,
    );
    final teacher = profile(uid: 'teacher', role: UserRole.teacher);
    expect(
      (await controller.send(teacher)).status,
      PasswordResetStatus.networkError,
    );
    final invalid = profile(
      uid: 'invalid',
      role: UserRole.teacher,
      email: 'invalid',
    );
    expect(
      (await controller.send(invalid)).status,
      PasswordResetStatus.invalidEmail,
    );
  });
}
