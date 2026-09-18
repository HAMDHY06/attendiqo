import 'dart:convert';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class FirestoreInstituteRepository implements InstituteRepository {
  FirestoreInstituteRepository({FirebaseFirestore? firestore, FirebaseAuth? auth, http.Client? client})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance,
      _client = client ?? http.Client();
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final http.Client _client;

  @override
  Future<List<Institute>> fetchInstitutes() async {
    final result = await _db
        .collection(FirestoreCollections.institutes)
        .orderBy('name')
        .get();
    return result.docs
        .map((doc) => _instituteFrom(doc.id, doc.data()))
        .whereType<Institute>()
        .toList();
  }

  @override
  Future<Institute?> fetchInstituteById(String instituteId) async {
    final result = await _db
        .collection(FirestoreCollections.institutes)
        .doc(instituteId)
        .get();
    if (!result.exists) return null;
    return _instituteFrom(result.id, result.data() ?? const {});
  }

  @override
  Future<Institute> createInstitute(Institute institute) async {
    return _saveThroughWorker('/v1/institutes/create', institute);
  }

  @override
  Future<void> updateInstitute(Institute institute) async {
    await _saveThroughWorker('/v1/institutes/update', institute);
  }

  Future<Institute> _saveThroughWorker(String path, Institute value) async {
    final token = await _auth.currentUser?.getIdToken(true);
    if (token == null || token.isEmpty) throw const Failure('Sign in again to continue.', code: 'unauthenticated');
    final payload = {
      'instituteId': value.instituteId, 'instituteCode': value.instituteCode,
      'name': value.name, 'address': value.address, 'contactNumber': value.contactNumber,
      'email': value.email, 'status': value.status.name,
      'pushNotificationsEnabled': value.pushNotificationsEnabled, 'smsEnabled': value.smsEnabled,
      'smsMonthlyLimit': value.smsMonthlyLimit, 'allowPaidExtraSms': value.allowPaidExtraSms,
    };
    try {
      final response = await _client.post(Uri.parse('${AttendiqoServiceEndpoints.workerBaseUrl}$path'), headers: {'authorization': 'Bearer $token', 'content-type': 'application/json'}, body: jsonEncode(payload));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const Failure('The institute service returned an invalid response.', code: 'backend-unavailable');
      if (response.statusCode < 200 || response.statusCode >= 300) throw Failure(decoded['message'] as String? ?? 'Unable to save the institute.', code: (decoded['error'] as String? ?? 'backend-unavailable').replaceAll('_', '-'));
      final raw = decoded['institute'];
      if (raw is! Map<String, dynamic>) throw const Failure('The institute service returned an invalid response.', code: 'backend-unavailable');
      final normalized = <String, Object?>{};
      for (final entry in raw.entries) {
        normalized[entry.key] = (entry.key.endsWith('At') && entry.value is String) ? DateTime.tryParse(entry.value as String) : entry.value;
      }
      return Institute.tryFromMap(normalized) ?? value;
    } on Failure { rethrow; } catch (_) { throw const Failure('The institute service is temporarily unavailable.', code: 'backend-unavailable'); }
  }

  @override
  Future<List<UserProfile>> fetchInstituteAdmins(String instituteId) async {
    final result = await _db
        .collection(FirestoreCollections.users)
        .where('instituteId', isEqualTo: instituteId)
        .where('role', isEqualTo: UserRole.instituteAdmin.name)
        .get();
    return result.docs
        .map((doc) => _profileFrom(doc.id, doc.data()))
        .whereType<UserProfile>()
        .toList();
  }

  @override
  Future<List<AuditLogEntry>> fetchAuditLogs({String? instituteId}) async {
    Query<Map<String, dynamic>> query = _db
        .collection(FirestoreCollections.auditLogs)
        .orderBy('createdAt', descending: true)
        .limit(100);
    if (instituteId != null) {
      query = query.where('instituteId', isEqualTo: instituteId);
    }
    final result = await query.get();
    return result.docs
        .map((doc) => _auditFrom(doc.id, doc.data()))
        .whereType<AuditLogEntry>()
        .toList();
  }

  Institute? _instituteFrom(String id, Map<String, dynamic> raw) =>
      Institute.tryFromMap(_normalize(id, raw, idField: 'instituteId'));
  UserProfile? _profileFrom(String id, Map<String, dynamic> raw) =>
      UserProfile.tryFromMap(_normalize(id, raw, idField: 'uid'));
  AuditLogEntry? _auditFrom(String id, Map<String, dynamic> raw) {
    final actorRole = UserRoleSerialization.tryParse(raw['actorRole']);
    final action = AuditAction.values
        .where((value) => value.name == raw['action'])
        .firstOrNull;
    final targetType = AuditTargetType.values
        .where((value) => value.name == raw['targetType'])
        .firstOrNull;
    final createdAt = raw['createdAt'];
    if (actorRole == null ||
        action == null ||
        targetType == null ||
        createdAt is! Timestamp) {
      return null;
    }
    return AuditLogEntry(
      auditLogId: id,
      actorUid: raw['actorUid'] as String,
      actorRole: actorRole,
      instituteId: raw['instituteId'] as String?,
      action: action,
      targetType: targetType,
      targetId: raw['targetId'] as String,
      summary: raw['summary'] as String,
      createdAt: createdAt.toDate(),
    );
  }

  Map<String, Object?> _normalize(
    String id,
    Map<String, dynamic> raw, {
    required String idField,
  }) {
    final result = <String, Object?>{idField: id};
    for (final entry in raw.entries) {
      result[entry.key] = entry.value is Timestamp
          ? (entry.value as Timestamp).toDate()
          : entry.value;
    }
    return result;
  }
}
