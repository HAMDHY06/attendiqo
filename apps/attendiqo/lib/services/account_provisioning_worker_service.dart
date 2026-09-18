import 'dart:convert';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AccountProvisioningWorkerService
    implements TeacherProvisioningService, InstituteAdminProvisioningService {
  AccountProvisioningWorkerService({
    FirebaseAuth? auth,
    http.Client? client,
    String? endpoint,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client(),
       _endpoint = (endpoint ?? AttendiqoServiceEndpoints.workerBaseUrl)
           .replaceAll(RegExp(r'/+$'), '');

  final FirebaseAuth _auth;
  final http.Client _client;
  final String _endpoint;

  @override
  Future<TeacherCreationResult> createTeacher(
    TeacherCreationRequest request,
  ) async {
    final value = await _post('/v1/accounts/teachers/create', {
      'instituteId': request.instituteId,
      'email': request.normalizedEmail,
      'displayName': request.displayName.trim(),
      'phoneNumber': request.phoneNumber,
      'employeeNumber': request.normalizedEmployeeNumber,
      'permissions': request.permissions.toMap(),
    });
    final createdAt = DateTime.tryParse(value['createdAt'] as String? ?? '');
    final uid = value['uid'];
    final temporaryPassword = value['temporaryPassword'];
    if (uid is! String ||
        temporaryPassword is! String ||
        createdAt == null) {
      throw const Failure(
        'The account service returned an invalid response.',
        code: 'backend-invalid-response',
      );
    }
    return TeacherCreationResult(
      profile: UserProfile.newTeacher(
        uid: uid,
        email: request.normalizedEmail,
        displayName: request.displayName,
        instituteId: request.instituteId,
        createdBy: request.actor.uid,
        now: createdAt,
        phoneNumber: request.phoneNumber,
        employeeNumber: request.normalizedEmployeeNumber,
        permissions: request.permissions,
      ),
      oneTimeTemporaryPassword: temporaryPassword,
    );
  }

  @override
  Future<InstituteAdminCreationResult> createInstituteAdmin(
    InstituteAdminCreationRequest request,
  ) async {
    final value = await _post('/v1/accounts/institute-admins/create', {
      'instituteId': request.instituteId,
      'email': request.email.trim().toLowerCase(),
      'displayName': request.displayName.trim(),
    });
    final uid = value['uid'];
    final temporaryPassword = value['temporaryPassword'];
    final createdAt = DateTime.tryParse(value['createdAt'] as String? ?? '');
    if (uid is! String ||
        temporaryPassword is! String ||
        createdAt == null) {
      throw const Failure(
        'The account service returned an invalid response.',
        code: 'backend-invalid-response',
      );
    }
    return InstituteAdminCreationResult(
      profile: UserProfile(
        uid: uid,
        email: request.email.trim().toLowerCase(),
        displayName: request.displayName.trim(),
        role: UserRole.instituteAdmin,
        instituteId: request.instituteId,
        active: true,
        mustChangePassword: true,
        createdAt: createdAt,
        createdBy: request.actorUid,
        updatedAt: createdAt,
      ),
      oneTimeTemporaryPassword: temporaryPassword,
    );
  }

  @override
  Future<void> disableInstituteAdmin({
    required String uid,
    required String instituteId,
    required String actorUid,
  }) async {
    await _post('/v1/accounts/institute-admins/disable', {
      'uid': uid,
      'instituteId': instituteId,
    });
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> payload,
  ) async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken(true);
    if (user == null || token == null || token.isEmpty) {
      throw const Failure(
        'Sign in again to use the secure account service.',
        code: 'unauthenticated',
      );
    }
    try {
      final response = await _client.post(
        Uri.parse('$_endpoint$path'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const Failure(
          'The secure account service is temporarily unavailable.',
          code: 'backend-unavailable',
        );
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }
      throw Failure(
        decoded['message'] is String
            ? decoded['message'] as String
            : 'The secure account service is temporarily unavailable.',
        code: decoded['error'] is String
            ? (decoded['error'] as String).replaceAll('_', '-')
            : 'backend-unavailable',
      );
    } on Failure {
      rethrow;
    } on FormatException {
      throw const Failure(
        'The secure account service returned an invalid response.',
        code: 'backend-invalid-response',
      );
    } on http.ClientException {
      throw const Failure(
        'The secure account service is temporarily unavailable.',
        code: 'network-error',
      );
    }
  }
}
