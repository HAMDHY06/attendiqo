import 'dart:convert';

import 'package:http/http.dart' as http;

import 'enums.dart';
import 'institute_membership.dart';

/// Safe Cloudflare Worker client. It accepts only an Auth-token callback and
/// returns no token, path, or backend diagnostic to callers.
class MembershipWorkerClient {
  MembershipWorkerClient({
    required this.tokenProvider,
    http.Client? client,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _baseUrl =
           (baseUrl ?? const String.fromEnvironment('MEMBERSHIP_WORKER_URL'))
               .replaceAll(RegExp(r'/+$'), '');

  final Future<String?> Function() tokenProvider;
  final http.Client _client;
  final String _baseUrl;

  Future<List<InstituteMembership>> loadOwnMemberships(
    String authenticatedUid,
  ) async {
    try {
      if (authenticatedUid.isEmpty || _baseUrl.isEmpty) {
        throw const MembershipWorkerFailure(
          'Membership services are unavailable.',
        );
      }
      final token = await tokenProvider();
      if (token == null || token.isEmpty) {
        throw const MembershipWorkerFailure(
          'Sign in to view institute access.',
        );
      }
      final response = await _client.post(
        Uri.parse('$_baseUrl/v1/memberships/list'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: '{}',
      );
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const MembershipWorkerFailure(
          'Your institute access could not be verified.',
        );
      }
      if (response.statusCode != 200) {
        throw const MembershipWorkerFailure(
          'Membership services are temporarily unavailable.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['memberships'] is! List) {
        throw const MembershipWorkerFailure(
          'Membership information is unavailable.',
        );
      }
      final memberships = <InstituteMembership>[];
      for (final raw in decoded['memberships'] as List) {
        if (raw is! Map<String, dynamic>) throw const FormatException();
        final instituteId = raw['instituteId'];
        final role = UserRoleSerialization.tryParse(raw['role']);
        final status = _status(raw['status']);
        if (instituteId is! String ||
            instituteId.isEmpty ||
            role == null ||
            status == null ||
            role == UserRole.superAdmin) {
          throw const FormatException();
        }
        memberships.add(
          InstituteMembership(
            uid: authenticatedUid,
            instituteId: instituteId,
            role: role,
            status: status,
            requestedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        );
      }
      return List.unmodifiable(memberships);
    } on MembershipWorkerFailure {
      rethrow;
    } on FormatException {
      throw const MembershipWorkerFailure(
        'Membership information is unavailable.',
      );
    } on http.ClientException {
      throw const MembershipWorkerFailure(
        'Membership services are temporarily unavailable.',
      );
    } catch (_) {
      throw const MembershipWorkerFailure(
        'Membership services are temporarily unavailable.',
      );
    }
  }

  Future<InstituteJoinRequest> requestMembership({
    required String joinCode,
    required UserRole requestedRole,
  }) async {
    final value = await _post('/v1/memberships/request', {
      'joinCode': joinCode.trim().toUpperCase(),
      'requestedRole': requestedRole.name,
    });
    final status = _status(value['status']);
    if (status == null) {
      throw const MembershipWorkerFailure(
        'Membership information is unavailable.',
      );
    }
    return InstituteJoinRequest(
      requestId: '',
      uid: '',
      instituteId: '',
      requestedRole: requestedRole,
      status: status,
      requestedAt: DateTime.now().toUtc(),
    );
  }

  Future<List<InstituteJoinRequest>> loadOwnRequests() =>
      _loadRequests('/v1/memberships/requests/list');

  Future<List<InstituteJoinRequest>> loadReviewableRequests() =>
      _loadRequests('/v1/memberships/reviewable');

  Future<InstituteMembershipStatus> reviewRequest({
    required String requestId,
    required bool approve,
  }) async {
    final value = await _post('/v1/memberships/review', {
      'requestId': requestId,
      'decision': approve ? 'approve' : 'reject',
    });
    final status = _status(value['status']);
    if (status == null) {
      throw const MembershipWorkerFailure(
        'Membership information is unavailable.',
      );
    }
    return status;
  }

  Future<InstituteMembershipStatus> revokeMembership(
    String membershipId,
  ) async {
    final value = await _post('/v1/memberships/revoke', {
      'membershipId': membershipId,
    });
    final status = _status(value['status']);
    if (status == null) {
      throw const MembershipWorkerFailure(
        'Membership information is unavailable.',
      );
    }
    return status;
  }

  Future<List<InstituteJoinRequest>> _loadRequests(String path) async {
    final value = await _post(path, const {});
    final raw = value['requests'];
    if (raw is! List) {
      throw const MembershipWorkerFailure(
        'Membership information is unavailable.',
      );
    }
    try {
      return List.unmodifiable(
        raw.map((item) {
          if (item is! Map<String, dynamic>) throw const FormatException();
          final role = UserRoleSerialization.tryParse(item['requestedRole']);
          final status = _status(item['status']);
          if (item['requestId'] is! String ||
              item['instituteId'] is! String ||
              role == null ||
              status == null) {
            throw const FormatException();
          }
          return InstituteJoinRequest(
            requestId: item['requestId'] as String,
            uid: '',
            instituteId: item['instituteId'] as String,
            requestedRole: role,
            status: status,
            requestedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          );
        }),
      );
    } on FormatException {
      throw const MembershipWorkerFailure(
        'Membership information is unavailable.',
      );
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      if (_baseUrl.isEmpty) {
        throw const MembershipWorkerFailure(
          'Membership services are unavailable.',
        );
      }
      final token = await tokenProvider();
      if (token == null || token.isEmpty) {
        throw const MembershipWorkerFailure(
          'Sign in to view institute access.',
        );
      }
      final response = await _client.post(
        Uri.parse('$_baseUrl$path'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const MembershipWorkerFailure(
          'Your institute access could not be verified.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const MembershipWorkerFailure(
          'Membership services are temporarily unavailable.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return decoded;
    } on MembershipWorkerFailure {
      rethrow;
    } on FormatException {
      throw const MembershipWorkerFailure(
        'Membership information is unavailable.',
      );
    } on http.ClientException {
      throw const MembershipWorkerFailure(
        'Membership services are temporarily unavailable.',
      );
    } catch (_) {
      throw const MembershipWorkerFailure(
        'Membership services are temporarily unavailable.',
      );
    }
  }

  InstituteMembershipStatus? _status(Object? value) {
    if (value is! String) return null;
    for (final status in InstituteMembershipStatus.values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

class MembershipWorkerFailure implements Exception {
  const MembershipWorkerFailure(this.message);
  final String message;
}
