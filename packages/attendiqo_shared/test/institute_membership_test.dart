import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Institute join membership foundation', () {
    test(
      'normalizes a visible institute join code without treating it as a secret',
      () {
        expect(InstituteJoinCode.tryParse(' demo-2026 ')?.value, 'DEMO-2026');
        expect(InstituteJoinCode.tryParse('short'), isNull);
        expect(InstituteJoinCode.tryParse('unsafe code'), isNull);
      },
    );

    test(
      'uses one deterministic membership document per user and institute',
      () {
        final membership = InstituteMembership(
          uid: 'user_a',
          instituteId: 'institute_a',
          role: UserRole.teacher,
          status: InstituteMembershipStatus.active,
          requestedAt: DateTime.utc(2026),
        );
        expect(membership.documentId, 'user_a_institute_a');
        expect(membership.isActive, isTrue);
        expect(membership.isValidInstituteRole, isTrue);
      },
    );

    test('never permits an institute join request to grant Super Admin', () {
      expect(
        InstituteMembershipPolicy.mayRequest(UserRole.superAdmin),
        isFalse,
      );
      expect(
        InstituteMembershipPolicy.mayApprove(
          reviewerRole: UserRole.instituteAdmin,
          requestedRole: UserRole.instituteAdmin,
          sameInstitute: true,
        ),
        isFalse,
      );
      expect(
        InstituteMembershipPolicy.mayApprove(
          reviewerRole: UserRole.superAdmin,
          requestedRole: UserRole.instituteAdmin,
          sameInstitute: false,
        ),
        isTrue,
      );
    });

    test('selects only active memberships for the authenticated user', () {
      final memberships = [
        InstituteMembership(
          uid: 'user_a',
          instituteId: 'institute_b',
          role: UserRole.teacher,
          status: InstituteMembershipStatus.pending,
          requestedAt: DateTime.utc(2026),
        ),
        InstituteMembership(
          uid: 'user_a',
          instituteId: 'institute_a',
          role: UserRole.instituteAdmin,
          status: InstituteMembershipStatus.active,
          requestedAt: DateTime.utc(2026),
        ),
        InstituteMembership(
          uid: 'other_user',
          instituteId: 'institute_c',
          role: UserRole.teacher,
          status: InstituteMembershipStatus.active,
          requestedAt: DateTime.utc(2026),
        ),
      ];

      final selected = ActiveInstituteSelection.select(
        memberships: memberships,
        uid: 'user_a',
        preferredInstituteId: 'institute_b',
      );

      expect(selected?.instituteId, 'institute_a');
      expect(selected?.canUseTeacherCapabilities, isTrue);
      expect(selected?.usesLegacyCompatibility, isFalse);
    });

    test('legacy compatibility remains explicit and session-only', () {
      final session = ActiveInstituteSession.legacy(
        uid: 'user_a',
        instituteId: 'institute_a',
        role: UserRole.teacher,
      );

      expect(session.usesLegacyCompatibility, isTrue);
      expect(session.instituteId, 'institute_a');
      expect(session.canUseTeacherCapabilities, isTrue);
    });
  });
}
