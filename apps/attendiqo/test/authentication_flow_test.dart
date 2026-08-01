import 'dart:async';

import 'package:attendiqo/app/attendiqo_app.dart';
import 'package:attendiqo/features/authentication/presentation/login_screen.dart';
import 'package:attendiqo/theme/attendiqo_theme.dart';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRepository implements AuthenticationRepository {
  FakeRepository({this.initialUser, this.profile});
  final AuthenticatedUser? initialUser;
  UserProfile? profile;
  final changes = StreamController<AuthenticatedUser?>.broadcast();
  bool resetRequested = false;
  bool signedOut = false;

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
        AttendiqoApp(key: ValueKey(role), authenticationRepository: repository),
      );
      await tester.pumpAndSettle();
      final title = switch (role) {
        UserRole.superAdmin => 'Super Admin dashboard',
        UserRole.instituteAdmin => 'Institute Admin dashboard',
        _ => 'Teacher dashboard',
      };
      expect(find.text(title), findsOneWidget);
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
