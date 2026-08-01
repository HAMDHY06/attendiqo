import 'dart:math';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final timestamp = DateTime.utc(2026, 8, 1);

  test('institute model parses typed data', () {
    final institute = Institute.tryFromMap({
      'instituteId': 'i1',
      'instituteCode': 'COLLEGE_1',
      'name': 'College One',
      'address': 'Colombo',
      'contactNumber': '+94771234567',
      'email': 'office@example.com',
      'active': true,
      'status': 'active',
      'pushNotificationsEnabled': true,
      'smsEnabled': false,
      'smsMonthlyLimit': 0,
      'allowPaidExtraSms': false,
      'smsUsedThisMonth': 0,
      'createdAt': timestamp,
      'createdBy': 'super-1',
      'updatedAt': timestamp,
      'updatedBy': 'super-1',
    });

    expect(institute, isNotNull);
    expect(institute!.status, InstituteStatus.active);
    expect(institute.instituteCode, 'COLLEGE_1');
  });

  test('new institutes default SMS and paid extra SMS to off', () {
    final institute = Institute.newInstitute(
      instituteId: 'i1',
      instituteCode: 'CODE1',
      name: 'Institute',
      address: '',
      contactNumber: '+94771234567',
      email: '',
      now: timestamp,
      actorUid: 'super-1',
    );

    expect(institute.smsEnabled, isFalse);
    expect(institute.allowPaidExtraSms, isFalse);
    expect(institute.pushNotificationsEnabled, isTrue);
    expect(institute.smsUsedThisMonth, 0);
  });

  test('institute code validation is uppercase and safe', () {
    expect(InstituteCodeValidator.validate('ABC_12'), isNull);
    expect(InstituteCodeValidator.validate('abc'), contains('uppercase'));
    expect(InstituteCodeValidator.validate('A B'), isNotNull);
    expect(InstituteCodeValidator.normalize('  abc-1 '), 'ABC-1');
  });

  test(
    'mock provisioning returns an ephemeral policy-compliant password',
    () async {
      final service = MockInstituteAdminProvisioningService(random: Random(7));
      const request = InstituteAdminCreationRequest(
        instituteId: 'i1',
        email: 'admin@example.com',
        displayName: 'Admin One',
        actorUid: 'super-1',
      );
      final result = await service.createInstituteAdmin(request);

      expect(service.requests, [request]);
      expect(result.profile.role, UserRole.instituteAdmin);
      expect(result.profile.mustChangePassword, isTrue);
      expect(result.profile.instituteId, 'i1');
      expect(
        PasswordValidator.validateForCreation(result.oneTimeTemporaryPassword),
        isNull,
      );
      expect(result.profile.toString(), isNot(contains('password')));
    },
  );

  test('audit log has typed action and contains no secret field', () {
    final log = AuditLogEntry(
      auditLogId: 'a1',
      actorUid: 'super-1',
      actorRole: UserRole.superAdmin,
      instituteId: 'i1',
      action: AuditAction.instituteCreated,
      targetType: AuditTargetType.institute,
      targetId: 'i1',
      summary: 'Institute created',
      createdAt: timestamp,
    );
    expect(log.action, AuditAction.instituteCreated);
    expect(log.summary.toLowerCase(), isNot(contains('password')));
  });

  test('Phase 3 collection constants are centralized', () {
    expect(FirestoreCollections.institutes, 'institutes');
    expect(FirestoreCollections.instituteCodes, 'institute_codes');
    expect(FirestoreCollections.auditLogs, 'audit_logs');
    expect(FirestoreCollections.smsSettings, 'sms_settings');
    expect(FirestoreCollections.smsUsage, 'sms_usage');
  });
}
