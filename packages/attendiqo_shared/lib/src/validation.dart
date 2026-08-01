abstract final class FieldValidators {
  static String? required(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  static String? email(String? value) {
    final requiredError = required(value, label: 'Email');
    if (requiredError != null) return requiredError;
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value!.trim());
    return valid ? null : 'Enter a valid email address';
  }

  static String? optionalEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return email(value);
  }
}

abstract final class InstituteCodeValidator {
  static final RegExp _pattern = RegExp(r'^[A-Z][A-Z0-9_-]{2,15}$');

  static String normalize(String value) => value.trim().toUpperCase();

  static String? validate(String? value) {
    final requiredError = FieldValidators.required(
      value,
      label: 'Institute code',
    );
    if (requiredError != null) return requiredError;
    if (value != value!.toUpperCase()) {
      return 'Institute code must be uppercase';
    }
    if (!_pattern.hasMatch(value.trim())) {
      return 'Use 3-16 uppercase letters, numbers, hyphens or underscores';
    }
    return null;
  }
}

abstract final class EmployeeNumberValidator {
  static final RegExp _pattern = RegExp(r'^[A-Z0-9][A-Z0-9_-]{1,31}$');

  static String normalize(String value) => value.trim().toUpperCase();

  static String? validateOptional(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = normalize(value);
    if (!_pattern.hasMatch(normalized)) {
      return 'Use 2-32 letters, numbers, hyphens or underscores';
    }
    return null;
  }
}

abstract final class ClassCodeValidator {
  static final RegExp _pattern = RegExp(r'^[A-Z0-9][A-Z0-9_-]{1,31}$');
  static String normalize(String value) => value.trim().toUpperCase();
  static String? validate(String? value) {
    final requiredError = FieldValidators.required(value, label: 'Class code');
    if (requiredError != null) return requiredError;
    if (!_pattern.hasMatch(normalize(value!))) {
      return 'Use 2-32 letters, numbers, hyphens or underscores';
    }
    return null;
  }
}

abstract final class StudentNumberValidator {
  static final RegExp _pattern = RegExp(r'^[A-Z0-9][A-Z0-9_-]{1,39}$');
  static String normalize(String value) => value.trim().toUpperCase();
  static String? validate(String? value) {
    final requiredError = FieldValidators.required(
      value,
      label: 'Student number',
    );
    if (requiredError != null) return requiredError;
    if (!_pattern.hasMatch(normalize(value!))) {
      return 'Use 2-40 letters, numbers, hyphens or underscores';
    }
    return null;
  }
}

abstract final class PasswordValidator {
  static String? validateForCreation(String? value) {
    final requiredError = FieldValidators.required(value, label: 'Password');
    if (requiredError != null) return requiredError;
    final password = value!;
    if (password.length < 10) return 'Use at least 10 characters';
    if (!RegExp('[A-Z]').hasMatch(password)) {
      return 'Add at least one uppercase letter';
    }
    if (!RegExp('[a-z]').hasMatch(password)) {
      return 'Add at least one lowercase letter';
    }
    if (!RegExp('[0-9]').hasMatch(password)) {
      return 'Add at least one number';
    }
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return 'Add at least one special character';
    }
    return null;
  }
}

abstract final class MobileNumberValidator {
  static String normalize(String value) {
    var normalized = value.replaceAll(RegExp(r'[\s()-]'), '');
    if (normalized.startsWith('0094')) {
      normalized = '+94${normalized.substring(4)}';
    }
    if (normalized.startsWith('0') && normalized.length == 10) {
      normalized = '+94${normalized.substring(1)}';
    }
    return normalized;
  }

  static bool isValid(String value, {bool required = true}) {
    if (value.trim().isEmpty) return !required;
    final normalized = normalize(value);
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized);
  }

  static String? validatePrimary(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Primary parent mobile number is required';
    }
    return isValid(value) ? null : 'Enter a valid mobile number';
  }

  static String? validateRequired(
    String? value, {
    String label = 'Mobile number',
  }) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return isValid(value) ? null : 'Enter a valid mobile number';
  }

  static String? validateSecondary(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return isValid(value) ? null : 'Enter a valid mobile number';
  }
}

abstract final class MessageTemplateValidator {
  static String? validate(String? value) {
    final requiredError = FieldValidators.required(
      value,
      label: 'Message template',
    );
    if (requiredError != null) return requiredError;
    if (!value!.trimLeft().startsWith('[Institute Name]')) {
      return 'Message must begin with [Institute Name]';
    }
    if (value.length > 320) return 'Message template is too long';
    return null;
  }
}
