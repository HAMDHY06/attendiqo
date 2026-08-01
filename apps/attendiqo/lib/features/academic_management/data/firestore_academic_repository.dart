import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreAcademicRepository implements AcademicRepository {
  FirestoreAcademicRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  @override
  Future<List<UserProfile>> fetchTeachersForAcademic(UserProfile actor) async {
    // A teacher may read only their own profile. Fetching it directly refreshes
    // permission changes without attempting a forbidden institute-wide query.
    if (actor.role == UserRole.teacher) {
      final snapshot = await _firestore
          .collection(FirestoreCollections.users)
          .doc(actor.uid)
          .get();
      final data = snapshot.data();
      final refreshed = data == null
          ? null
          : UserProfile.tryFromMap(_normalize(snapshot.id, data, 'uid'));
      return refreshed == null ? [actor] : [refreshed];
    }
    Query<Map<String, dynamic>> query = _firestore
        .collection(FirestoreCollections.users)
        .where('role', isEqualTo: UserRole.teacher.name);
    if (actor.role != UserRole.superAdmin) {
      query = query.where('instituteId', isEqualTo: actor.instituteId);
    }
    final snapshot = await query.get();
    return snapshot.docs
        .map(
          (doc) =>
              UserProfile.tryFromMap(_normalize(doc.id, doc.data(), 'uid')),
        )
        .whereType<UserProfile>()
        .where((value) => value.active)
        .toList();
  }

  @override
  Future<List<AcademicClass>> fetchClasses(UserProfile actor) async {
    Query<Map<String, dynamic>> query = _firestore.collection(
      FirestoreCollections.classes,
    );
    if (actor.role == UserRole.instituteAdmin) {
      query = query.where('instituteId', isEqualTo: actor.instituteId);
    } else if (actor.role == UserRole.teacher) {
      query = query.where('teacherIds', arrayContains: actor.uid);
    }
    final snapshot = await query.get();
    return snapshot.docs
        .map(
          (doc) => AcademicClass.tryFromMap(
            _normalize(doc.id, doc.data(), 'classId'),
          ),
        )
        .whereType<AcademicClass>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<AcademicClass> createClass(
    AcademicClass value,
    UserProfile actor,
  ) async {
    final validation = value.validate();
    if (validation != null) throw Failure(validation, code: 'invalid-input');
    if (!AcademicAuthorization.canCreateClass(actor, value.instituteId)) {
      throw const Failure(
        'Class creation is not permitted for this account.',
        code: 'permission-denied',
      );
    }
    if (actor.role == UserRole.teacher &&
        (value.teacherIds.length != 1 ||
            value.teacherIds.single != actor.uid ||
            value.primaryTeacherId != actor.uid ||
            value.createdBy != actor.uid)) {
      throw const Failure(
        'A Teacher-created class must assign only the creating Teacher.',
        code: 'invalid-teacher-assignment',
      );
    }
    final classReference = _firestore
        .collection(FirestoreCollections.classes)
        .doc(value.classId);
    final codeReference = _firestore
        .collection(FirestoreCollections.classCodes)
        .doc('${value.instituteId}_${value.classCode}');
    final auditReference = _firestore
        .collection(FirestoreCollections.auditLogs)
        .doc();
    try {
      await _firestore.runTransaction((transaction) async {
        final existingCode = await transaction.get(codeReference);
        if (existingCode.exists) {
          throw const Failure(
            'Class code already exists.',
            code: 'duplicate-class-code',
          );
        }
        for (final teacherId in value.teacherIds) {
          final teacher = await transaction.get(
            _firestore.collection(FirestoreCollections.users).doc(teacherId),
          );
          if (teacher.data()?['role'] != UserRole.teacher.name ||
              teacher.data()?['instituteId'] != value.instituteId ||
              teacher.data()?['active'] != true) {
            throw const Failure(
              'Every teacher must be active and belong to this institute.',
              code: 'invalid-teacher',
            );
          }
        }
        transaction.set(classReference, _serverMap(value.toMap()));
        transaction.set(codeReference, {
          'instituteId': value.instituteId,
          'classCode': value.classCode,
          'classId': value.classId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': actor.uid,
        });
        transaction.set(
          auditReference,
          _audit(
            auditReference.id,
            actor,
            value.instituteId,
            AuditAction.classCreated,
            AuditTargetType.academicClass,
            value.classId,
            'Class created',
          ),
        );
      });
    } on Failure {
      rethrow;
    } on FirebaseException catch (error) {
      throw Failure(
        SafeErrorMapper.fromCode(
          error.code,
          fallback: 'The class could not be created. Please try again.',
        ),
        code: error.code,
      );
    }
    return value;
  }

  @override
  Future<void> updateClass(AcademicClass value, UserProfile actor) async {
    final reference = _firestore
        .collection(FirestoreCollections.classes)
        .doc(value.classId);
    final auditReference = _firestore
        .collection(FirestoreCollections.auditLogs)
        .doc();
    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(reference);
      if (!current.exists) {
        throw const Failure('Class was not found.', code: 'not-found');
      }
      final currentClass = AcademicClass.tryFromMap(
        _normalize(value.classId, current.data()!, 'classId'),
      );
      if (currentClass == null ||
          !AcademicAuthorization.canEditClass(actor, currentClass)) {
        throw const Failure(
          'You may edit only an assigned, non-archived class.',
          code: 'permission-denied',
        );
      }
      if (actor.role == UserRole.teacher &&
          (value.teacherIds.length != currentClass.teacherIds.length ||
              !value.teacherIds.every(currentClass.teacherIds.contains) ||
              value.primaryTeacherId != currentClass.primaryTeacherId ||
              value.status != currentClass.status ||
              value.active != currentClass.active)) {
        throw const Failure(
          'Teacher assignments and class status require Institute Admin access.',
          code: 'permission-denied',
        );
      }
      if (current.data()?['instituteId'] != value.instituteId ||
          current.data()?['classCode'] != value.classCode) {
        throw const Failure(
          'Institute and class code cannot be changed here.',
          code: 'immutable-field',
        );
      }
      for (final teacherId in value.teacherIds) {
        final teacher = await transaction.get(
          _firestore.collection(FirestoreCollections.users).doc(teacherId),
        );
        if (teacher.data()?['role'] != UserRole.teacher.name ||
            teacher.data()?['instituteId'] != value.instituteId ||
            teacher.data()?['active'] != true) {
          throw const Failure(
            'Every teacher must be active and belong to this institute.',
            code: 'invalid-teacher',
          );
        }
      }
      transaction.update(
        reference,
        _serverMap(value.toMap())
          ..remove('classId')
          ..remove('instituteId')
          ..remove('classCode')
          ..remove('createdAt')
          ..remove('createdBy'),
      );
      final oldStatus = current.data()?['status'];
      final action = value.status == AcademicClassStatus.archived
          ? AuditAction.classArchived
          : oldStatus != AcademicClassStatus.active.name &&
                value.status == AcademicClassStatus.active
          ? AuditAction.classActivated
          : oldStatus == AcademicClassStatus.active.name &&
                value.status == AcademicClassStatus.inactive
          ? AuditAction.classDeactivated
          : AuditAction.classUpdated;
      transaction.set(
        auditReference,
        _audit(
          auditReference.id,
          actor,
          value.instituteId,
          action,
          AuditTargetType.academicClass,
          value.classId,
          'Class administration updated',
        ),
      );
    });
  }

  @override
  Future<List<ClassScheduleChange>> fetchScheduleChanges(
    UserProfile actor, {
    String? classId,
  }) async {
    if (actor.role == UserRole.teacher && classId == null) return const [];
    Query<Map<String, dynamic>> query = _firestore.collection(
      FirestoreCollections.classScheduleChanges,
    );
    if (classId != null) query = query.where('classId', isEqualTo: classId);
    if (actor.role != UserRole.superAdmin) {
      query = query.where('instituteId', isEqualTo: actor.instituteId);
    }
    final snapshot = await query.get();
    return snapshot.docs
        .map(
          (doc) => ClassScheduleChange.tryFromMap(
            _normalize(doc.id, doc.data(), 'scheduleChangeId'),
          ),
        )
        .whereType<ClassScheduleChange>()
        .toList()
      ..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
  }

  @override
  Future<void> saveScheduleChange(
    ClassScheduleChange value,
    UserProfile actor,
  ) async {
    final reference = _firestore
        .collection(FirestoreCollections.classScheduleChanges)
        .doc(value.scheduleChangeId);
    final auditReference = _firestore
        .collection(FirestoreCollections.auditLogs)
        .doc();
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      if (existing.exists &&
          existing.data()?['status'] != ScheduleChangeStatus.scheduled.name) {
        throw const Failure(
          'Completed schedule history cannot be changed.',
          code: 'history-immutable',
        );
      }
      if (existing.exists) {
        transaction.update(reference, {
          'status': value.status.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.set(reference, _serverMap(value.toMap()));
      }
      transaction.set(
        auditReference,
        _audit(
          auditReference.id,
          actor,
          value.instituteId,
          value.status == ScheduleChangeStatus.cancelled
              ? AuditAction.classScheduleChangeCancelled
              : AuditAction.classScheduleChanged,
          AuditTargetType.scheduleChange,
          value.scheduleChangeId,
          value.status == ScheduleChangeStatus.cancelled
              ? 'Temporary schedule change cancelled'
              : 'Temporary class schedule changed',
        ),
      );
    });
  }

  @override
  Future<List<Student>> fetchStudents(UserProfile actor) async {
    // Full student profiles include parent contacts and intentionally remain
    // unavailable to direct teacher queries until a trusted redacted view exists.
    if (actor.role == UserRole.teacher) return const [];
    Query<Map<String, dynamic>> query = _firestore.collection(
      FirestoreCollections.students,
    );
    if (actor.role == UserRole.instituteAdmin) {
      query = query.where('instituteId', isEqualTo: actor.instituteId);
    }
    final snapshot = await query.get();
    return snapshot.docs
        .map(
          (doc) =>
              Student.tryFromMap(_normalize(doc.id, doc.data(), 'studentId')),
        )
        .whereType<Student>()
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  @override
  Future<Student> createStudent(Student value, UserProfile actor) async {
    final validation = value.validate();
    if (validation != null) throw Failure(validation, code: 'invalid-input');
    if (!AcademicAuthorization.canCreateStudent(actor, value.instituteId)) {
      throw const Failure(
        'Student creation requires Institute Admin access or a trusted service.',
        code: 'backend-unavailable',
      );
    }
    final reference = _firestore
        .collection(FirestoreCollections.students)
        .doc(value.studentId);
    final reservation = _firestore
        .collection(FirestoreCollections.studentNumbers)
        .doc('${value.instituteId}_${value.studentNumber}');
    final auditReference = _firestore
        .collection(FirestoreCollections.auditLogs)
        .doc();
    await _firestore.runTransaction((transaction) async {
      if ((await transaction.get(reservation)).exists) {
        throw const Failure(
          'Student number already exists.',
          code: 'duplicate-student-number',
        );
      }
      transaction.set(reference, _serverMap(value.toMap()));
      transaction.set(reservation, {
        'instituteId': value.instituteId,
        'studentNumber': value.studentNumber,
        'studentId': value.studentId,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': actor.uid,
      });
      transaction.set(
        auditReference,
        _audit(
          auditReference.id,
          actor,
          value.instituteId,
          AuditAction.studentCreated,
          AuditTargetType.student,
          value.studentId,
          'Student created',
        ),
      );
    });
    return value;
  }

  @override
  Future<void> updateStudent(Student value, UserProfile actor) async {
    if (!AcademicAuthorization.canEditStudent(actor, value)) {
      throw const Failure(
        'Student editing requires Institute Admin access or a trusted service.',
        code: 'backend-unavailable',
      );
    }
    final reference = _firestore
        .collection(FirestoreCollections.students)
        .doc(value.studentId);
    final auditReference = _firestore
        .collection(FirestoreCollections.auditLogs)
        .doc();
    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(reference);
      final currentData = current.data();
      if (currentData == null) {
        throw const Failure('Student was not found.', code: 'not-found');
      }
      if (currentData['instituteId'] != value.instituteId ||
          currentData['studentNumber'] != value.studentNumber ||
          currentData['qrTokenHash'] != value.qrToken ||
          currentData['qrVersion'] != value.qrVersion ||
          currentData['qrEnabled'] != value.qrEnabled) {
        throw const Failure(
          'Protected fields require a trusted transaction.',
          code: 'immutable-field',
        );
      }
      transaction.update(
        reference,
        _serverMap(value.toMap())
          ..remove('studentId')
          ..remove('instituteId')
          ..remove('studentNumber')
          ..remove('qrTokenHash')
          ..remove('qrVersion')
          ..remove('qrEnabled')
          ..remove('createdAt')
          ..remove('createdBy'),
      );
      final action = value.status == StudentStatus.suspended
          ? AuditAction.studentSuspended
          : value.status == StudentStatus.leftInstitute
          ? AuditAction.studentMarkedLeft
          : value.active && currentData['active'] == false
          ? AuditAction.studentActivated
          : !value.active && currentData['active'] == true
          ? AuditAction.studentDeactivated
          : AuditAction.studentUpdated;
      transaction.set(
        auditReference,
        _audit(
          auditReference.id,
          actor,
          value.instituteId,
          action,
          AuditTargetType.student,
          value.studentId,
          'Student administration updated',
        ),
      );
    });
  }

  @override
  Future<List<ClassStudentAssignment>> fetchAssignments(
    UserProfile actor, {
    String? classId,
    String? studentId,
  }) async {
    if (actor.role == UserRole.teacher && classId == null) return const [];
    Query<Map<String, dynamic>> query = _firestore.collection(
      FirestoreCollections.classStudents,
    );
    if (classId != null) query = query.where('classId', isEqualTo: classId);
    if (studentId != null) {
      query = query.where('studentId', isEqualTo: studentId);
    }
    if (actor.role != UserRole.superAdmin) {
      query = query.where('instituteId', isEqualTo: actor.instituteId);
    }
    final snapshot = await query.get();
    return snapshot.docs
        .map(
          (doc) => ClassStudentAssignment.tryFromMap(
            _normalize(doc.id, doc.data(), 'assignmentId'),
          ),
        )
        .whereType<ClassStudentAssignment>()
        .toList();
  }

  @override
  Future<void> saveAssignment(
    ClassStudentAssignment value,
    UserProfile actor,
  ) async {
    if (actor.role == UserRole.teacher) {
      throw const Failure(
        'Student assignment requires Institute Admin access.',
        code: 'permission-denied',
      );
    }
    final reference = _firestore
        .collection(FirestoreCollections.classStudents)
        .doc(value.assignmentId);
    final classReference = _firestore
        .collection(FirestoreCollections.classes)
        .doc(value.classId);
    final studentReference = _firestore
        .collection(FirestoreCollections.students)
        .doc(value.studentId);
    final auditReference = _firestore
        .collection(FirestoreCollections.auditLogs)
        .doc();
    await _firestore.runTransaction((transaction) async {
      final academicClass = await transaction.get(classReference);
      final student = await transaction.get(studentReference);
      final existing = await transaction.get(reference);
      if (academicClass.data()?['instituteId'] != value.instituteId ||
          student.data()?['instituteId'] != value.instituteId) {
        throw const Failure(
          'Class and student must belong to the same institute.',
          code: 'institute-mismatch',
        );
      }
      if (value.active &&
          (academicClass.data()?['status'] ==
                  AcademicClassStatus.archived.name ||
              student.data()?['active'] != true)) {
        throw const Failure(
          'Archived classes and inactive students cannot receive enrolments.',
          code: 'inactive-target',
        );
      }
      if (existing.exists &&
          existing.data()?['active'] == true &&
          value.active) {
        throw const Failure(
          'Student is already assigned to this class.',
          code: 'duplicate-assignment',
        );
      }
      transaction.set(reference, _serverMap(value.toMap()));
      final action = value.active
          ? (value.scheduleOverlapConfirmed
                ? AuditAction.studentScheduleOverlapConfirmed
                : AuditAction.studentAssignedToClass)
          : AuditAction.studentRemovedFromClass;
      transaction.set(
        auditReference,
        _audit(
          auditReference.id,
          actor,
          value.instituteId,
          action,
          AuditTargetType.classStudentAssignment,
          value.assignmentId,
          value.scheduleOverlapConfirmed
              ? 'Student assignment overlap confirmed with a recorded reason'
              : value.active
              ? 'Student assigned to class'
              : 'Student removed from class',
        ),
      );
    });
  }

  @override
  Future<List<AuditLogEntry>> fetchAuditLogs({String? instituteId}) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection(FirestoreCollections.auditLogs)
        .orderBy('createdAt', descending: true)
        .limit(100);
    if (instituteId != null) {
      query = query.where('instituteId', isEqualTo: instituteId);
    }
    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => _auditEntry(doc.id, doc.data()))
        .whereType<AuditLogEntry>()
        .toList();
  }

  Map<String, Object?> _normalize(
    String id,
    Map<String, dynamic> raw,
    String idField,
  ) {
    Object? convert(Object? value) =>
        value is Timestamp ? value.toDate() : value;
    return {
      idField: id,
      for (final entry in raw.entries) entry.key: convert(entry.value),
    };
  }

  Map<String, Object?> _serverMap(Map<String, Object?> raw) => {
    for (final entry in raw.entries)
      entry.key: entry.value is DateTime
          ? _serverManagedTimestampFields.contains(entry.key)
                ? FieldValue.serverTimestamp()
                : Timestamp.fromDate(entry.value! as DateTime)
          : entry.value,
  };

  static const _serverManagedTimestampFields = {
    'createdAt',
    'updatedAt',
    'changedAt',
    'joinedAt',
    'leftAt',
    'scheduleOverlapConfirmedAt',
  };
  Map<String, Object?> _audit(
    String id,
    UserProfile actor,
    String instituteId,
    AuditAction action,
    AuditTargetType type,
    String targetId,
    String summary,
  ) => {
    'auditLogId': id,
    'actorUid': actor.uid,
    'actorRole': actor.role.name,
    'instituteId': instituteId,
    'action': action.name,
    'targetType': type.name,
    'targetId': targetId,
    'summary': summary,
    'createdAt': FieldValue.serverTimestamp(),
  };
  AuditLogEntry? _auditEntry(String id, Map<String, dynamic> data) {
    final role = UserRoleSerialization.tryParse(data['actorRole']);
    final action = AuditAction.values
        .where((e) => e.name == data['action'])
        .firstOrNull;
    final type = AuditTargetType.values
        .where((e) => e.name == data['targetType'])
        .firstOrNull;
    if (role == null ||
        action == null ||
        type == null ||
        data['createdAt'] is! Timestamp) {
      return null;
    }
    return AuditLogEntry(
      auditLogId: id,
      actorUid: data['actorUid'] as String,
      actorRole: role,
      instituteId: data['instituteId'] as String?,
      action: action,
      targetType: type,
      targetId: data['targetId'] as String,
      summary: data['summary'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }
}
