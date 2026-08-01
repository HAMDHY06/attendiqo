import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseManagedPasswordResetService
    implements ManagedPasswordResetService {
  FirebaseManagedPasswordResetService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Future<PasswordResetResult> sendPasswordResetEmail(
    ManagedPasswordResetRequest request,
  ) async {
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

    try {
      final auditReference = _firestore
          .collection(FirestoreCollections.auditLogs)
          .doc();
      await auditReference.set({
        'auditLogId': auditReference.id,
        'actorUid': request.actor.uid,
        'actorRole': request.actor.role.name,
        'instituteId': request.target.instituteId,
        'action': request.target.role == UserRole.teacher
            ? AuditAction.teacherPasswordResetRequested.name
            : AuditAction.passwordResetRequested.name,
        'targetType': request.target.role == UserRole.teacher
            ? AuditTargetType.teacher.name
            : AuditTargetType.user.name,
        'targetId': request.target.uid,
        'summary': 'Password reset email requested for authorized account',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _auth.sendPasswordResetEmail(email: request.target.email.trim());
      return PasswordResetResult.safeSuccess;
    } on FirebaseAuthException catch (error) {
      return switch (error.code) {
        'user-not-found' => PasswordResetResult.safeSuccess,
        'invalid-email' => const PasswordResetResult(
          PasswordResetStatus.invalidEmail,
          'The selected account has an invalid email address.',
        ),
        'user-disabled' => const PasswordResetResult(
          PasswordResetStatus.disabledAccount,
          'This account is disabled. Enable it before requesting a password reset.',
        ),
        'network-request-failed' => const PasswordResetResult(
          PasswordResetStatus.networkError,
          'Network unavailable. Check your connection and try again.',
        ),
        _ => const PasswordResetResult(
          PasswordResetStatus.failure,
          'Unable to request a password-reset email. Please try again.',
        ),
      };
    } on FirebaseException catch (error) {
      return PasswordResetResult(
        error.code == 'permission-denied'
            ? PasswordResetStatus.unauthorized
            : PasswordResetStatus.networkError,
        error.code == 'permission-denied'
            ? 'You are not allowed to request a password reset for this account.'
            : 'Network unavailable. Check your connection and try again.',
      );
    } catch (_) {
      return const PasswordResetResult(
        PasswordResetStatus.failure,
        'Unable to request a password-reset email. Please try again.',
      );
    }
  }
}
