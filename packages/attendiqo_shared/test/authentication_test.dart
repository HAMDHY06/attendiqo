import 'dart:async';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthenticationRepository
    implements AuthenticationRepository, ActiveMembershipRepository {
  final controller = StreamController<AuthenticatedUser?>.broadcast();
  final profiles = <String, UserProfile>{};
  AuthFailure? signInFailure;
  AuthFailure? resetFailure;
  bool signedOut = false;
  bool resetRequested = false;
  bool passwordUpdated = false;
  bool forceFlagCleared = false;
  List<InstituteMembership> memberships = const [];

  @override
  Stream<AuthenticatedUser?> authStateChanges() => controller.stream;
  @override
  Future<UserProfile?> loadProfile(String uid) async => profiles[uid];
  @override
  Future<List<InstituteMembership>> loadOwnMemberships(
    String authenticatedUid,
  ) async {
    if (memberships.isNotEmpty) return memberships;
    final current = profiles[authenticatedUid];
    if (current == null || current.role == UserRole.superAdmin) {
      return const [];
    }
    return [
      InstituteMembership(
        uid: authenticatedUid,
        instituteId: 'institute-1',
        role: current.role,
        status: InstituteMembershipStatus.active,
        requestedAt: DateTime.utc(2026),
      ),
    ];
  }

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
  Future<void> sendPasswordResetEmail(String email) async {
    if (resetFailure case final failure?) throw failure;
    resetRequested = true;
  }

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

ActiveInstituteSession activeMembership(UserRole role) =>
    ActiveInstituteSession.fromMembership(
      InstituteMembership(
        uid: 'u1',
        instituteId: 'institute-1',
        role: role,
        status: InstituteMembershipStatus.active,
        requestedAt: DateTime.utc(2026),
      ),
    );

void main() {
  test('approved membership determines the management destination', () {
    final userProfile = profile(role: UserRole.parent);
    final decision = AuthenticationPolicy.evaluate(
      userProfile,
      AppAudience.management,
      activeMembership: ActiveInstituteSession.fromMembership(
        InstituteMembership(
          uid: userProfile.uid,
          instituteId: 'institute_b',
          role: UserRole.instituteAdmin,
          status: InstituteMembershipStatus.active,
          requestedAt: DateTime.utc(2026),
        ),
      ),
    );

    expect(decision.destination, AuthDestination.instituteAdminDashboard);
  });
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
        activeMembership: activeMembership(UserRole.instituteAdmin),
      ).destination,
      AuthDestination.instituteAdminDashboard,
    );
    expect(
      AuthenticationPolicy.evaluate(
        profile(),
        AppAudience.management,
        activeMembership: activeMembership(UserRole.teacher),
      ).destination,
      AuthDestination.teacherDashboard,
    );
    expect(
      AuthenticationPolicy.evaluate(
        profile(role: UserRole.parent, instituteId: null),
        AppAudience.connect,
        activeMembership: activeMembership(UserRole.parent),
      ).destination,
      AuthDestination.parentDashboard,
    );
  });

  test('unsupported roles are rejected with app-specific messages', () {
    final parent = AuthenticationPolicy.evaluate(
      profile(role: UserRole.parent, instituteId: null),
      AppAudience.management,
      activeMembership: activeMembership(UserRole.parent),
    );
    final teacher = AuthenticationPolicy.evaluate(
      profile(),
      AppAudience.connect,
      activeMembership: activeMembership(UserRole.teacher),
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
        activeMembership: activeMembership(UserRole.teacher),
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

  test('controller uses only active memberships from its repository', () async {
    final repository = FakeAuthenticationRepository()
      ..profiles['u1'] = profile(role: UserRole.parent)
      ..memberships = [
        InstituteMembership(
          uid: 'u1',
          instituteId: 'pending-institute',
          role: UserRole.instituteAdmin,
          status: InstituteMembershipStatus.pending,
          requestedAt: DateTime.utc(2026),
        ),
        InstituteMembership(
          uid: 'u1',
          instituteId: 'approved-institute',
          role: UserRole.instituteAdmin,
          status: InstituteMembershipStatus.active,
          requestedAt: DateTime.utc(2026),
        ),
      ];
    final controller = AuthenticationController(
      repository: repository,
      audience: AppAudience.management,
    );

    await controller.signIn(email: 'user@example.com', password: 'password');

    expect(
      controller.state.activeMembership?.instituteId,
      'approved-institute',
    );
    expect(
      controller.state.destination,
      AuthDestination.instituteAdminDashboard,
    );
    controller.dispose();
    await repository.dispose();
  });

  test('session switches only between approved active institutes', () async {
    final repository = FakeAuthenticationRepository()
      ..profiles['u1'] = profile()
      ..memberships = [
        InstituteMembership(
          uid: 'u1',
          instituteId: 'first',
          role: UserRole.teacher,
          status: InstituteMembershipStatus.active,
          requestedAt: DateTime.utc(2026),
        ),
        InstituteMembership(
          uid: 'u1',
          instituteId: 'second',
          role: UserRole.instituteAdmin,
          status: InstituteMembershipStatus.active,
          requestedAt: DateTime.utc(2026),
        ),
        InstituteMembership(
          uid: 'u1',
          instituteId: 'pending',
          role: UserRole.teacher,
          status: InstituteMembershipStatus.pending,
          requestedAt: DateTime.utc(2026),
        ),
      ];
    final controller = AuthenticationController(
      repository: repository,
      audience: AppAudience.management,
    );
    await controller.signIn(email: 'user@example.com', password: 'password');

    expect(controller.state.activeMembership?.instituteId, 'first');
    expect(await controller.selectActiveInstitute('second'), isTrue);
    expect(controller.state.activeMembership?.instituteId, 'second');
    expect(controller.state.profile?.role, UserRole.instituteAdmin);
    expect(
      controller.state.activeMembership?.canUseTeacherCapabilities,
      isTrue,
    );
    expect(await controller.selectActiveInstitute('pending'), isFalse);
    expect(controller.state.activeMembership?.instituteId, 'second');
    controller.dispose();
    await repository.dispose();
  });

  test(
    'refresh updates selectable memberships and removes a revoked selected institute',
    () async {
      final repository = FakeAuthenticationRepository()
        ..profiles['u1'] = profile()
        ..memberships = [
          InstituteMembership(
            uid: 'u1',
            instituteId: 'first',
            role: UserRole.teacher,
            status: InstituteMembershipStatus.active,
            requestedAt: DateTime.utc(2026),
          ),
        ];
      final controller = AuthenticationController(
        repository: repository,
        audience: AppAudience.management,
      );
      await controller.signIn(email: 'user@example.com', password: 'password');
      repository.memberships = [
        InstituteMembership(
          uid: 'u1',
          instituteId: 'first',
          role: UserRole.teacher,
          status: InstituteMembershipStatus.active,
          requestedAt: DateTime.utc(2026),
        ),
        InstituteMembership(
          uid: 'u1',
          instituteId: 'second',
          role: UserRole.teacher,
          status: InstituteMembershipStatus.active,
          requestedAt: DateTime.utc(2026),
        ),
      ];
      await controller.refreshMemberships();
      expect(await controller.selectActiveInstitute('second'), isTrue);
      repository.memberships = [
        InstituteMembership(
          uid: 'u1',
          instituteId: 'first',
          role: UserRole.teacher,
          status: InstituteMembershipStatus.active,
          requestedAt: DateTime.utc(2026),
        ),
        InstituteMembership(
          uid: 'u1',
          instituteId: 'second',
          role: UserRole.teacher,
          status: InstituteMembershipStatus.revoked,
          requestedAt: DateTime.utc(2026),
        ),
      ];
      await controller.refreshMemberships();
      expect(controller.state.activeMembership?.instituteId, 'first');
      expect(await controller.selectActiveInstitute('second'), isFalse);
      controller.dispose();
      await repository.dispose();
    },
  );

  test('non-active memberships cannot create an institute session', () async {
    final repository = FakeAuthenticationRepository()
      ..profiles['u1'] = profile()
      ..memberships = InstituteMembershipStatus.values
          .where((status) => status != InstituteMembershipStatus.active)
          .map(
            (status) => InstituteMembership(
              uid: 'u1',
              instituteId: status.name,
              role: UserRole.teacher,
              status: status,
              requestedAt: DateTime.utc(2026),
            ),
          )
          .toList(growable: false);
    final controller = AuthenticationController(
      repository: repository,
      audience: AppAudience.management,
    );

    await controller.signIn(email: 'user@example.com', password: 'password');

    expect(controller.state.status, AuthenticationStatus.blocked);
    expect(controller.state.activeMembership, isNull);
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
    'password recovery does not reveal an unrelated missing account',
    () async {
      final repository = FakeAuthenticationRepository()
        ..resetFailure = const AuthFailure(
          AuthFailureCode.userNotFound,
          'No account was found for this email.',
        );
      final controller = AuthenticationController(
        repository: repository,
        audience: AppAudience.management,
      );

      expect(
        await controller.requestPasswordReset('unknown@example.com'),
        isTrue,
      );
      expect(controller.state.message, isNull);
      controller.dispose();
      await repository.dispose();
    },
  );

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
