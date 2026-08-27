import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreInstituteRepository implements InstituteRepository {
  FirestoreInstituteRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Map<String, Object?> _instituteData(
    Institute value, {
    required Object timestamp,
  }) => {
    'instituteId': value.instituteId,
    'instituteCode': value.instituteCode,
    'name': value.name,
    'address': value.address,
    'contactNumber': value.contactNumber,
    'email': value.email,
    'active': value.active,
    'status': value.status.name,
    'pushNotificationsEnabled': value.pushNotificationsEnabled,
    'smsEnabled': value.smsEnabled,
    'smsMonthlyLimit': value.smsMonthlyLimit,
    'allowPaidExtraSms': value.allowPaidExtraSms,
    'smsUsedThisMonth': value.smsUsedThisMonth,
    'createdAt': timestamp,
    'createdBy': value.createdBy,
    'updatedAt': timestamp,
    'updatedBy': value.updatedBy,
  };

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
    final instituteRef = _db
        .collection(FirestoreCollections.institutes)
        .doc(institute.instituteId);
    final codeRef = _db
        .collection(FirestoreCollections.instituteCodes)
        .doc(institute.instituteCode);
    final auditRef = _db.collection(FirestoreCollections.auditLogs).doc();
    await _db.runTransaction((transaction) async {
      if ((await transaction.get(codeRef)).exists) {
        throw const Failure(
          'Institute code already exists',
          code: 'duplicate-code',
        );
      }
      transaction.set(codeRef, {
        'instituteId': institute.instituteId,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': institute.createdBy,
      });
      transaction.set(
        instituteRef,
        _instituteData(institute, timestamp: FieldValue.serverTimestamp()),
      );
      transaction.set(
        auditRef,
        _auditData(
          auditRef.id,
          institute.createdBy,
          institute.instituteId,
          AuditAction.instituteCreated,
          AuditTargetType.institute,
          institute.instituteId,
          'Institute ${institute.instituteCode} created',
        ),
      );
    });
    return institute;
  }

  @override
  Future<void> updateInstitute(Institute institute) async {
    final ref = _db
        .collection(FirestoreCollections.institutes)
        .doc(institute.instituteId);
    final auditRef = _db.collection(FirestoreCollections.auditLogs).doc();
    await _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final data = current.data();
      if (data == null) {
        throw const Failure('Institute was not found', code: 'not-found');
      }
      if (data['instituteCode'] != institute.instituteCode) {
        throw const Failure(
          'Institute code cannot be changed',
          code: 'immutable-code',
        );
      }
      final previousStatus = data['status'];
      final previousSms = data['smsEnabled'];
      final previousPush = data['pushNotificationsEnabled'];
      final update =
          _instituteData(institute, timestamp: FieldValue.serverTimestamp())
            ..['createdAt'] = data['createdAt']
            ..['createdBy'] = data['createdBy']
            ..['smsUsedThisMonth'] = data['smsUsedThisMonth'];
      transaction.update(ref, update);
      final action = previousStatus != institute.status.name
          ? (institute.status == InstituteStatus.active
                ? AuditAction.instituteActivated
                : AuditAction.instituteSuspended)
          : previousSms != institute.smsEnabled
          ? AuditAction.smsSettingChanged
          : previousPush != institute.pushNotificationsEnabled
          ? AuditAction.pushSettingChanged
          : AuditAction.instituteUpdated;
      transaction.set(
        auditRef,
        _auditData(
          auditRef.id,
          institute.updatedBy,
          institute.instituteId,
          action,
          AuditTargetType.institute,
          institute.instituteId,
          '${action.name}: ${institute.instituteCode}',
        ),
      );
    });
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

  Map<String, Object?> _auditData(
    String auditLogId,
    String actorUid,
    String? instituteId,
    AuditAction action,
    AuditTargetType targetType,
    String targetId,
    String summary,
  ) => {
    'auditLogId': auditLogId,
    'actorUid': actorUid,
    'actorRole': UserRole.superAdmin.name,
    'instituteId': instituteId,
    'action': action.name,
    'targetType': targetType.name,
    'targetId': targetId,
    'summary': summary,
    'createdAt': FieldValue.serverTimestamp(),
  };

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
