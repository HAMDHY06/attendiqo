import 'dart:convert';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreTeacherRepository implements TeacherRepository {
  FirestoreTeacherRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<Map<String, List<String>>> fetchAssignedClassNames({
    String? instituteId,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore.collection(
        FirestoreCollections.classes,
      );
      if (instituteId != null) {
        query = query.where('instituteId', isEqualTo: instituteId);
      }
      final snapshot = await query.get();
      final result = <String, List<String>>{};
      for (final document in snapshot.docs) {
        final name = document.data()['name'];
        final teacherIds = document.data()['teacherIds'];
        if (name is! String || teacherIds is! List) continue;
        for (final teacherUid in teacherIds.whereType<String>()) {
          result.putIfAbsent(teacherUid, () => <String>[]).add(name);
        }
      }
      for (final names in result.values) {
        names.sort();
      }
      return result;
    } on FirebaseException catch (error) {
      throw Failure(
        SafeErrorMapper.fromCode(
          error.code,
          fallback: 'Unable to load assigned classes.',
        ),
        code: error.code,
      );
    }
  }

  @override
  Future<List<UserProfile>> fetchTeachers({String? instituteId}) async {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection(FirestoreCollections.users)
          .where('role', isEqualTo: UserRole.teacher.name);
      if (instituteId != null) {
        query = query.where('instituteId', isEqualTo: instituteId);
      }
      final snapshot = await query.get();
      return snapshot.docs
          .map((document) => _profile(document.id, document.data()))
          .whereType<UserProfile>()
          .toList()
        ..sort((left, right) => left.displayName.compareTo(right.displayName));
    } on FirebaseException catch (error) {
      throw Failure(
        error.code == 'permission-denied'
            ? 'You cannot access teacher-management information.'
            : 'Unable to load teacher accounts. Check your connection.',
        code: error.code,
      );
    }
  }

  @override
  Future<void> updateTeacher(
    UserProfile teacher, {
    required UserProfile actor,
    bool verifiedSuperAdmin = false,
  }) async {
    if (!TeacherAuthorization.canManage(
      actor,
      teacher,
      verifiedSuperAdmin: verifiedSuperAdmin,
    )) {
      throw const Failure(
        'You are not allowed to update this teacher.',
        code: 'unauthorized',
      );
    }
    final teacherReference = _firestore
        .collection(FirestoreCollections.users)
        .doc(teacher.uid);
    final instituteReference = _firestore
        .collection(FirestoreCollections.institutes)
        .doc(teacher.instituteId);
    final auditReference = _firestore
        .collection(FirestoreCollections.auditLogs)
        .doc();

    await _firestore.runTransaction((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(teacherReference),
        transaction.get(instituteReference),
      ]);
      final current = snapshots[0].data();
      final institute = snapshots[1].data();
      if (current == null || current['role'] != UserRole.teacher.name) {
        throw const Failure(
          'Teacher account was not found.',
          code: 'not-found',
        );
      }
      if (institute == null ||
          institute['active'] != true ||
          institute['status'] != InstituteStatus.active.name) {
        throw const Failure(
          'Teacher management is unavailable while the institute is suspended or inactive.',
          code: 'institute-inactive',
        );
      }
      final currentEmployee = current['employeeNumber'] as String?;
      final nextEmployee = teacher.employeeNumber;
      DocumentReference<Map<String, dynamic>>? nextReservation;
      DocumentReference<Map<String, dynamic>>? oldReservation;
      if (nextEmployee != currentEmployee && nextEmployee != null) {
        nextReservation = _employeeReference(
          teacher.instituteId!,
          nextEmployee,
        );
        if ((await transaction.get(nextReservation)).exists) {
          throw const Failure(
            'That employee number is already used in this institute.',
            code: 'duplicate-employee-number',
          );
        }
      }
      if (nextEmployee != currentEmployee && currentEmployee != null) {
        oldReservation = _employeeReference(
          teacher.instituteId!,
          currentEmployee,
        );
      }

      final now = FieldValue.serverTimestamp();
      transaction.update(teacherReference, {
        'displayName': teacher.displayName.trim(),
        'phoneNumber': teacher.phoneNumber,
        'employeeNumber': nextEmployee,
        'permissions': teacher.effectiveTeacherPermissions.toMap(),
        'active': teacher.active,
        'status': teacher.effectiveTeacherStatus!.name,
        'updatedAt': now,
        'updatedBy': actor.uid,
      });
      if (nextReservation != null) {
        transaction.set(nextReservation, {
          'instituteId': teacher.instituteId,
          'employeeNumber': nextEmployee,
          'teacherUid': teacher.uid,
          'createdAt': now,
          'createdBy': actor.uid,
        });
      }
      if (oldReservation != null) transaction.delete(oldReservation);

      final action = _action(current, teacher);
      transaction.set(auditReference, {
        'auditLogId': auditReference.id,
        'actorUid': actor.uid,
        'actorRole': actor.role.name,
        'instituteId': teacher.instituteId,
        'action': action.name,
        'targetType': AuditTargetType.teacher.name,
        'targetId': teacher.uid,
        'summary': _summary(action),
        'createdAt': now,
      });
    });
  }

  @override
  Future<void> updateTeacherPermissions({
    required UserProfile actor,
    required String teacherUid,
    required String instituteId,
    required TeacherPermissions permissions,
    bool verifiedSuperAdmin = false,
  }) async {
    final teacherReference = _firestore
        .collection(FirestoreCollections.users)
        .doc(teacherUid);
    final instituteReference = _firestore
        .collection(FirestoreCollections.institutes)
        .doc(instituteId);
    final auditReference = _firestore
        .collection(FirestoreCollections.auditLogs)
        .doc();
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshots = await Future.wait([
          transaction.get(teacherReference),
          transaction.get(instituteReference),
        ]);
        final current = snapshots[0].data();
        final institute = snapshots[1].data();
        if (current == null || current['role'] != UserRole.teacher.name) {
          throw const Failure(
            'Teacher account was not found.',
            code: 'not-found',
          );
        }
        final currentProfile = _profile(teacherUid, current);
        if (currentProfile == null ||
            currentProfile.instituteId != instituteId ||
            !TeacherAuthorization.canManage(
              actor,
              currentProfile,
              verifiedSuperAdmin: verifiedSuperAdmin,
            )) {
          throw const Failure(
            'You are not allowed to update this teacher.',
            code: 'unauthorized',
          );
        }
        if (institute == null ||
            institute['active'] != true ||
            institute['status'] != InstituteStatus.active.name) {
          throw const Failure(
            'Teacher management is unavailable while the institute is suspended or inactive.',
            code: 'institute-inactive',
          );
        }
        final currentPermissions = TeacherPermissions.tryFromMap(
          current['permissions'],
        );
        if (currentPermissions == null) {
          throw const Failure(
            'Teacher permissions are invalid.',
            code: 'invalid-input',
          );
        }
        final changedKeys = currentPermissions.changedKeys(permissions).toList()
          ..sort();
        if (changedKeys.isEmpty) return;
        final now = FieldValue.serverTimestamp();
        transaction.update(teacherReference, {
          'permissions': permissions.toMap(),
          'updatedAt': now,
          'updatedBy': actor.uid,
        });
        transaction.set(auditReference, {
          'auditLogId': auditReference.id,
          'actorUid': actor.uid,
          'actorRole': actor.role.name,
          'instituteId': instituteId,
          'action': AuditAction.teacherPermissionsChanged.name,
          'targetType': AuditTargetType.teacher.name,
          'targetId': teacherUid,
          'summary': 'Teacher permissions changed: ${changedKeys.join(', ')}',
          'createdAt': now,
        });
      });
    } on Failure {
      rethrow;
    } on FirebaseException catch (error) {
      throw Failure(
        SafeErrorMapper.fromCode(
          error.code,
          fallback: 'Unable to save teacher permissions. Please try again.',
        ),
        code: error.code,
      );
    }
  }

  @override
  Future<List<AuditLogEntry>> fetchAuditLogs({String? instituteId}) async {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection(FirestoreCollections.auditLogs)
          .orderBy('createdAt', descending: true)
          .limit(100);
      if (instituteId != null) {
        query = query.where('instituteId', isEqualTo: instituteId);
      }
      final snapshot = await query.get();
      return snapshot.docs
          .map((document) => _audit(document.id, document.data()))
          .whereType<AuditLogEntry>()
          .where((entry) => entry.targetType == AuditTargetType.teacher)
          .toList();
    } on FirebaseException catch (error) {
      throw Failure(
        error.code == 'permission-denied'
            ? 'You cannot access teacher audit logs.'
            : 'Unable to load teacher audit logs.',
        code: error.code,
      );
    }
  }

  DocumentReference<Map<String, dynamic>> _employeeReference(
    String instituteId,
    String employeeNumber,
  ) => _firestore
      .collection(FirestoreCollections.teacherEmployeeNumbers)
      .doc(
        '${instituteId}_${EmployeeNumberValidator.normalize(employeeNumber)}',
      );

  AuditAction _action(Map<String, dynamic> current, UserProfile teacher) {
    if (current['active'] == true && !teacher.active) {
      return AuditAction.teacherDisabled;
    }
    if (current['active'] == false && teacher.active) {
      return AuditAction.teacherReactivated;
    }
    if (jsonEncode(current['permissions']) !=
        jsonEncode(teacher.effectiveTeacherPermissions.toMap())) {
      return AuditAction.teacherPermissionsChanged;
    }
    return AuditAction.teacherUpdated;
  }

  String _summary(AuditAction action) => switch (action) {
    AuditAction.teacherDisabled => 'Teacher account disabled',
    AuditAction.teacherReactivated => 'Teacher account reactivated',
    AuditAction.teacherPermissionsChanged => 'Teacher permissions updated',
    _ => 'Teacher profile updated',
  };

  UserProfile? _profile(String uid, Map<String, dynamic> data) =>
      UserProfile.tryFromMap(_normalize(uid, data, idField: 'uid'));

  AuditLogEntry? _audit(String id, Map<String, dynamic> data) {
    final actorRole = UserRoleSerialization.tryParse(data['actorRole']);
    final action = AuditAction.values
        .where((value) => value.name == data['action'])
        .firstOrNull;
    final targetType = AuditTargetType.values
        .where((value) => value.name == data['targetType'])
        .firstOrNull;
    final createdAt = data['createdAt'];
    if (actorRole == null ||
        action == null ||
        targetType == null ||
        createdAt is! Timestamp) {
      return null;
    }
    return AuditLogEntry(
      auditLogId: id,
      actorUid: data['actorUid']! as String,
      actorRole: actorRole,
      instituteId: data['instituteId'] as String?,
      action: action,
      targetType: targetType,
      targetId: data['targetId']! as String,
      summary: data['summary']! as String,
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
