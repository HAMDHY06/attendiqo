import 'dart:async';

import 'package:attendiqo_connect/app/connect_app.dart';
import 'package:attendiqo_connect/features/authentication/presentation/connect_authentication_screens.dart';
import 'package:attendiqo_connect/features/authentication/presentation/parent_login_screen.dart';
import 'package:attendiqo_connect/theme/connect_theme.dart';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRepository
    implements
        AuthenticationRepository,
        ActiveMembershipRepository,
        MembershipWorkflowRepository {
  FakeRepository({
    this.initialUser,
    this.profile,
    this.noMembership = false,
    this.membershipOverrides = const [],
  });
  final AuthenticatedUser? initialUser;
  final UserProfile? profile;
  final bool noMembership;
  List<InstituteMembership> membershipOverrides;
  final changes = StreamController<AuthenticatedUser?>.broadcast();
  bool signedOut = false;
  bool resetRequested = false;
  UserRole? requestedRole;

  @override
  Future<List<InstituteMembership>> loadOwnMemberships(
    String authenticatedUid,
  ) async {
    if (membershipOverrides.isNotEmpty) return membershipOverrides;
    final current = profile;
    if (noMembership ||
        current == null ||
        current.role == UserRole.superAdmin) {
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
  Stream<AuthenticatedUser?> authStateChanges() async* {
    yield initialUser;
    yield* changes.stream;
  }

  @override
  Future<UserProfile?> loadProfile(String uid) async => profile;
  @override
  Future<void> markLastLogin(String uid) async {}
  @override
  Future<void> clearMustChangePassword(String uid) async {}
  @override
  Future<void> sendPasswordResetEmail(String email) async =>
      resetRequested = true;
  @override
  Future<AuthenticatedUser> signIn({
    required String email,
    required String password,
  }) async => AuthenticatedUser(uid: 'u1', email: email);
  @override
  Future<void> signOut() async {
    signedOut = true;
    changes.add(null);
  }

  @override
  Future<void> updatePassword(String newPassword) async {}
  @override
  Future<InstituteJoinRequest> requestMembership({
    required String joinCode,
    required UserRole requestedRole,
  }) async {
    this.requestedRole = requestedRole;
    return InstituteJoinRequest(
      requestId: 'safe',
      uid: '',
      instituteId: '',
      requestedRole: requestedRole,
      status: InstituteMembershipStatus.pending,
      requestedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<List<InstituteJoinRequest>> loadOwnRequests() async => const [];
  @override
  Future<List<InstituteJoinRequest>> loadReviewableRequests() async => const [];
  @override
  Future<InstituteMembershipStatus> reviewRequest({
    required String requestId,
    required bool approve,
  }) async => approve
      ? InstituteMembershipStatus.active
      : InstituteMembershipStatus.rejected;
  @override
  Future<InstituteMembershipStatus> revokeMembership(
    String membershipId,
  ) async => InstituteMembershipStatus.revoked;
  Future<void> dispose() => changes.close();
}

UserProfile testProfile(
  UserRole role, {
  bool active = true,
  bool mustChangePassword = false,
}) => UserProfile(
  uid: 'u1',
  email: 'parent@example.com',
  displayName: 'Test Parent',
  role: role,
  instituteId: role == UserRole.parent || role == UserRole.superAdmin
      ? null
      : 'institute-1',
  active: active,
  mustChangePassword: mustChangePassword,
  createdAt: DateTime.utc(2026),
  createdBy: 'provisioner',
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('theme retains Connect brand colours', () {
    expect(ConnectTheme.light().colorScheme.primary, const Color(0xFF4F46E5));
  });

  testWidgets('signed-out session shows simple parent login validation', (
    tester,
  ) async {
    final repository = FakeRepository();
    await tester.pumpWidget(
      AttendiqoConnectApp(authenticationRepository: repository),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ParentLoginScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pump();
    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    await repository.dispose();
  });

  testWidgets('blocked parent session submits a Parent Connect join request', (
    tester,
  ) async {
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(uid: 'u1', email: 'p@x.com'),
      profile: testProfile(UserRole.parent, active: true),
      noMembership: true,
    );
    await tester.pumpWidget(
      AttendiqoConnectApp(authenticationRepository: repository),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ParentMembershipAccessScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'ABCDEF');
    await tester.tap(find.text('Request Parent Connect access'));
    await tester.pump();
    expect(repository.requestedRole, UserRole.parent);
    await repository.dispose();
  });

  testWidgets(
    'Parent Connect status UI is explicit for every non-active membership',
    (tester) async {
      for (final status in [
        InstituteMembershipStatus.pending,
        InstituteMembershipStatus.rejected,
        InstituteMembershipStatus.suspended,
        InstituteMembershipStatus.revoked,
      ]) {
        final repository = FakeRepository(
          initialUser: const AuthenticatedUser(uid: 'u1', email: 'p@x.com'),
          profile: testProfile(UserRole.parent),
          membershipOverrides: [
            InstituteMembership(
              uid: 'u1',
              instituteId: 'institute-1',
              role: UserRole.parent,
              status: status,
              requestedAt: DateTime.utc(2026),
            ),
          ],
        );
        await tester.pumpWidget(
          AttendiqoConnectApp(authenticationRepository: repository),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ParentMembershipAccessScreen), findsOneWidget);
        await repository.dispose();
      }
    },
  );

  testWidgets('parent forgot-password sends a safe reset request', (
    tester,
  ) async {
    final repository = FakeRepository();
    final controller = AuthenticationController(
      repository: repository,
      audience: AppAudience.connect,
    );
    await tester.pumpWidget(
      MaterialApp(home: ConnectForgotPasswordScreen(controller: controller)),
    );
    await tester.enterText(find.byType(TextFormField), 'parent@example.com');
    await tester.tap(find.text('Send reset email'));
    await tester.pumpAndSettle();
    expect(repository.resetRequested, isTrue);
    expect(
      find.text(
        'If an eligible account exists, password-reset instructions have been sent.',
      ),
      findsOneWidget,
    );
    controller.dispose();
    await repository.dispose();
  });

  testWidgets('parent routes to dashboard', (tester) async {
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(
        uid: 'u1',
        email: 'parent@example.com',
      ),
      profile: testProfile(UserRole.parent),
    );
    await tester.pumpWidget(
      AttendiqoConnectApp(authenticationRepository: repository),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
    expect(find.text('No child selected'), findsOneWidget);
    await repository.dispose();
  });

  testWidgets('management account is rejected with management-app message', (
    tester,
  ) async {
    for (final role in [
      UserRole.superAdmin,
      UserRole.instituteAdmin,
      UserRole.teacher,
    ]) {
      final repository = FakeRepository(
        initialUser: const AuthenticatedUser(
          uid: 'u1',
          email: 'user@example.com',
        ),
        profile: testProfile(role),
      );
      await tester.pumpWidget(
        AttendiqoConnectApp(
          key: ValueKey(role),
          authenticationRepository: repository,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This account belongs to the Attendiqo management application.',
        ),
        findsOneWidget,
      );
      await repository.dispose();
    }
  });

  testWidgets('inactive parent is blocked', (tester) async {
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(
        uid: 'u1',
        email: 'parent@example.com',
      ),
      profile: testProfile(UserRole.parent, active: false),
    );
    await tester.pumpWidget(
      AttendiqoConnectApp(authenticationRepository: repository),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This account profile is inactive. Contact your administrator.',
      ),
      findsOneWidget,
    );
    await repository.dispose();
  });

  testWidgets('temporary parent routes to password change', (tester) async {
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(
        uid: 'u1',
        email: 'parent@example.com',
      ),
      profile: testProfile(UserRole.parent, mustChangePassword: true),
    );
    await tester.pumpWidget(
      AttendiqoConnectApp(authenticationRepository: repository),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create a new password'), findsOneWidget);
    await repository.dispose();
  });

  testWidgets('parent logout returns to login', (tester) async {
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(
        uid: 'u1',
        email: 'parent@example.com',
      ),
      profile: testProfile(UserRole.parent),
    );
    await tester.pumpWidget(
      AttendiqoConnectApp(authenticationRepository: repository),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.byType(ParentLoginScreen), findsOneWidget);
    expect(repository.signedOut, isTrue);
    await repository.dispose();
  });
}
