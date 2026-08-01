import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile profile({
  required String uid,
  required UserRole role,
  String? instituteId,
  String? email,
  bool active = true,
}) => UserProfile(
  uid: uid,
  email: email ?? '$uid@example.com',
  displayName: uid,
  role: role,
  instituteId: instituteId,
  active: active,
  mustChangePassword: true,
  createdAt: DateTime.utc(2026, 8, 1),
  createdBy: 'provisioner',
  updatedAt: DateTime.utc(2026, 8, 1),
);

void main() {
  test('Super Admin may reset Institute Admin and Teacher accounts', () {
    final actor = profile(uid: 'super', role: UserRole.superAdmin);
    expect(
      ManagedPasswordResetRequest(
        actor: actor,
        target: profile(
          uid: 'admin',
          role: UserRole.instituteAdmin,
          instituteId: 'i1',
        ),
      ).isAuthorized,
      isTrue,
    );
    expect(
      ManagedPasswordResetRequest(
        actor: actor,
        target: profile(
          uid: 'teacher',
          role: UserRole.teacher,
          instituteId: 'i1',
        ),
      ).isAuthorized,
      isTrue,
    );
  });

  test('Institute Admin is limited to teachers in the same institute', () {
    final actor = profile(
      uid: 'admin',
      role: UserRole.instituteAdmin,
      instituteId: 'i1',
    );
    expect(
      ManagedPasswordResetRequest(
        actor: actor,
        target: profile(
          uid: 'teacher-a',
          role: UserRole.teacher,
          instituteId: 'i1',
        ),
      ).isAuthorized,
      isTrue,
    );
    expect(
      ManagedPasswordResetRequest(
        actor: actor,
        target: profile(
          uid: 'teacher-b',
          role: UserRole.teacher,
          instituteId: 'i2',
        ),
      ).isAuthorized,
      isFalse,
    );
  });

  test(
    'mock reports invalid, disabled, network, and safe success states',
    () async {
      final actor = profile(
        uid: 'admin',
        role: UserRole.instituteAdmin,
        instituteId: 'i1',
      );
      ManagedPasswordResetRequest request(UserProfile target) =>
          ManagedPasswordResetRequest(actor: actor, target: target);
      UserProfile teacher({String? email, bool active = true}) => profile(
        uid: 'teacher',
        role: UserRole.teacher,
        instituteId: 'i1',
        email: email,
        active: active,
      );

      final service = MockManagedPasswordResetService();
      expect(
        (await service.sendPasswordResetEmail(
          request(teacher(email: 'invalid')),
        )).status,
        PasswordResetStatus.invalidEmail,
      );
      expect(
        (await service.sendPasswordResetEmail(
          request(teacher(active: false)),
        )).status,
        PasswordResetStatus.disabledAccount,
      );
      service.nextStatus = PasswordResetStatus.networkError;
      expect(
        (await service.sendPasswordResetEmail(request(teacher()))).status,
        PasswordResetStatus.networkError,
      );
      service.nextStatus = null;
      final success = await service.sendPasswordResetEmail(request(teacher()));
      expect(success, same(PasswordResetResult.safeSuccess));
      expect(success.message.toLowerCase(), isNot(contains('exists')));
    },
  );

  test('managed reset models contain no password, link, or token fields', () {
    final request = ManagedPasswordResetRequest(
      actor: profile(uid: 'super', role: UserRole.superAdmin),
      target: profile(
        uid: 'admin',
        role: UserRole.instituteAdmin,
        instituteId: 'i1',
      ),
    );
    final description = request.toString().toLowerCase();
    expect(description, isNot(contains('password:')));
    expect(description, isNot(contains('token')));
    expect(description, isNot(contains('resetlink')));
  });
}
