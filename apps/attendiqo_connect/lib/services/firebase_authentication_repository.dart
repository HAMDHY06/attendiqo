import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseAuthenticationRepository implements AuthenticationRepository {
  FirebaseAuthenticationRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Stream<AuthenticatedUser?> authStateChanges() => _auth.authStateChanges().map(
    (user) => user == null
        ? null
        : AuthenticatedUser(uid: user.uid, email: user.email ?? ''),
  );

  @override
  Future<AuthenticatedUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthFailure(
          AuthFailureCode.unknown,
          'Unable to sign in. Please try again.',
        );
      }
      return AuthenticatedUser(uid: user.uid, email: user.email ?? email);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthFailure(error);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthFailure(error, reset: true);
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure(
        AuthFailureCode.invalidCredentials,
        'Please sign in again.',
      );
    }
    try {
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthFailure(error);
    }
  }

  @override
  Future<UserProfile?> loadProfile(String uid) async {
    try {
      final snapshot = await _firestore
          .collection(FirestoreCollections.users)
          .doc(uid)
          .get();
      final data = snapshot.data();
      if (data == null) return null;
      final normalized = <String, Object?>{};
      for (final entry in data.entries) {
        normalized[entry.key] = entry.value is Timestamp
            ? (entry.value as Timestamp).toDate()
            : entry.value;
      }
      normalized['uid'] = uid;
      return UserProfile.tryFromMap(normalized);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const AuthFailure(
          AuthFailureCode.permissionDenied,
          'Your profile cannot be accessed. Contact your administrator.',
        );
      }
      throw const AuthFailure(
        AuthFailureCode.network,
        'Unable to load your profile. Check your connection and try again.',
      );
    }
  }

  @override
  Future<void> markLastLogin(String uid) => _updateProfile(uid, {
    'lastLoginAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, 'Your session could not be verified. Contact your administrator.');

  @override
  Future<void> clearMustChangePassword(String uid) => _updateProfile(
    uid,
    {'mustChangePassword': false, 'updatedAt': FieldValue.serverTimestamp()},
    'Your password changed, but your profile could not be updated. Contact your administrator.',
  );

  Future<void> _updateProfile(
    String uid,
    Map<String, Object?> values,
    String deniedMessage,
  ) async {
    try {
      await _firestore
          .collection(FirestoreCollections.users)
          .doc(uid)
          .update(values);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw AuthFailure(AuthFailureCode.permissionDenied, deniedMessage);
      }
      throw const AuthFailure(
        AuthFailureCode.network,
        'Unable to synchronize your profile. Check your connection and try again.',
      );
    }
  }

  AuthFailure _mapAuthFailure(
    FirebaseAuthException error, {
    bool reset = false,
  }) => switch (error.code) {
    'invalid-email' => const AuthFailure(
      AuthFailureCode.invalidEmail,
      'Enter a valid email address.',
    ),
    'invalid-credential' || 'wrong-password' => const AuthFailure(
      AuthFailureCode.invalidCredentials,
      'The email or password is incorrect.',
    ),
    'user-not-found' => const AuthFailure(
      AuthFailureCode.userNotFound,
      'No account was found for this email.',
    ),
    'user-disabled' => const AuthFailure(
      AuthFailureCode.userDisabled,
      'This account has been disabled. Contact your institute.',
    ),
    'too-many-requests' => const AuthFailure(
      AuthFailureCode.tooManyRequests,
      'Too many attempts. Wait a while and try again.',
    ),
    'network-request-failed' => const AuthFailure(
      AuthFailureCode.network,
      'Network unavailable. Check your connection and try again.',
    ),
    'requires-recent-login' => const AuthFailure(
      AuthFailureCode.requiresRecentLogin,
      'For security, sign out and sign in again before changing your password.',
    ),
    _ when reset => const AuthFailure(
      AuthFailureCode.resetFailed,
      'Unable to send the password-reset email. Please try again.',
    ),
    _ => const AuthFailure(
      AuthFailureCode.unknown,
      'Unable to complete authentication. Please try again.',
    ),
  };
}
