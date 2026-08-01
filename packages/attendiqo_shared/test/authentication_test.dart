import 'dart:async';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthenticationRepository implements AuthenticationRepository {
  final controller = StreamController<AuthenticatedUser?>.broadcast();
  final profiles = <String, UserProfile>{};
  AuthFailure? signInFailure;
  bool signedOut = false;
  bool resetRequested = false;
  bool passwordUpdated = false;
  bool forceFlagCleared = false;

  @override
  Stream<AuthenticatedUser?> authStateChanges() => controller.stream;
  @override
  Future<UserProfile?> loadProfile(String uid) async => profiles[uid];
  @override
  Future<void> markLastLogin(String uid) async {}
  @override
  Future<void> clearMustChangePassword(String uid) async {
    forceFlagCleared = true;
    final current = profiles[uid]!;
    profiles[uid] = profile(
      role: current.role,
      active: current.active,
      mustChangePassword: false,
      instituteId: current.instituteId,
    );
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async =>
      resetRequested = true;
  @override
  Future<AuthenticatedUser> signIn({
    required String email,
    required String password,
  }) async {
    if (signInFailure case final failure?) throw failure;
    return AuthenticatedUser(uid: 'u1', email: email);
  }

  @override
  Future<void> signOut() async => signedOut = true;
  @override
  Future<void> updatePassword(String newPassword) async =>
      passwordUpdated = true;

  Future<void> dispose() => controller.close();
}

UserProfile profile({
  UserRole role = UserRole.teacher,
  bool active = true,
  bool mustChangePassword = false,
  String? instituteId = 'institute-1',
}) => UserProfile(
  uid: 'u1',
  email: 'user@example.com',
  displayName: 'Test User',
  role: role,
  instituteId: instituteId,
  active: active,
  mustChangePassword: mustChangePassword,
  createdAt: DateTime.utc(2026),
  createdBy: 'provisioner',
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('email validation rejects malformed values', () {
    expect(FieldValidators.email(''), 'Email is required');
    expect(FieldValidators.email('invalid'), isNotNull);
    expect(FieldValidators.email('valid@example.com'), isNull);
  });

  test('account-creation password enforces every requirement', () {
    expect(PasswordValidator.validateForCreation('Short1!'), isNotNull);
    expect(
      PasswordValidator.validateForCreation('lowercase1!'),
      contains('uppercase'),
    );
    expect(
      PasswordValidator.validateForCreation('UPPERCASE1!'),
      contains('lowercase'),
    );
    expect(
      PasswordValidator.validateForCreation('NoNumbers!!'),
      contains('number'),
    );
    expect(
      PasswordValidator.validateForCreation('NoSpecial123'),
      contains('special'),
    );
    expect(PasswordValidator.validateForCreation('SecurePass1!'), isNull);
  });

  test('roles parse only known wire values', () {
    expect(UserRoleSerialization.tryParse('superAdmin'), UserRole.superAdmin);
    expect(UserRoleSerialization.tryParse('parent'), UserRole.parent);
    expect(UserRoleSerialization.tryParse('administrator'), isNull);
  });

  test('profile institute rules are enforced', () {
    expect(
      profile(
        role: UserRole.superAdmin,
        instituteId: null,
      ).hasValidInstituteAssignment,
      isTrue,
    );
    expect(
      profile(role: UserRole.superAdmin).hasValidInstituteAssignment,
      isFalse,
    );
    expect(
      profile(
        role: UserRole.teacher,
        instituteId: null,
      ).hasValidInstituteAssignment,
      isFalse,
    );
    expect(
      profile(
        role: UserRole.parent,
        instituteId: null,
      ).hasValidInstituteAssignment,
      isTrue,
    );
  });

  test('role policy routes each supported account', () {
    expect(
      AuthenticationPolicy.evaluate(
        profile(role: UserRole.superAdmin, instituteId: null),
        AppAudience.management,
      ).destination,
      AuthDestination.superAdminDashboard,
    );
    expect(
      AuthenticationPolicy.evaluate(
        profile(role: UserRole.instituteAdmin),
        AppAudience.management,
      ).destination,
      AuthDestination.instituteAdminDashboard,
    );
    expect(
      AuthenticationPolicy.evaluate(
        profile(),
        AppAudience.management,
      ).destination,
      AuthDestination.teacherDashboard,
    );
    expect(
      AuthenticationPolicy.evaluate(
        profile(role: UserRole.parent, instituteId: null),
        AppAudience.connect,
      ).destination,
      AuthDestination.parentDashboard,
    );
  });

  test('unsupported roles are rejected with app-specific messages', () {
    final parent = AuthenticationPolicy.evaluate(
      profile(role: UserRole.parent, instituteId: null),
      AppAudience.management,
    );
    final teacher = AuthenticationPolicy.evaluate(
      profile(),
      AppAudience.connect,
    );
    expect(
      parent.error!.userMessage,
      'This account belongs to Attendiqo Connect.',
    );
    expect(
      teacher.error!.userMessage,
      'This account belongs to the Attendiqo management application.',
    );
  });

  test('inactive profile is rejected and force-change is routed', () {
    expect(
      AuthenticationPolicy.evaluate(
        profile(active: false),
        AppAudience.management,
      ).error!.code,
      AuthFailureCode.inactiveProfile,
    );
    expect(
      AuthenticationPolicy.evaluate(
        profile(mustChangePassword: true),
        AppAudience.management,
      ).destination,
      AuthDestination.changePassword,
    );
  });

  test('controller signs in, routes, resets password, and logs out', () async {
    final repository = FakeAuthenticationRepository();
    repository.profiles['u1'] = profile();
    final controller = AuthenticationController(
      repository: repository,
      audience: AppAudience.management,
    );
    await controller.signIn(
      email: 'user@example.com',
      password: 'existing-password',
    );
    expect(controller.state.destination, AuthDestination.teacherDashboard);
    expect(await controller.requestPasswordReset('user@example.com'), isTrue);
    expect(repository.resetRequested, isTrue);
    await controller.signOut();
    expect(repository.signedOut, isTrue);
    expect(controller.state.status, AuthenticationStatus.signedOut);
    controller.dispose();
    await repository.dispose();
  });

  test('repository failures expose safe mapped messages', () async {
    final repository = FakeAuthenticationRepository()
      ..signInFailure = const AuthFailure(
        AuthFailureCode.userDisabled,
        'This account has been disabled. Contact your administrator.',
      );
    final controller = AuthenticationController(
      repository: repository,
      audience: AppAudience.management,
    );
    await controller.signIn(email: 'user@example.com', password: 'anything');
    expect(controller.state.status, AuthenticationStatus.failure);
    expect(
      controller.state.message,
      'This account has been disabled. Contact your administrator.',
    );
    controller.dispose();
    await repository.dispose();
  });

  test(
    'temporary account changes password before clearing force flag',
    () async {
      final repository = FakeAuthenticationRepository();
      repository.profiles['u1'] = profile(mustChangePassword: true);
      final controller = AuthenticationController(
        repository: repository,
        audience: AppAudience.management,
      );
      await controller.signIn(
        email: 'user@example.com',
        password: 'temporary-password',
      );
      expect(controller.state.status, AuthenticationStatus.mustChangePassword);
      expect(await controller.changePassword('NewSecure1!'), isTrue);
      expect(repository.passwordUpdated, isTrue);
      expect(repository.forceFlagCleared, isTrue);
      expect(controller.state.destination, AuthDestination.teacherDashboard);
      controller.dispose();
      await repository.dispose();
    },
  );
}
