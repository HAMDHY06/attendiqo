import 'dart:math';

import 'enums.dart';
import 'models.dart';

class Institute {
  const Institute({
    required this.instituteId,
    required this.instituteCode,
    required this.name,
    required this.address,
    required this.contactNumber,
    required this.email,
    required this.active,
    required this.status,
    required this.pushNotificationsEnabled,
    required this.smsEnabled,
    required this.smsMonthlyLimit,
    required this.allowPaidExtraSms,
    required this.smsUsedThisMonth,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
  });

  factory Institute.newInstitute({
    required String instituteId,
    required String instituteCode,
    required String name,
    required String address,
    required String contactNumber,
    required String email,
    required DateTime now,
    required String actorUid,
  }) => Institute(
    instituteId: instituteId,
    instituteCode: instituteCode,
    name: name,
    address: address,
    contactNumber: contactNumber,
    email: email,
    active: true,
    status: InstituteStatus.active,
    pushNotificationsEnabled: true,
    smsEnabled: false,
    smsMonthlyLimit: 0,
    allowPaidExtraSms: false,
    smsUsedThisMonth: 0,
    createdAt: now,
    createdBy: actorUid,
    updatedAt: now,
    updatedBy: actorUid,
  );

  final String instituteId;
  final String instituteCode;
  final String name;
  final String address;
  final String contactNumber;
  final String email;
  final bool active;
  final InstituteStatus status;
  final bool pushNotificationsEnabled;
  final bool smsEnabled;
  final int smsMonthlyLimit;
  final bool allowPaidExtraSms;
  final int smsUsedThisMonth;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;

  Institute copyWith({
    String? name,
    String? address,
    String? contactNumber,
    String? email,
    bool? active,
    InstituteStatus? status,
    bool? pushNotificationsEnabled,
    bool? smsEnabled,
    int? smsMonthlyLimit,
    bool? allowPaidExtraSms,
    DateTime? updatedAt,
    String? updatedBy,
  }) => Institute(
    instituteId: instituteId,
    instituteCode: instituteCode,
    name: name ?? this.name,
    address: address ?? this.address,
    contactNumber: contactNumber ?? this.contactNumber,
    email: email ?? this.email,
    active: active ?? this.active,
    status: status ?? this.status,
    pushNotificationsEnabled:
        pushNotificationsEnabled ?? this.pushNotificationsEnabled,
    smsEnabled: smsEnabled ?? this.smsEnabled,
    smsMonthlyLimit: smsMonthlyLimit ?? this.smsMonthlyLimit,
    allowPaidExtraSms: allowPaidExtraSms ?? this.allowPaidExtraSms,
    smsUsedThisMonth: smsUsedThisMonth,
    createdAt: createdAt,
    createdBy: createdBy,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );

  static Institute? tryFromMap(Map<String, Object?> data) {
    final status = InstituteStatus.values
        .where((value) => value.name == data['status'])
        .firstOrNull;
    if (status == null ||
        data['instituteId'] is! String ||
        data['instituteCode'] is! String ||
        data['name'] is! String ||
        data['address'] is! String ||
        data['contactNumber'] is! String ||
        data['email'] is! String ||
        data['active'] is! bool ||
        data['pushNotificationsEnabled'] is! bool ||
        data['smsEnabled'] is! bool ||
        data['smsMonthlyLimit'] is! int ||
        data['allowPaidExtraSms'] is! bool ||
        data['smsUsedThisMonth'] is! int ||
        data['createdAt'] is! DateTime ||
        data['createdBy'] is! String ||
        data['updatedAt'] is! DateTime ||
        data['updatedBy'] is! String) {
      return null;
    }
    return Institute(
      instituteId: data['instituteId']! as String,
      instituteCode: data['instituteCode']! as String,
      name: data['name']! as String,
      address: data['address']! as String,
      contactNumber: data['contactNumber']! as String,
      email: data['email']! as String,
      active: data['active']! as bool,
      status: status,
      pushNotificationsEnabled: data['pushNotificationsEnabled']! as bool,
      smsEnabled: data['smsEnabled']! as bool,
      smsMonthlyLimit: data['smsMonthlyLimit']! as int,
      allowPaidExtraSms: data['allowPaidExtraSms']! as bool,
      smsUsedThisMonth: data['smsUsedThisMonth']! as int,
      createdAt: data['createdAt']! as DateTime,
      createdBy: data['createdBy']! as String,
      updatedAt: data['updatedAt']! as DateTime,
      updatedBy: data['updatedBy']! as String,
    );
  }
}

class AuditLogEntry {
  const AuditLogEntry({
    required this.auditLogId,
    required this.actorUid,
    required this.actorRole,
    required this.instituteId,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.summary,
    required this.createdAt,
  });
  final String auditLogId;
  final String actorUid;
  final UserRole actorRole;
  final String? instituteId;
  final AuditAction action;
  final AuditTargetType targetType;
  final String targetId;
  final String summary;
  final DateTime createdAt;
}

class InstituteStatistics {
  const InstituteStatistics({
    required this.totalInstitutes,
    required this.activeInstitutes,
    required this.suspendedInstitutes,
    required this.totalInstituteAdmins,
    required this.pushEnabledInstitutes,
    required this.smsEnabledInstitutes,
  });
  final int totalInstitutes;
  final int activeInstitutes;
  final int suspendedInstitutes;
  final int totalInstituteAdmins;
  final int pushEnabledInstitutes;
  final int smsEnabledInstitutes;
}

class InstituteAdminCreationRequest {
  const InstituteAdminCreationRequest({
    required this.instituteId,
    required this.email,
    required this.displayName,
    required this.actorUid,
  });
  final String instituteId;
  final String email;
  final String displayName;
  final String actorUid;
}

class InstituteAdminCreationResult {
  const InstituteAdminCreationResult({
    required this.profile,
    required this.oneTimeTemporaryPassword,
  });
  final UserProfile profile;
  final String oneTimeTemporaryPassword;
}

abstract interface class AuditLogRepository {
  Future<List<AuditLogEntry>> fetchAuditLogs({String? instituteId});
}

abstract interface class InstituteRepository implements AuditLogRepository {
  Future<List<Institute>> fetchInstitutes();
  Future<Institute> createInstitute(Institute institute);
  Future<void> updateInstitute(Institute institute);
  Future<List<UserProfile>> fetchInstituteAdmins(String instituteId);
}

abstract interface class InstituteAdminProvisioningService {
  Future<InstituteAdminCreationResult> createInstituteAdmin(
    InstituteAdminCreationRequest request,
  );
  Future<void> disableInstituteAdmin({
    required String uid,
    required String instituteId,
    required String actorUid,
  });
}

class UnavailableInstituteAdminProvisioningService
    implements InstituteAdminProvisioningService {
  const UnavailableInstituteAdminProvisioningService();

  Never _unavailable() => throw const Failure(
    'Privileged account service is not deployed. Contact HamdhyTech support.',
    code: 'backend-unavailable',
  );

  @override
  Future<InstituteAdminCreationResult> createInstituteAdmin(
    InstituteAdminCreationRequest request,
  ) async => _unavailable();

  @override
  Future<void> disableInstituteAdmin({
    required String uid,
    required String instituteId,
    required String actorUid,
  }) async => _unavailable();
}

class MockInstituteAdminProvisioningService
    implements InstituteAdminProvisioningService {
  MockInstituteAdminProvisioningService({Random? random})
    : _random = random ?? Random.secure();
  final Random _random;
  final List<InstituteAdminCreationRequest> requests = [];

  String _temporaryPassword() {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    const digits = '23456789';
    const specials = '!@#%';
    final body = List.generate(
      8,
      (_) => letters[_random.nextInt(letters.length)],
    ).join();
    return 'A${body}a${digits[_random.nextInt(digits.length)]}${specials[_random.nextInt(specials.length)]}';
  }

  @override
  Future<InstituteAdminCreationResult> createInstituteAdmin(
    InstituteAdminCreationRequest request,
  ) async {
    requests.add(request);
    final now = DateTime.now().toUtc();
    return InstituteAdminCreationResult(
      profile: UserProfile(
        uid: 'mock-${now.microsecondsSinceEpoch}',
        email: request.email,
        displayName: request.displayName,
        role: UserRole.instituteAdmin,
        instituteId: request.instituteId,
        active: true,
        mustChangePassword: true,
        createdAt: now,
        createdBy: request.actorUid,
        updatedAt: now,
      ),
      oneTimeTemporaryPassword: _temporaryPassword(),
    );
  }

  @override
  Future<void> disableInstituteAdmin({
    required String uid,
    required String instituteId,
    required String actorUid,
  }) async {}
}
