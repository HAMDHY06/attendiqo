import 'dart:math';

import 'enums.dart';
import 'institute.dart';
import 'models.dart';
import 'validation.dart';

abstract final class TeacherAuthorization {
  static bool canView(
    UserProfile actor,
    UserProfile teacher, {
    bool verifiedSuperAdmin = false,
  }) {
    if (teacher.role != UserRole.teacher) return false;
    return (actor.role == UserRole.superAdmin && verifiedSuperAdmin) ||
        (actor.role == UserRole.instituteAdmin &&
            actor.active &&
            actor.instituteId == teacher.instituteId);
  }

  static bool canManage(
    UserProfile actor,
    UserProfile teacher, {
    bool verifiedSuperAdmin = false,
  }) => canView(actor, teacher, verifiedSuperAdmin: verifiedSuperAdmin);

  static bool hasPermission(
    UserProfile teacher,
    TeacherPermission permission,
  ) =>
      teacher.role == UserRole.teacher &&
      teacher.effectiveTeacherPermissions.allows(permission);
}

class TeacherCreationRequest {
  const TeacherCreationRequest({
    required this.actor,
    required this.instituteId,
    required this.email,
    required this.displayName,
    required this.permissions,
    this.phoneNumber,
    this.employeeNumber,
  });

  final UserProfile actor;
  final String instituteId;
  final String email;
  final String displayName;
  final String? phoneNumber;
  final String? employeeNumber;
  final TeacherPermissions permissions;

  String get normalizedEmail => email.trim().toLowerCase();
  String? get normalizedEmployeeNumber =>
      employeeNumber == null || employeeNumber!.trim().isEmpty
      ? null
      : EmployeeNumberValidator.normalize(employeeNumber!);

  String? validate() {
    final nameError = FieldValidators.required(
      displayName,
      label: 'Display name',
    );
    if (nameError != null) return nameError;
    final emailError = FieldValidators.email(email);
    if (emailError != null) return emailError;
    final phoneError = MobileNumberValidator.validateSecondary(phoneNumber);
    if (phoneError != null) return phoneError;
    return EmployeeNumberValidator.validateOptional(employeeNumber);
  }
}

class TeacherCreationResult {
  const TeacherCreationResult({
    required this.profile,
    required this.oneTimeTemporaryPassword,
  });

  final UserProfile profile;
  final String oneTimeTemporaryPassword;
}

abstract interface class TeacherProvisioningService {
  Future<TeacherCreationResult> createTeacher(TeacherCreationRequest request);
}

class UnavailableTeacherProvisioningService
    implements TeacherProvisioningService {
  const UnavailableTeacherProvisioningService();

  @override
  Future<TeacherCreationResult> createTeacher(
    TeacherCreationRequest request,
  ) async => throw const Failure(
    'Teacher provisioning backend is not deployed. Contact HamdhyTech support.',
    code: 'backend-unavailable',
  );
}

class MockTeacherProvisioningService implements TeacherProvisioningService {
  MockTeacherProvisioningService({
    Random? random,
    Set<String>? existingEmails,
    Set<String>? existingEmployeeNumbers,
    this.forcedFailureCode,
  }) : _random = random ?? Random.secure(),
       existingEmails = existingEmails ?? <String>{},
       existingEmployeeNumbers = existingEmployeeNumbers ?? <String>{};

  final Random _random;
  final Set<String> existingEmails;
  final Set<String> existingEmployeeNumbers;
  final String? forcedFailureCode;
  final List<TeacherCreationRequest> requests = [];

  @override
  Future<TeacherCreationResult> createTeacher(
    TeacherCreationRequest request,
  ) async {
    requests.add(request);
    final validation = request.validate();
    if (validation != null) {
      throw Failure(validation, code: 'invalid-input');
    }
    if (!request.actor.active ||
        (request.actor.role != UserRole.superAdmin &&
            (request.actor.role != UserRole.instituteAdmin ||
                request.actor.instituteId != request.instituteId))) {
      throw const Failure(
        'You are not allowed to create a teacher for this institute.',
        code: 'unauthorized',
      );
    }
    if (forcedFailureCode != null) {
      throw Failure(_messageFor(forcedFailureCode!), code: forcedFailureCode);
    }
    if (existingEmails.contains(request.normalizedEmail)) {
      throw const Failure(
        'An account already uses this email address.',
        code: 'duplicate-email',
      );
    }
    final employeeNumber = request.normalizedEmployeeNumber;
    final employeeKey = employeeNumber == null
        ? null
        : '${request.instituteId}_$employeeNumber';
    if (employeeKey != null && existingEmployeeNumbers.contains(employeeKey)) {
      throw const Failure(
        'That employee number is already used in this institute.',
        code: 'duplicate-employee-number',
      );
    }
    existingEmails.add(request.normalizedEmail);
    if (employeeKey != null) existingEmployeeNumbers.add(employeeKey);
    final now = DateTime.now().toUtc();
    return TeacherCreationResult(
      profile: UserProfile.newTeacher(
        uid: 'mock-teacher-${now.microsecondsSinceEpoch}',
        email: request.normalizedEmail,
        displayName: request.displayName,
        instituteId: request.instituteId,
        createdBy: request.actor.uid,
        now: now,
        phoneNumber: request.phoneNumber,
        employeeNumber: employeeNumber,
        permissions: request.permissions,
      ),
      oneTimeTemporaryPassword: _temporaryPassword(),
    );
  }

  String _temporaryPassword() {
    const uppercase = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lowercase = 'abcdefghijkmnopqrstuvwxyz';
    const digits = '23456789';
    const specials = '!@#%';
    const all = '$uppercase$lowercase$digits$specials';
    final values = <String>[
      uppercase[_random.nextInt(uppercase.length)],
      lowercase[_random.nextInt(lowercase.length)],
      digits[_random.nextInt(digits.length)],
      specials[_random.nextInt(specials.length)],
      ...List.generate(12, (_) => all[_random.nextInt(all.length)]),
    ]..shuffle(_random);
    return values.join();
  }

  String _messageFor(String code) => switch (code) {
    'duplicate-email' => 'An account already uses this email address.',
    'duplicate-employee-number' =>
      'That employee number is already used in this institute.',
    'network' => 'Network unavailable. Check your connection and try again.',
    _ => 'Unable to create the teacher account. Please try again.',
  };
}

abstract interface class TeacherRepository implements AuditLogRepository {
  Future<List<UserProfile>> fetchTeachers({String? instituteId});
  Future<Map<String, List<String>>> fetchAssignedClassNames({
    String? instituteId,
  });
  Future<void> updateTeacher(
    UserProfile teacher, {
    required UserProfile actor,
    bool verifiedSuperAdmin = false,
  });
  Future<void> updateTeacherPermissions({
    required UserProfile actor,
    required String teacherUid,
    required String instituteId,
    required TeacherPermissions permissions,
    bool verifiedSuperAdmin = false,
  });
}
