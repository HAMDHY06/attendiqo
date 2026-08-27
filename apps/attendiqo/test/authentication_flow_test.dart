import 'dart:async';

import 'package:attendiqo/app/attendiqo_app.dart';
import 'package:attendiqo/features/authentication/presentation/authentication_screens.dart';
import 'package:attendiqo/features/authentication/presentation/login_screen.dart';
import 'package:attendiqo/theme/attendiqo_theme.dart';
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
    this.resetFailure,
    this.noMembership = false,
    this.membershipOverrides = const [],
    this.reviewable = const [],
  });
  final AuthenticatedUser? initialUser;
  UserProfile? profile;
  final AuthFailure? resetFailure;
  final bool noMembership;
  List<InstituteMembership> membershipOverrides;
  List<InstituteJoinRequest> reviewable;
  final reviewed = <String>[];
  final changes = StreamController<AuthenticatedUser?>.broadcast();
  bool resetRequested = false;
  Completer<void>? resetCompleter;
  bool signedOut = false;
  bool passwordRequirementCleared = false;
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
  Future<void> clearMustChangePassword(String uid) async {
    passwordRequirementCleared = true;
    final current = profile;
    if (current?.role == UserRole.teacher) {
      profile = current!.copyWithTeacher(
        mustChangePassword: false,
        teacherStatus: TeacherStatus.active,
        updatedBy: uid,
      );
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    if (resetFailure case final failure?) throw failure;
    resetRequested = true;
    await resetCompleter?.future;
  }

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
  Future<List<InstituteJoinRequest>> loadReviewableRequests() async =>
      reviewable;
  @override
  Future<InstituteMembershipStatus> reviewRequest({
    required String requestId,
    required bool approve,
  }) async {
    reviewed.add('$requestId:$approve');
    return approve
        ? InstituteMembershipStatus.active
        : InstituteMembershipStatus.rejected;
  }

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
  email: 'user@example.com',
  displayName: 'Test User',
  role: role,
  instituteId: role == UserRole.superAdmin ? null : 'institute-1',
  active: active,
  mustChangePassword: mustChangePassword,
  createdAt: DateTime.utc(2026),
  createdBy: 'provisioner',
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('theme retains Attendiqo brand colours', () {
    expect(AttendiqoTheme.light().colorScheme.primary, const Color(0xFF4338CA));
  });

  testWidgets('signed-out session shows login and validates fields', (
    tester,
  ) async {
    final repository = FakeRepository();
    await tester.pumpWidget(AttendiqoApp(authenticationRepository: repository));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pump();
    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    await repository.dispose();
  });

  testWidgets('blocked management session submits a Teacher join request', (
    tester,
  ) async {
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(uid: 'u1', email: 'u@x.com'),
      profile: testProfile(UserRole.teacher, active: true),
      noMembership: true,
    );
    await tester.pumpWidget(AttendiqoApp(authenticationRepository: repository));
    await tester.pumpAndSettle();
    expect(find.byType(MembershipAccessScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'ABCDEF');
    await tester.tap(find.text('Request access'));
    await tester.pump();
    expect(repository.requestedRole, UserRole.teacher);
    await repository.dispose();
  });

  testWidgets(
    'membership status UI is explicit for pending rejected suspended and revoked',
    (tester) async {
      for (final status in [
        InstituteMembershipStatus.pending,
        InstituteMembershipStatus.rejected,
        InstituteMembershipStatus.suspended,
        InstituteMembershipStatus.revoked,
      ]) {
        final repository = FakeRepository(
          initialUser: const AuthenticatedUser(uid: 'u1', email: 'u@x.com'),
          profile: testProfile(UserRole.teacher),
          membershipOverrides: [
            InstituteMembership(
              uid: 'u1',
              instituteId: 'institute-1',
              role: UserRole.teacher,
              status: status,
              requestedAt: DateTime.utc(2026),
            ),
          ],
        );
        await tester.pumpWidget(
          AttendiqoApp(authenticationRepository: repository),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MembershipAccessScreen), findsOneWidget);
        await repository.dispose();
      }
    },
  );

  testWidgets('Super Admin can review Institute Admin request', (tester) async {
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(uid: 'u1', email: 's@x.com'),
      profile: testProfile(UserRole.superAdmin),
      reviewable: [
        InstituteJoinRequest(
          requestId: 'r1',
          uid: '',
          instituteId: 'i1',
          requestedRole: UserRole.instituteAdmin,
          status: InstituteMembershipStatus.pending,
          requestedAt: DateTime.utc(2026),
        ),
      ],
    );
    final controller = AuthenticationController(
      repository: repository,
      audience: AppAudience.management,
    )..start();
    await tester.pumpWidget(
      MaterialApp(home: MembershipReviewScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('instituteAdmin request'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(repository.reviewed, contains('r1:true'));
    controller.dispose();
    await repository.dispose();
  });

  testWidgets(
    'Institute Admin review is selected-institute scoped and excludes admin requests',
    (tester) async {
      final repository = FakeRepository(
        initialUser: const AuthenticatedUser(uid: 'u1', email: 'a@x.com'),
        profile: testProfile(UserRole.instituteAdmin),
        reviewable: [
          InstituteJoinRequest(
            requestId: 'teacher',
            uid: '',
            instituteId: 'institute-1',
            requestedRole: UserRole.teacher,
            status: InstituteMembershipStatus.pending,
            requestedAt: DateTime.utc(2026),
          ),
          InstituteJoinRequest(
            requestId: 'parent',
            uid: '',
            instituteId: 'institute-1',
            requestedRole: UserRole.parent,
            status: InstituteMembershipStatus.pending,
            requestedAt: DateTime.utc(2026),
          ),
          InstituteJoinRequest(
            requestId: 'other',
            uid: '',
            instituteId: 'i2',
            requestedRole: UserRole.teacher,
            status: InstituteMembershipStatus.pending,
            requestedAt: DateTime.utc(2026),
          ),
          InstituteJoinRequest(
            requestId: 'admin',
            uid: '',
            instituteId: 'institute-1',
            requestedRole: UserRole.instituteAdmin,
            status: InstituteMembershipStatus.pending,
            requestedAt: DateTime.utc(2026),
          ),
        ],
      );
      final controller = AuthenticationController(
        repository: repository,
        audience: AppAudience.management,
      )..start();
      await tester.pumpWidget(
        MaterialApp(home: MembershipReviewScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('teacher request'), findsOneWidget);
      expect(find.text('parent request'), findsOneWidget);
      expect(find.text('instituteAdmin request'), findsNothing);
      controller.dispose();
      await repository.dispose();
    },
  );

  testWidgets('Super Admin rejection uses the Worker workflow decision', (
    tester,
  ) async {
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(uid: 'u1', email: 's@x.com'),
      profile: testProfile(UserRole.superAdmin),
      reviewable: [
        InstituteJoinRequest(
          requestId: 'reject',
          uid: '',
          instituteId: 'i1',
          requestedRole: UserRole.instituteAdmin,
          status: InstituteMembershipStatus.pending,
          requestedAt: DateTime.utc(2026),
        ),
      ],
    );
    final controller = AuthenticationController(
      repository: repository,
      audience: AppAudience.management,
    )..start();
    await tester.pumpWidget(
      MaterialApp(home: MembershipReviewScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(repository.reviewed, contains('reject:false'));
    controller.dispose();
    await repository.dispose();
  });

  testWidgets(
    'Institute Admin sends approve and reject decisions only for same-institute Teacher and Parent requests',
    (tester) async {
      final repository = FakeRepository(
        initialUser: const AuthenticatedUser(uid: 'u1', email: 'a@x.com'),
        profile: testProfile(UserRole.instituteAdmin),
        reviewable: [
          InstituteJoinRequest(
            requestId: 'teacher',
            uid: '',
            instituteId: 'institute-1',
            requestedRole: UserRole.teacher,
            status: InstituteMembershipStatus.pending,
            requestedAt: DateTime.utc(2026),
          ),
          InstituteJoinRequest(
            requestId: 'parent',
            uid: '',
            instituteId: 'institute-1',
            requestedRole: UserRole.parent,
            status: InstituteMembershipStatus.pending,
            requestedAt: DateTime.utc(2026),
          ),
        ],
      );
      final controller = AuthenticationController(
        repository: repository,
        audience: AppAudience.management,
      )..start();
      await tester.pumpWidget(
        MaterialApp(home: MembershipReviewScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reject').last);
      await tester.pumpAndSettle();
      expect(
        repository.reviewed,
        containsAll(['teacher:true', 'parent:false']),
      );
      controller.dispose();
      await repository.dispose();
    },
  );

  testWidgets('Teacher and Parent cannot access reviewer controls', (
    tester,
  ) async {
    for (final role in [UserRole.teacher, UserRole.parent]) {
      final repository = FakeRepository(
        initialUser: const AuthenticatedUser(uid: 'u1', email: 'x@x.com'),
        profile: testProfile(role),
      );
      final controller = AuthenticationController(
        repository: repository,
        audience: AppAudience.management,
      )..start();
      await tester.pumpWidget(
        MaterialApp(home: MembershipReviewScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Membership approvals are unavailable for this account.'),
        findsOneWidget,
      );
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      controller.dispose();
      await repository.dispose();
    }
  });

  testWidgets('forgot-password shows validation, loading, and safe success', (
    tester,
  ) async {
    final repository = FakeRepository()..resetCompleter = Completer<void>();
    final controller = AuthenticationController(
      repository: repository,
      audience: AppAudience.management,
    );
    await tester.pumpWidget(
      MaterialApp(home: ForgotPasswordScreen(controller: controller)),
    );
    await tester.enterText(find.byType(TextFormField), 'invalid');
    await tester.tap(find.text('Send reset email'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.tap(find.text('Send reset email'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.resetCompleter!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'If an eligible account exists, password-reset instructions have been sent.',
      ),
      findsOneWidget,
    );
    controller.dispose();
    await repository.dispose();
  });

  testWidgets('forgot-password maps network and disabled-account failures', (
    tester,
  ) async {
    for (final failure in [
      const AuthFailure(
        AuthFailureCode.network,
        'Network unavailable. Check your connection and try again.',
      ),
      const AuthFailure(
        AuthFailureCode.userDisabled,
        'This account has been disabled. Contact your administrator.',
      ),
    ]) {
      final repository = FakeRepository(resetFailure: failure);
      final controller = AuthenticationController(
        repository: repository,
        audience: AppAudience.management,
      );
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(failure.code),
          home: ForgotPasswordScreen(controller: controller),
        ),
      );
      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('Send reset email'));
      await tester.pumpAndSettle();
      expect(find.text(failure.userMessage), findsOneWidget);
      controller.dispose();
      await repository.dispose();
    }
  });

  testWidgets('management roles route to their dashboards', (tester) async {
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
        AttendiqoApp(
          key: ValueKey(role),
          authenticationRepository: repository,
          superAdminBuilder: (_) =>
              const Scaffold(body: Text('Super Admin dashboard')),
          instituteAdminBuilder: (_) =>
              const Scaffold(body: Text('Institute Admin dashboard')),
        ),
      );
      await tester.pumpAndSettle();
      final title = switch (role) {
        UserRole.superAdmin => 'Super Admin dashboard',
        UserRole.instituteAdmin => 'Institute Admin dashboard',
        _ => 'Home',
      };
      expect(
        find.text(title),
        role == UserRole.teacher ? findsWidgets : findsOneWidget,
      );
      await repository.dispose();
    }
  });

  testWidgets('parent is rejected with Connect message', (tester) async {
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(
        uid: 'u1',
        email: 'user@example.com',
      ),
      profile: testProfile(UserRole.parent),
    );
    await tester.pumpWidget(AttendiqoApp(authenticationRepository: repository));
    await tester.pumpAndSettle();
    expect(
      find.text('This account belongs to Attendiqo Connect.'),
      findsOneWidget,
    );
    await repository.dispose();
  });

  testWidgets('inactive profile is blocked', (tester) async {
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(
        uid: 'u1',
        email: 'user@example.com',
      ),
      profile: testProfile(UserRole.teacher, active: false),
    );
    await tester.pumpWidget(AttendiqoApp(authenticationRepository: repository));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This account profile is inactive. Contact your administrator.',
      ),
      findsOneWidget,
    );
    await repository.dispose();
  });

  testWidgets('temporary profile routes to password change', (tester) async {
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(
        uid: 'u1',
        email: 'user@example.com',
      ),
      profile: testProfile(UserRole.teacher, mustChangePassword: true),
    );
    await tester.pumpWidget(AttendiqoApp(authenticationRepository: repository));
    await tester.pumpAndSettle();
    expect(find.text('Create a new password'), findsOneWidget);
    await repository.dispose();
  });

  testWidgets('teacher first login changes password and activates profile', (
    tester,
  ) async {
    final pending = testProfile(
      UserRole.teacher,
      mustChangePassword: true,
    ).copyWithTeacher(teacherStatus: TeacherStatus.pendingFirstLogin);
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(
        uid: 'u1',
        email: 'user@example.com',
      ),
      profile: pending,
    );
    await tester.pumpWidget(AttendiqoApp(authenticationRepository: repository));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('newPasswordField')),
      'SecurePass2!',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm new password'),
      'SecurePass2!',
    );
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(repository.passwordRequirementCleared, isTrue);
    expect(repository.profile?.teacherStatus, TeacherStatus.active);
    expect(find.text('Home'), findsWidgets);
    await repository.dispose();
  });

  testWidgets('logout returns to login', (tester) async {
    final repository = FakeRepository(
      initialUser: const AuthenticatedUser(
        uid: 'u1',
        email: 'user@example.com',
      ),
      profile: testProfile(UserRole.teacher),
    );
    await tester.pumpWidget(AttendiqoApp(authenticationRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(repository.signedOut, isTrue);
    await repository.dispose();
  });
}
