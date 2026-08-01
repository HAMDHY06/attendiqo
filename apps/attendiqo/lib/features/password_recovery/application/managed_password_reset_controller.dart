import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';

import '../data/firestore_teacher_password_recovery_repository.dart';

class ManagedPasswordResetController extends ChangeNotifier {
  ManagedPasswordResetController({
    required this.actor,
    required this.service,
    this.teacherRepository,
  });

  final UserProfile actor;
  final ManagedPasswordResetService service;
  final TeacherPasswordRecoveryRepository? teacherRepository;

  List<UserProfile> teachers = [];
  bool loadingDirectory = false;
  String? loadingTargetUid;
  PasswordResetResult? result;
  String? directoryError;

  Future<void> loadTeachers() async {
    final instituteId = actor.instituteId;
    if (actor.role != UserRole.instituteAdmin || instituteId == null) return;
    loadingDirectory = true;
    directoryError = null;
    notifyListeners();
    try {
      teachers = await teacherRepository!.fetchTeachers(instituteId);
    } on Failure catch (failure) {
      directoryError = failure.message;
    } catch (_) {
      directoryError = 'Unable to load teacher accounts. Please try again.';
    } finally {
      loadingDirectory = false;
      notifyListeners();
    }
  }

  Future<PasswordResetResult> send(UserProfile target) async {
    loadingTargetUid = target.uid;
    result = const PasswordResetResult(
      PasswordResetStatus.loading,
      'Requesting password-reset email...',
    );
    notifyListeners();
    final response = await service.sendPasswordResetEmail(
      ManagedPasswordResetRequest(actor: actor, target: target),
    );
    loadingTargetUid = null;
    result = response;
    notifyListeners();
    return response;
  }
}
