import 'package:attendiqo/features/super_admin/application/super_admin_controller.dart';
import 'package:attendiqo/features/super_admin/presentation/super_admin_screens.dart';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryInstituteRepository implements InstituteRepository {
  MemoryInstituteRepository(this.values);
  final List<Institute> values;
  final List<AuditLogEntry> logs = [];
  final Map<String, List<UserProfile>> adminsByInstitute = {};

  @override
  Future<Institute> createInstitute(Institute institute) async {
    if (values.any((value) => value.instituteCode == institute.instituteCode)) {
      throw const Failure('Duplicate', code: 'duplicate-code');
    }
    values.add(institute);
    logs.add(_log(institute, AuditAction.instituteCreated));
    return institute;
  }

  @override
  Future<List<AuditLogEntry>> fetchAuditLogs({String? instituteId}) async =>
      logs
          .where(
            (value) => instituteId == null || value.instituteId == instituteId,
          )
          .toList();

  @override
  Future<List<UserProfile>> fetchInstituteAdmins(String instituteId) async =>
      adminsByInstitute[instituteId] ?? [];

  @override
  Future<List<Institute>> fetchInstitutes() async => List.of(values);

  @override
  Future<Institute?> fetchInstituteById(String instituteId) async {
    for (final value in values) {
      if (value.instituteId == instituteId) return value;
    }
    return null;
  }

  @override
  Future<void> updateInstitute(Institute institute) async {
    final index = values.indexWhere(
      (value) => value.instituteId == institute.instituteId,
    );
    values[index] = institute;
    logs.add(_log(institute, AuditAction.instituteUpdated));
  }

  AuditLogEntry _log(Institute institute, AuditAction action) => AuditLogEntry(
    auditLogId: 'log-${logs.length}',
    actorUid: 'super-1',
    actorRole: UserRole.superAdmin,
    instituteId: institute.instituteId,
    action: action,
    targetType: AuditTargetType.institute,
    targetId: institute.instituteId,
    summary: action.name,
    createdAt: DateTime.utc(2026, 8, 1),
  );
}

Institute sampleInstitute({
  String id = 'i1',
  String code = 'ALPHA',
  String name = 'Alpha College',
  InstituteStatus status = InstituteStatus.active,
}) {
  final created = Institute.newInstitute(
    instituteId: id,
    instituteCode: code,
    name: name,
    address: 'Colombo',
    contactNumber: '+94771234567',
    email: 'office@example.com',
    now: DateTime.utc(2026, 8, 1),
    actorUid: 'super-1',
  );
  return created.copyWith(
    status: status,
    active: status == InstituteStatus.active,
  );
}

SuperAdminController controllerFor(
  MemoryInstituteRepository repository, {
  MockInstituteAdminProvisioningService? service,
  MockManagedPasswordResetService? resetService,
}) => SuperAdminController(
  repository: repository,
  provisioningService: service ?? MockInstituteAdminProvisioningService(),
  passwordResetService: resetService ?? MockManagedPasswordResetService(),
  actor: userProfile(uid: 'super-1', role: UserRole.superAdmin),
  idFactory: () => 'new-id',
);

UserProfile userProfile({
  required String uid,
  required UserRole role,
  String? instituteId,
  bool active = true,
}) => UserProfile(
  uid: uid,
  email: '$uid@example.com',
  displayName: uid,
  role: role,
  instituteId: instituteId,
  active: active,
  mustChangePassword: false,
  createdAt: DateTime.utc(2026, 8, 1),
  createdBy: 'super-1',
  updatedAt: DateTime.utc(2026, 8, 1),
);

void main() {
  test(
    'institute list loads, searches, filters, and calculates statistics',
    () async {
      final repository = MemoryInstituteRepository([
        sampleInstitute(),
        sampleInstitute(
          id: 'i2',
          code: 'BETA',
          name: 'Beta Academy',
          status: InstituteStatus.suspended,
        ),
      ]);
      final controller = controllerFor(repository);
      await controller.load();

      expect(controller.institutes, hasLength(2));
      expect(controller.statistics.suspendedInstitutes, 1);
      controller.setSearch('beta');
      expect(controller.visibleInstitutes.single.instituteCode, 'BETA');
      controller.setSearch('');
      controller.setFilter(InstituteFilter.active);
      expect(controller.visibleInstitutes.single.instituteCode, 'ALPHA');
    },
  );

  test(
    'institute creation normalizes code and creates an audit event',
    () async {
      final repository = MemoryInstituteRepository([]);
      final controller = controllerFor(repository);
      final created = await controller.createInstitute(
        code: ' new_1 ',
        name: 'New Institute',
        address: '',
        contactNumber: '+94771234567',
        email: '',
      );

      expect(created!.instituteCode, 'NEW_1');
      expect(repository.logs.single.action, AuditAction.instituteCreated);
    },
  );

  testWidgets('institute creation form validates required values', (
    tester,
  ) async {
    final controller = controllerFor(MemoryInstituteRepository([]));
    await tester.pumpWidget(
      MaterialApp(home: InstituteFormScreen(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('saveInstitute')));
    await tester.pump();

    expect(find.text('Institute code is required'), findsOneWidget);
    expect(find.text('Institute name is required'), findsOneWidget);
    expect(find.text('Contact number is required'), findsOneWidget);
  });

  testWidgets('suspension requires confirmation', (tester) async {
    final repository = MemoryInstituteRepository([sampleInstitute()]);
    final controller = controllerFor(repository);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: InstituteDetailsScreen(
          controller: controller,
          institute: repository.values.single,
        ),
      ),
    );
    await tester.tap(find.text('Suspend'));
    await tester.pumpAndSettle();
    expect(find.text('Suspend institute?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmSuspension')));
    await tester.pumpAndSettle();
    expect(repository.values.single.status, InstituteStatus.suspended);
  });

  testWidgets('admin request uses mock and reveals temporary password once', (
    tester,
  ) async {
    final service = MockInstituteAdminProvisioningService();
    final controller = controllerFor(
      MemoryInstituteRepository([sampleInstitute()]),
      service: service,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CreateInstituteAdminScreen(
          controller: controller,
          institute: sampleInstitute(),
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      'Admin User',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'admin@example.com',
    );
    await tester.tap(find.byKey(const Key('createInstituteAdmin')));
    await tester.pumpAndSettle();

    expect(service.requests.single.instituteId, 'i1');
    expect(find.byKey(const Key('temporaryPassword')), findsOneWidget);
    await tester.tap(find.text('I saved it securely'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('temporaryPassword')), findsNothing);
  });

  testWidgets('Super Admin can send a safe reset email request', (
    tester,
  ) async {
    final repository = MemoryInstituteRepository([sampleInstitute()]);
    final admin = userProfile(
      uid: 'admin-1',
      role: UserRole.instituteAdmin,
      instituteId: 'i1',
    );
    repository.adminsByInstitute['i1'] = [admin];
    final resetService = MockManagedPasswordResetService();
    final controller = controllerFor(repository, resetService: resetService);

    await tester.pumpWidget(
      MaterialApp(
        home: InstituteAdminListScreen(
          controller: controller,
          institute: sampleInstitute(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send Password Reset Email'));
    await tester.pumpAndSettle();

    expect(resetService.requests.single.target.uid, 'admin-1');
    expect(find.text(PasswordResetResult.safeSuccess.message), findsOneWidget);
  });
}
