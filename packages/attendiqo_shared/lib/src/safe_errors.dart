import 'models.dart';

/// Converts operational failure codes into stable, non-sensitive UI messages.
abstract final class SafeErrorMapper {
  static String fromFailure(
    Failure failure, {
    String fallback = 'Something went wrong. Please try again.',
  }) => fromCode(failure.code, fallback: fallback);

  static String fromCode(
    String? code, {
    String fallback = 'Something went wrong. Please try again.',
  }) => switch (code) {
    'permission-denied' ||
    'unauthorized' => 'You do not have permission to complete this action.',
    'unauthenticated' => 'Your session has expired. Please sign in again.',
    'unavailable' || 'network' || 'network-request-failed' =>
      'The service is unavailable. Check your connection and try again.',
    'duplicate-class-code' =>
      'That class code is already used in this institute.',
    'duplicate-email' => 'An account already uses this email address.',
    'duplicate-employee-number' =>
      'That employee number is already used in this institute.',
    'institute-inactive' || 'suspended-institute' =>
      'This action is unavailable while the institute is suspended or inactive.',
    'inactive-account' =>
      'This account is inactive. Contact your administrator.',
    'backend-unavailable' || 'backend-not-configured' =>
      'This service is not configured yet. Contact HamdhyTech support.',
    'invalid-input' => 'Please correct the highlighted information.',
    'invalid-teacher' || 'invalid-teacher-assignment' =>
      'Select an active Teacher from this institute.',
    'reason-required' => 'Enter a reason before saving this correction.',
    'class-inactive' =>
      'This class is inactive or archived and cannot be used for this action.',
    'session-exists' =>
      'An attendance session is already open for this class and date.',
    _ => fallback,
  };
}
