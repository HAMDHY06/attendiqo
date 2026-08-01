import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';

enum TeacherFilter { all, active, disabled, pendingFirstLogin }

class TeacherManagementController extends ChangeNotifier {
  TeacherManagementController({
    required this.actor,
    required this.repository,
    required this.provisioningService,
    required this.passwordResetService,
    this.verifiedSuperAdminClaim = false,
  });

  final UserProfile actor;
  final TeacherRepository repository;
  final TeacherProvisioningService provisioningService;
  final ManagedPasswordResetService passwordResetService;
  final bool verifiedSuperAdminClaim;

  List<UserProfile> teachers = [];
  List<AuditLogEntry> auditLogs = [];
  Map<String, List<String>> assignedClassNames = const {};
  bool loading = false;
  bool saving = false;
  String? resettingUid;
  String? error;
  String searchQuery = '';
  TeacherFilter filter = TeacherFilter.all;
  String? superAdminInstituteFilter;

  List<UserProfile> get visibleTeachers => teachers.where((teacher) {
    final query = searchQuery.trim().toLowerCase();
    final matchesSearch =
        query.isEmpty ||
        teacher.displayName.toLowerCase().contains(query) ||
        teacher.email.toLowerCase().contains(query) ||
        (teacher.employeeNumber?.toLowerCase().contains(query) ?? false);
    final status = teacher.effectiveTeacherStatus;
    final matchesStatus =
        filter == TeacherFilter.all ||
        (filter == TeacherFilter.active && status == TeacherStatus.active) ||
        (filter == TeacherFilter.disabled &&
            status == TeacherStatus.disabled) ||
        (filter == TeacherFilter.pendingFirstLogin &&
            status == TeacherStatus.pendingFirstLogin);
    final matchesInstitute =
        superAdminInstituteFilter == null ||
        teacher.instituteId == superAdminInstituteFilter;
    return matchesSearch && matchesStatus && matchesInstitute;
  }).toList();

  int get activeCount => teachers
      .where((value) => value.effectiveTeacherStatus == TeacherStatus.active)
      .length;
  int get disabledCount => teachers
      .where((value) => value.effectiveTeacherStatus == TeacherStatus.disabled)
      .length;
  int get pendingCount => teachers
      .where(
        (value) =>
            value.effectiveTeacherStatus == TeacherStatus.pendingFirstLogin,
      )
      .length;
  List<String> get instituteIds =>
      teachers.map((value) => value.instituteId!).toSet().toList()..sort();

  Future<void> load() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final instituteId = actor.role == UserRole.instituteAdmin
          ? actor.instituteId
          : null;
      final results = await Future.wait([
        repository.fetchTeachers(instituteId: instituteId),
        repository.fetchAuditLogs(instituteId: instituteId),
        repository.fetchAssignedClassNames(instituteId: instituteId),
      ]);
      teachers = results[0] as List<UserProfile>;
      auditLogs = results[1] as List<AuditLogEntry>;
      assignedClassNames = results[2] as Map<String, List<String>>;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to load teacher management. Please try again.',
      );
      _debugFailure('load', failure.code, failure.runtimeType);
    } catch (exception) {
      error = 'Unable to load teacher management. Please try again.';
      _debugFailure('load', null, exception.runtimeType);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setSearch(String value) {
    searchQuery = value;
    notifyListeners();
  }

  void setFilter(TeacherFilter value) {
    filter = value;
    notifyListeners();
  }

  void setInstituteFilter(String? value) {
    superAdminInstituteFilter = value;
    notifyListeners();
  }

  Future<TeacherCreationResult?> createTeacher({
    required String displayName,
    required String email,
    String? phoneNumber,
    String? employeeNumber,
    required TeacherPermissions permissions,
  }) async {
    if (saving) return null;
    final instituteId = actor.instituteId;
    if (instituteId == null) {
      error = 'Select an institute before creating a teacher.';
      notifyListeners();
      return null;
    }
    saving = true;
    error = null;
    notifyListeners();
    try {
      final result = await provisioningService.createTeacher(
        TeacherCreationRequest(
          actor: actor,
          instituteId: instituteId,
          email: email,
          displayName: displayName,
          phoneNumber: phoneNumber,
          employeeNumber: employeeNumber,
          permissions: permissions,
        ),
      );
      teachers = [...teachers, result.profile]
        ..sort((left, right) => left.displayName.compareTo(right.displayName));
      return result;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to create the teacher account. Please try again.',
      );
      _debugFailure('createTeacher', failure.code, failure.runtimeType);
      return null;
    } catch (exception) {
      error = 'Unable to create the teacher account. Please try again.';
      _debugFailure('createTeacher', null, exception.runtimeType);
      return null;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<bool> saveTeacher(UserProfile teacher) async {
    if (saving) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final updated = teacher.copyWithTeacher(
        updatedAt: DateTime.now().toUtc(),
        updatedBy: actor.uid,
      );
      await repository.updateTeacher(
        updated,
        actor: actor,
        verifiedSuperAdmin: verifiedSuperAdminClaim,
      );
      final index = teachers.indexWhere((value) => value.uid == teacher.uid);
      if (index >= 0) teachers[index] = updated;
      return true;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to save teacher changes. Please try again.',
      );
      _debugFailure('saveTeacher', failure.code, failure.runtimeType);
      return false;
    } catch (exception) {
      error = 'Unable to save teacher changes. Please try again.';
      _debugFailure('saveTeacher', null, exception.runtimeType);
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<bool> setActive(UserProfile teacher, bool active) => saveTeacher(
    teacher.copyWithTeacher(
      active: active,
      teacherStatus: !active
          ? TeacherStatus.disabled
          : teacher.mustChangePassword
          ? TeacherStatus.pendingFirstLogin
          : TeacherStatus.active,
    ),
  );

  Future<PasswordResetResult> sendPasswordReset(UserProfile teacher) async {
    if (resettingUid != null) {
      return const PasswordResetResult(
        PasswordResetStatus.failure,
        'A password-reset request is already in progress.',
      );
    }
    resettingUid = teacher.uid;
    notifyListeners();
    final result = await passwordResetService.sendPasswordResetEmail(
      ManagedPasswordResetRequest(actor: actor, target: teacher),
    );
    resettingUid = null;
    if (!result.succeeded) error = result.message;
    notifyListeners();
    return result;
  }

  List<AuditLogEntry> auditLogsFor(String teacherUid) =>
      auditLogs.where((entry) => entry.targetId == teacherUid).toList();

  bool canEditTeacher(UserProfile teacher) => TeacherAuthorization.canManage(
    actor,
    teacher,
    verifiedSuperAdmin: verifiedSuperAdminClaim,
  );

  Future<UserProfile?> updateTeacherPermissions(
    UserProfile teacher,
    TeacherPermissions permissions,
  ) async {
    if (saving || !canEditTeacher(teacher)) {
      if (!canEditTeacher(teacher)) {
        error = 'You do not have permission to edit this teacher.';
        notifyListeners();
      }
      return null;
    }
    final changedKeys = teacher.effectiveTeacherPermissions.changedKeys(
      permissions,
    );
    if (changedKeys.isEmpty) return teacher;
    final instituteId = teacher.instituteId;
    if (instituteId == null) {
      error = 'The teacher institute assignment is missing.';
      notifyListeners();
      return null;
    }
    saving = true;
    error = null;
    notifyListeners();
    try {
      await repository.updateTeacherPermissions(
        actor: actor,
        teacherUid: teacher.uid,
        instituteId: instituteId,
        permissions: permissions,
        verifiedSuperAdmin: verifiedSuperAdminClaim,
      );
      final updated = teacher.copyWithTeacher(
        permissions: permissions,
        updatedAt: DateTime.now().toUtc(),
        updatedBy: actor.uid,
      );
      final index = teachers.indexWhere((value) => value.uid == teacher.uid);
      if (index >= 0) teachers[index] = updated;
      auditLogs = await repository.fetchAuditLogs(
        instituteId: actor.role == UserRole.instituteAdmin
            ? actor.instituteId
            : null,
      );
      return updated;
    } on Failure catch (failure) {
      error = SafeErrorMapper.fromFailure(
        failure,
        fallback: 'Unable to save teacher permissions. Please try again.',
      );
      _debugFailure(
        'updateTeacherPermissions',
        failure.code,
        failure.runtimeType,
      );
      return null;
    } catch (exception) {
      error = 'Unable to save teacher permissions. Please try again.';
      _debugFailure('updateTeacherPermissions', null, exception.runtimeType);
      return null;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  void _debugFailure(String operation, String? code, Type type) {
    if (kDebugMode) {
      debugPrint(
        '[TeacherManagement] $operation failed code=${code ?? 'unknown'} type=$type',
      );
    }
  }
}
