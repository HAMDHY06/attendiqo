import 'enums.dart';
import 'models.dart';
import 'validation.dart';

class ManagedPasswordResetRequest {
  const ManagedPasswordResetRequest({
    required this.actor,
    required this.target,
  });

  final UserProfile actor;
  final UserProfile target;

  bool get isAuthorized => switch (actor.role) {
    UserRole.superAdmin =>
      target.role == UserRole.instituteAdmin || target.role == UserRole.teacher,
    UserRole.instituteAdmin =>
      target.role == UserRole.teacher &&
          actor.instituteId != null &&
          actor.instituteId == target.instituteId,
    _ => false,
  };
}

class PasswordResetResult {
  const PasswordResetResult(this.status, this.message);

  static const safeSuccess = PasswordResetResult(
    PasswordResetStatus.success,
    'If the account is eligible, password-reset instructions have been sent.',
  );

  final PasswordResetStatus status;
  final String message;
  bool get succeeded => status == PasswordResetStatus.success;
}

abstract interface class ManagedPasswordResetService {
  Future<PasswordResetResult> sendPasswordResetEmail(
    ManagedPasswordResetRequest request,
  );
}

class MockManagedPasswordResetService implements ManagedPasswordResetService {
  MockManagedPasswordResetService({this.nextStatus});

  PasswordResetStatus? nextStatus;
  final List<ManagedPasswordResetRequest> requests = [];

  @override
  Future<PasswordResetResult> sendPasswordResetEmail(
    ManagedPasswordResetRequest request,
  ) async {
    requests.add(request);
    if (!request.isAuthorized) {
      return const PasswordResetResult(
        PasswordResetStatus.unauthorized,
        'You are not allowed to request a password reset for this account.',
      );
    }
    if (FieldValidators.email(request.target.email) != null) {
      return const PasswordResetResult(
        PasswordResetStatus.invalidEmail,
        'The selected account has an invalid email address.',
      );
    }
    if (!request.target.active) {
      return const PasswordResetResult(
        PasswordResetStatus.disabledAccount,
        'This account is disabled. Enable it before requesting a password reset.',
      );
    }
    return switch (nextStatus) {
      PasswordResetStatus.networkError => const PasswordResetResult(
        PasswordResetStatus.networkError,
        'Network unavailable. Check your connection and try again.',
      ),
      PasswordResetStatus.failure => const PasswordResetResult(
        PasswordResetStatus.failure,
        'Unable to request a password-reset email. Please try again.',
      ),
      _ => PasswordResetResult.safeSuccess,
    };
  }
}

class UnavailableManagedPasswordResetService
    implements ManagedPasswordResetService {
  const UnavailableManagedPasswordResetService();

  @override
  Future<PasswordResetResult> sendPasswordResetEmail(
    ManagedPasswordResetRequest request,
  ) async => const PasswordResetResult(
    PasswordResetStatus.networkError,
    'Password recovery is unavailable on this device.',
  );
}
