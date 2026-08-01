import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';

enum InstituteFilter { all, active, suspended, inactive }

class SuperAdminController extends ChangeNotifier {
  SuperAdminController({
    required this.repository,
    required this.provisioningService,
    required this.passwordResetService,
    required this.actor,
    String Function()? idFactory,
  }) : _idFactory =
           idFactory ??
           (() => 'inst-${DateTime.now().toUtc().microsecondsSinceEpoch}');
  final InstituteRepository repository;
  final InstituteAdminProvisioningService provisioningService;
  final ManagedPasswordResetService passwordResetService;
  final UserProfile actor;
  String get actorUid => actor.uid;
  final String Function() _idFactory;

  List<Institute> institutes = [];
  List<AuditLogEntry> auditLogs = [];
  bool loading = false;
  String? error;
  String searchQuery = '';
  InstituteFilter filter = InstituteFilter.all;
  int totalInstituteAdmins = 0;
  String? resettingUid;
  PasswordResetResult? passwordResetResult;

  List<Institute> get visibleInstitutes => institutes.where((institute) {
    final query = searchQuery.trim().toLowerCase();
    final matchesSearch =
        query.isEmpty ||
        institute.name.toLowerCase().contains(query) ||
        institute.instituteCode.toLowerCase().contains(query);
    final matchesFilter =
        filter == InstituteFilter.all || institute.status.name == filter.name;
    return matchesSearch && matchesFilter;
  }).toList();

  InstituteStatistics get statistics => InstituteStatistics(
    totalInstitutes: institutes.length,
    activeInstitutes: institutes
        .where((value) => value.status == InstituteStatus.active)
        .length,
    suspendedInstitutes: institutes
        .where((value) => value.status == InstituteStatus.suspended)
        .length,
    totalInstituteAdmins: totalInstituteAdmins,
    pushEnabledInstitutes: institutes
        .where((value) => value.pushNotificationsEnabled)
        .length,
    smsEnabledInstitutes: institutes.where((value) => value.smsEnabled).length,
  );

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      institutes = await repository.fetchInstitutes();
      final adminLists = await Future.wait(
        institutes.map(
          (value) => repository.fetchInstituteAdmins(value.instituteId),
        ),
      );
      totalInstituteAdmins = adminLists.fold(
        0,
        (sum, values) => sum + values.length,
      );
      auditLogs = await repository.fetchAuditLogs();
    } catch (_) {
      error = 'Unable to load institute management data. Please try again.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setSearch(String value) {
    searchQuery = value;
    notifyListeners();
  }

  void setFilter(InstituteFilter value) {
    filter = value;
    notifyListeners();
  }

  Future<Institute?> createInstitute({
    required String code,
    required String name,
    required String address,
    required String contactNumber,
    required String email,
  }) async {
    final now = DateTime.now().toUtc();
    final value = Institute.newInstitute(
      instituteId: _idFactory(),
      instituteCode: InstituteCodeValidator.normalize(code),
      name: name.trim(),
      address: address.trim(),
      contactNumber: contactNumber.trim(),
      email: email.trim(),
      now: now,
      actorUid: actorUid,
    );
    try {
      final created = await repository.createInstitute(value);
      institutes = [...institutes, created]
        ..sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
      return created;
    } on Failure catch (failure) {
      error = failure.code == 'duplicate-code'
          ? 'That institute code is already in use.'
          : failure.message;
      notifyListeners();
      return null;
    } catch (_) {
      error = 'Unable to create the institute. Please try again.';
      notifyListeners();
      return null;
    }
  }

  Future<bool> save(Institute value) async {
    try {
      final updated = value.copyWith(
        updatedAt: DateTime.now().toUtc(),
        updatedBy: actorUid,
      );
      await repository.updateInstitute(updated);
      final index = institutes.indexWhere(
        (item) => item.instituteId == value.instituteId,
      );
      if (index >= 0) institutes[index] = updated;
      notifyListeners();
      return true;
    } catch (_) {
      error = 'Unable to save institute changes.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> setStatus(Institute value, InstituteStatus status) => save(
    value.copyWith(status: status, active: status == InstituteStatus.active),
  );
  Future<List<UserProfile>> admins(String instituteId) =>
      repository.fetchInstituteAdmins(instituteId);
  Future<InstituteAdminCreationResult?> createAdmin(
    InstituteAdminCreationRequest request,
  ) async {
    try {
      final result = await provisioningService.createInstituteAdmin(request);
      totalInstituteAdmins += 1;
      notifyListeners();
      return result;
    } on Failure catch (failure) {
      error = failure.message;
      notifyListeners();
      return null;
    } catch (_) {
      error = 'Unable to create the Institute Admin account.';
      notifyListeners();
      return null;
    }
  }

  Future<bool> disableAdmin(UserProfile profile) async {
    try {
      await provisioningService.disableInstituteAdmin(
        uid: profile.uid,
        instituteId: profile.instituteId!,
        actorUid: actorUid,
      );
      return true;
    } on Failure catch (failure) {
      error = failure.message;
      notifyListeners();
      return false;
    } catch (_) {
      error = 'Unable to disable this Institute Admin.';
      notifyListeners();
      return false;
    }
  }

  Future<PasswordResetResult> resetAdminPassword(UserProfile profile) async {
    resettingUid = profile.uid;
    passwordResetResult = const PasswordResetResult(
      PasswordResetStatus.loading,
      'Requesting password-reset email...',
    );
    notifyListeners();
    final result = await passwordResetService.sendPasswordResetEmail(
      ManagedPasswordResetRequest(actor: actor, target: profile),
    );
    resettingUid = null;
    passwordResetResult = result;
    error = result.succeeded ? null : result.message;
    notifyListeners();
    return result;
  }
}
