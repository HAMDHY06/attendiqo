import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

abstract interface class TeacherPasswordRecoveryRepository {
  Future<List<UserProfile>> fetchTeachers(String instituteId);
}

class FirestoreTeacherPasswordRecoveryRepository
    implements TeacherPasswordRecoveryRepository {
  FirestoreTeacherPasswordRecoveryRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<List<UserProfile>> fetchTeachers(String instituteId) async {
    try {
      final snapshot = await _firestore
          .collection(FirestoreCollections.users)
          .where('instituteId', isEqualTo: instituteId)
          .where('role', isEqualTo: UserRole.teacher.name)
          .get();
      return snapshot.docs
          .map((document) => _profile(document.id, document.data()))
          .whereType<UserProfile>()
          .toList()
        ..sort((left, right) => left.displayName.compareTo(right.displayName));
    } on FirebaseException catch (error) {
      throw Failure(
        error.code == 'permission-denied'
            ? 'You cannot access teacher recovery information.'
            : 'Unable to load teacher accounts. Check your connection.',
        code: error.code,
      );
    }
  }

  UserProfile? _profile(String uid, Map<String, dynamic> data) {
    final normalized = <String, Object?>{'uid': uid};
    for (final entry in data.entries) {
      normalized[entry.key] = entry.value is Timestamp
          ? (entry.value as Timestamp).toDate()
          : entry.value;
    }
    return UserProfile.tryFromMap(normalized);
  }
}
