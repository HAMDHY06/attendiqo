import 'enums.dart';
import 'models.dart';

/// A safe, persistent institute identifier shown to authorised operators.
/// It is intentionally not a password, invite secret, or access grant.
class InstituteJoinCode {
  const InstituteJoinCode._(this.value);

  final String value;

  static InstituteJoinCode? tryParse(String value) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9][A-Z0-9-]{5,23}$').hasMatch(normalized)) {
      return null;
    }
    return InstituteJoinCode._(normalized);
  }
}

/// A role assignment for one institute. The user identity remains in
/// users/{uid}; this document is the future source of institute access.
class InstituteMembership {
  const InstituteMembership({
    required this.uid,
    required this.instituteId,
    required this.role,
    required this.status,
    required this.requestedAt,
    this.approvedAt,
    this.approvedBy,
    this.reviewedAt,
    this.reviewedBy,
  });

  final String uid;
  final String instituteId;
  final UserRole role;
  final InstituteMembershipStatus status;
  final DateTime requestedAt;
  final DateTime? approvedAt;
  final String? approvedBy;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  String get documentId => '${uid}_$instituteId';
  bool get isActive => status == InstituteMembershipStatus.active;
  bool get requiresApproval => status == InstituteMembershipStatus.pending;

  /// Super Admin is global; it must never be granted by an institute join.
  bool get isValidInstituteRole => role != UserRole.superAdmin;

  /// Institute administrators retain the teacher capability set for the same
  /// approved institute. This is a capability implication, not a second role
  /// document or a client-side role escalation.
  bool get canUseTeacherCapabilities =>
      isActive && (role == UserRole.teacher || role == UserRole.instituteAdmin);
}

/// The approved institute context selected for the current app session.
///
/// This is intentionally in-memory only: selecting another institute must not
/// persist a raw identifier through logout or grant access by itself. Callers
/// may use a legacy assignment only during the documented migration window.
class ActiveInstituteSession {
  const ActiveInstituteSession._({
    required this.membership,
    required this.usesLegacyCompatibility,
  });

  factory ActiveInstituteSession.fromMembership(
    InstituteMembership membership,
  ) {
    if (!membership.isActive || !membership.isValidInstituteRole) {
      throw ArgumentError.value(membership, 'membership', 'Must be active.');
    }
    return ActiveInstituteSession._(
      membership: membership,
      usesLegacyCompatibility: false,
    );
  }

  /// A transitional adapter only. New institute authorization must use an
  /// approved membership; this prevents breaking existing migrated accounts
  /// before the trusted membership backfill is deployed.
  factory ActiveInstituteSession.legacy({
    required String uid,
    required String instituteId,
    required UserRole role,
  }) => ActiveInstituteSession._(
    membership: InstituteMembership(
      uid: uid,
      instituteId: instituteId,
      role: role,
      status: InstituteMembershipStatus.active,
      requestedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
    usesLegacyCompatibility: true,
  );

  final InstituteMembership membership;
  final bool usesLegacyCompatibility;

  String get instituteId => membership.instituteId;
  UserRole get role => membership.role;
  bool get canUseTeacherCapabilities => membership.canUseTeacherCapabilities;
}

/// Creates an in-memory session view. Institute-scoped code receives its role
/// and institute only from an approved active membership.
extension ActiveMembershipProfile on UserProfile {
  UserProfile forActiveMembership(ActiveInstituteSession membership) =>
      UserProfile(
        uid: uid,
        email: email,
        displayName: displayName,
        role: membership.role,
        instituteId: membership.instituteId,
        active: active,
        mustChangePassword: mustChangePassword,
        createdAt: createdAt,
        createdBy: createdBy,
        updatedAt: updatedAt,
        lastLoginAt: lastLoginAt,
        updatedBy: updatedBy,
        phoneNumber: phoneNumber,
        employeeNumber: employeeNumber,
        permissions: permissions,
        teacherStatus: teacherStatus,
      );
}

/// Pure selection rules shared by both apps and their Firebase-less tests.
abstract final class ActiveInstituteSelection {
  static List<InstituteMembership> activeForUser(
    Iterable<InstituteMembership> memberships,
    String uid,
  ) {
    final values =
        memberships
            .where((value) => value.uid == uid && value.isActive)
            .toList(growable: false)
          ..sort((a, b) {
            final institute = a.instituteId.compareTo(b.instituteId);
            return institute != 0
                ? institute
                : a.role.name.compareTo(b.role.name);
          });
    return values;
  }

  static ActiveInstituteSession? select({
    required Iterable<InstituteMembership> memberships,
    required String uid,
    String? preferredInstituteId,
  }) {
    final active = activeForUser(memberships, uid);
    if (active.isEmpty) return null;
    final selected = preferredInstituteId == null
        ? active.first
        : active
              .where((value) => value.instituteId == preferredInstituteId)
              .firstOrNull;
    return ActiveInstituteSession.fromMembership(selected ?? active.first);
  }
}

/// A request created after a signed-in person enters a visible institute code.
/// The requested role is not trusted until a permitted reviewer approves it.
class InstituteJoinRequest {
  const InstituteJoinRequest({
    required this.requestId,
    required this.uid,
    required this.instituteId,
    required this.requestedRole,
    required this.status,
    required this.requestedAt,
    this.reviewedAt,
    this.reviewedBy,
  });

  final String requestId;
  final String uid;
  final String instituteId;
  final UserRole requestedRole;
  final InstituteMembershipStatus status;
  final DateTime requestedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  bool get isPending => status == InstituteMembershipStatus.pending;
  bool get canCreateInstituteMembership =>
      status == InstituteMembershipStatus.active &&
      requestedRole != UserRole.superAdmin;
}

/// Small policy object used by future trusted membership callables.
class InstituteMembershipPolicy {
  const InstituteMembershipPolicy._();

  static bool mayRequest(UserRole role) => role != UserRole.superAdmin;

  static bool mayApprove({
    required UserRole reviewerRole,
    required UserRole requestedRole,
    required bool sameInstitute,
  }) {
    if (reviewerRole == UserRole.superAdmin) {
      return requestedRole == UserRole.instituteAdmin ||
          requestedRole == UserRole.teacher ||
          requestedRole == UserRole.parent;
    }
    if (!sameInstitute || reviewerRole != UserRole.instituteAdmin) return false;
    return requestedRole == UserRole.teacher ||
        requestedRole == UserRole.parent;
  }
}
