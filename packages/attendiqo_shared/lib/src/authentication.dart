import 'dart:async';

import 'package:flutter/foundation.dart';

import 'enums.dart';
import 'models.dart';
import 'validation.dart';

class AuthenticatedUser {
  const AuthenticatedUser({required this.uid, required this.email});
  final String uid;
  final String email;
}

class AuthFailure implements Exception {
  const AuthFailure(this.code, this.userMessage);
  final AuthFailureCode code;
  final String userMessage;
}

abstract interface class AuthenticationRepository {
  Stream<AuthenticatedUser?> authStateChanges();
  Future<AuthenticatedUser> signIn({
    required String email,
    required String password,
  });
  Future<void> signOut();
  Future<void> sendPasswordResetEmail(String email);
  Future<void> updatePassword(String newPassword);
  Future<UserProfile?> loadProfile(String uid);
  Future<void> markLastLogin(String uid);
  Future<void> clearMustChangePassword(String uid);
}

class UnavailableAuthenticationRepository implements AuthenticationRepository {
  const UnavailableAuthenticationRepository();
  static const _message =
      'Authentication services are not configured on this device.';
  @override
  Stream<AuthenticatedUser?> authStateChanges() => Stream.value(null);
  @override
  Future<UserProfile?> loadProfile(String uid) async => null;
  @override
  Future<void> markLastLogin(String uid) async {}
  @override
  Future<void> clearMustChangePassword(String uid) async =>
      throw const AuthFailure(AuthFailureCode.network, _message);
  @override
  Future<void> sendPasswordResetEmail(String email) async =>
      throw const AuthFailure(AuthFailureCode.network, _message);
  @override
  Future<AuthenticatedUser> signIn({
    required String email,
    required String password,
  }) async => throw const AuthFailure(AuthFailureCode.network, _message);
  @override
  Future<void> signOut() async {}
  @override
  Future<void> updatePassword(String newPassword) async =>
      throw const AuthFailure(AuthFailureCode.network, _message);
}

class AccessDecision {
  const AccessDecision.allowed(this.destination) : error = null;
  const AccessDecision.blocked(this.error) : destination = null;
  final AuthDestination? destination;
  final AuthFailure? error;
  bool get isAllowed => destination != null;
}

abstract final class AuthenticationPolicy {
  static AccessDecision evaluate(UserProfile profile, AppAudience audience) {
    if (!profile.active) {
      return const AccessDecision.blocked(
        AuthFailure(
          AuthFailureCode.inactiveProfile,
          'This account profile is inactive. Contact your administrator.',
        ),
      );
    }
    if (!profile.hasValidInstituteAssignment) {
      return const AccessDecision.blocked(
        AuthFailure(
          AuthFailureCode.permissionDenied,
          'This account profile is incomplete. Contact your administrator.',
        ),
      );
    }
    if (audience == AppAudience.management && profile.role == UserRole.parent) {
      return const AccessDecision.blocked(
        AuthFailure(
          AuthFailureCode.unsupportedRole,
          'This account belongs to Attendiqo Connect.',
        ),
      );
    }
    if (audience == AppAudience.connect && profile.role != UserRole.parent) {
      return const AccessDecision.blocked(
        AuthFailure(
          AuthFailureCode.unsupportedRole,
          'This account belongs to the Attendiqo management application.',
        ),
      );
    }
    if (profile.mustChangePassword) {
      return const AccessDecision.allowed(AuthDestination.changePassword);
    }
    return AccessDecision.allowed(switch (profile.role) {
      UserRole.superAdmin => AuthDestination.superAdminDashboard,
      UserRole.instituteAdmin => AuthDestination.instituteAdminDashboard,
      UserRole.teacher => AuthDestination.teacherDashboard,
      UserRole.parent => AuthDestination.parentDashboard,
    });
  }
}

class AuthenticationState {
  const AuthenticationState(
    this.status, {
    this.destination,
    this.profile,
    this.message,
  });
  const AuthenticationState.checking() : this(AuthenticationStatus.checking);
  final AuthenticationStatus status;
  final AuthDestination? destination;
  final UserProfile? profile;
  final String? message;
}

class AuthenticationController extends ChangeNotifier {
  AuthenticationController({required this.repository, required this.audience});
  final AuthenticationRepository repository;
  final AppAudience audience;
  AuthenticationState _state = const AuthenticationState.checking();
  AuthenticationState get state => _state;
  StreamSubscription<AuthenticatedUser?>? _subscription;
  int _generation = 0;

  void start() {
    _subscription ??= repository.authStateChanges().listen(
      (user) => _resolve(user),
      onError: (_) =>
          _setFailure('Unable to check your session. Please try again.'),
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    _setState(const AuthenticationState(AuthenticationStatus.authenticating));
    try {
      final user = await repository.signIn(
        email: email.trim(),
        password: password,
      );
      await _resolve(user);
    } on AuthFailure catch (failure) {
      _setFailure(failure.userMessage);
    } catch (_) {
      _setFailure('Unable to sign in. Please try again.');
    }
  }

  Future<bool> requestPasswordReset(String email) async {
    try {
      await repository.sendPasswordResetEmail(email.trim());
      return true;
    } on AuthFailure catch (failure) {
      if (failure.code == AuthFailureCode.userNotFound) return true;
      _setFailure(failure.userMessage);
      return false;
    } catch (_) {
      _setFailure('Unable to send the password-reset email. Please try again.');
      return false;
    }
  }

  Future<bool> changePassword(String newPassword) async {
    final validation = PasswordValidator.validateForCreation(newPassword);
    if (validation != null) {
      _setFailure(validation);
      return false;
    }
    final profile = _state.profile;
    if (profile == null) return false;
    _setState(
      AuthenticationState(
        AuthenticationStatus.authenticating,
        profile: profile,
      ),
    );
    try {
      await repository.updatePassword(newPassword);
      await repository.clearMustChangePassword(profile.uid);
      await _resolve(AuthenticatedUser(uid: profile.uid, email: profile.email));
      return true;
    } on AuthFailure catch (failure) {
      _setState(
        AuthenticationState(
          AuthenticationStatus.mustChangePassword,
          destination: AuthDestination.changePassword,
          profile: profile,
          message: failure.userMessage,
        ),
      );
      return false;
    } catch (_) {
      _setState(
        AuthenticationState(
          AuthenticationStatus.mustChangePassword,
          destination: AuthDestination.changePassword,
          profile: profile,
          message: 'Unable to change the password. Please try again.',
        ),
      );
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await repository.signOut();
    } finally {
      _setState(
        const AuthenticationState(
          AuthenticationStatus.signedOut,
          destination: AuthDestination.signedOut,
        ),
      );
    }
  }

  Future<void> _resolve(AuthenticatedUser? user) async {
    final generation = ++_generation;
    if (user == null) {
      _setState(
        const AuthenticationState(
          AuthenticationStatus.signedOut,
          destination: AuthDestination.signedOut,
        ),
      );
      return;
    }
    _setState(const AuthenticationState(AuthenticationStatus.checking));
    try {
      final profile = await repository.loadProfile(user.uid);
      if (generation != _generation) return;
      if (profile == null) {
        _setState(
          const AuthenticationState(
            AuthenticationStatus.blocked,
            message: 'No user profile was found. Contact your administrator.',
          ),
        );
        return;
      }
      final decision = AuthenticationPolicy.evaluate(profile, audience);
      if (!decision.isAllowed) {
        _setState(
          AuthenticationState(
            AuthenticationStatus.blocked,
            profile: profile,
            message: decision.error!.userMessage,
          ),
        );
        return;
      }
      await repository.markLastLogin(user.uid);
      final destination = decision.destination!;
      _setState(
        AuthenticationState(
          destination == AuthDestination.changePassword
              ? AuthenticationStatus.mustChangePassword
              : AuthenticationStatus.authenticated,
          destination: destination,
          profile: profile,
        ),
      );
    } on AuthFailure catch (failure) {
      if (generation == _generation) {
        _setFailure(failure.userMessage);
      }
    } catch (_) {
      if (generation == _generation) {
        _setFailure('Unable to load your account profile. Please try again.');
      }
    }
  }

  void _setFailure(String message) => _setState(
    AuthenticationState(AuthenticationStatus.failure, message: message),
  );

  void _setState(AuthenticationState value) {
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
