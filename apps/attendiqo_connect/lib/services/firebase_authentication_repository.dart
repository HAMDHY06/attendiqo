import 'dart:convert';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

abstract interface class ParentAccountWorkflowRepository {
  Future<void> registerParent({
    required String displayName,
    required String mobileNumber,
    required String email,
    required String password,
  });

  Future<void> linkStudent(String studentNumber);
}

class FirebaseAuthenticationRepository
    implements
        AuthenticationRepository,
        ActiveMembershipRepository,
        MembershipWorkflowRepository,
        ParentAccountWorkflowRepository {
  FirebaseAuthenticationRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    http.Client? client,
    String? workerEndpoint,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _client = client ?? http.Client(),
       _workerEndpoint =
           (workerEndpoint ?? AttendiqoServiceEndpoints.workerBaseUrl)
               .replaceAll(RegExp(r'/+$'), '');
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final http.Client _client;
  final String _workerEndpoint;

  MembershipWorkerClient get _membershipWorker => MembershipWorkerClient(
    tokenProvider: () async => _auth.currentUser == null
        ? null
        : await _auth.currentUser!.getIdToken(true),
    baseUrl: const String.fromEnvironment(
      'MEMBERSHIP_WORKER_URL',
      defaultValue: AttendiqoServiceEndpoints.workerBaseUrl,
    ),
  );

  @override
  Future<List<InstituteMembership>> loadOwnMemberships(
    String authenticatedUid,
  ) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != authenticatedUid) {
      throw const AuthFailure(
        AuthFailureCode.invalidCredentials,
        'Please sign in again to view institute access.',
      );
    }
    try {
      return await _membershipWorker.loadOwnMemberships(authenticatedUid);
    } on MembershipWorkerFailure catch (error) {
      throw AuthFailure(AuthFailureCode.network, error.message);
    }
  }

  @override
  Future<InstituteJoinRequest> requestMembership({
    required String joinCode,
    required UserRole requestedRole,
  }) => _membershipWorker.requestMembership(
    joinCode: joinCode,
    requestedRole: requestedRole,
  );
  @override
  Future<List<InstituteJoinRequest>> loadOwnRequests() =>
      _membershipWorker.loadOwnRequests();
  @override
  Future<List<InstituteJoinRequest>> loadReviewableRequests() =>
      _membershipWorker.loadReviewableRequests();
  @override
  Future<InstituteMembershipStatus> reviewRequest({
    required String requestId,
    required bool approve,
  }) => _membershipWorker.reviewRequest(requestId: requestId, approve: approve);
  @override
  Future<InstituteMembershipStatus> revokeMembership(String membershipId) =>
      _membershipWorker.revokeMembership(membershipId);

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
  Future<void> registerParent({
    required String displayName,
    required String mobileNumber,
    required String email,
    required String password,
  }) async {
    User? createdUser;
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      createdUser = credential.user;
      if (createdUser == null) {
        throw const AuthFailure(
          AuthFailureCode.unknown,
          'Unable to create the parent account. Please try again.',
        );
      }
      await _postWorker('/v1/parents/bootstrap', {
        'displayName': displayName.trim(),
        'mobileNumber': MobileNumberValidator.normalize(mobileNumber),
      });
      await _auth.signOut();
    } on FirebaseAuthException catch (error) {
      throw _mapAuthFailure(error);
    } on AuthFailure {
      if (createdUser != null) {
        await createdUser.delete().catchError((_) {});
        await _auth.signOut().catchError((_) {});
      }
      rethrow;
    }
  }

  @override
  Future<void> linkStudent(String studentNumber) async {
    await _postWorker('/v1/parents/link', {
      'studentNumber': studentNumber.trim().toUpperCase(),
    });
  }

  Future<Map<String, dynamic>> _postWorker(
    String path,
    Map<String, Object?> payload,
  ) async {
    final token = await _auth.currentUser?.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw const AuthFailure(
        AuthFailureCode.invalidCredentials,
        'Please sign in again.',
      );
    }
    try {
      final response = await _client.post(
        Uri.parse('$_workerEndpoint$path'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }
      throw AuthFailure(
        response.statusCode == 401
            ? AuthFailureCode.invalidCredentials
            : response.statusCode == 403
            ? AuthFailureCode.permissionDenied
            : AuthFailureCode.unknown,
        decoded['message'] is String
            ? decoded['message'] as String
            : 'Unable to complete the request. Please try again.',
      );
    } on AuthFailure {
      rethrow;
    } on FormatException {
      throw const AuthFailure(
        AuthFailureCode.network,
        'The secure account service returned an invalid response.',
      );
    } on http.ClientException {
      throw const AuthFailure(
        AuthFailureCode.network,
        'Unable to reach the secure account service. Check your connection.',
      );
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
    'email-already-in-use' => const AuthFailure(
      AuthFailureCode.invalidEmail,
      'An account already uses this email address.',
    ),
    'weak-password' => const AuthFailure(
      AuthFailureCode.invalidCredentials,
      'Use a stronger password.',
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
