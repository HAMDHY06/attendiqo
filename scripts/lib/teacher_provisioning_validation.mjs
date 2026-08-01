export const defaultTeacherPermissions = Object.freeze({
  canCreateClasses: false,
  canEditClasses: false,
  canAddStudents: true,
  canEditStudents: true,
  canGenerateQrCodes: true,
  canTakeAttendance: true,
  canCorrectAttendance: false,
  canExportReports: true,
  canViewParentContacts: true,
  canSendManualNotifications: false,
});

export function normalizeEmail(value) {
  return value.trim().toLowerCase();
}

export function normalizeEmployeeNumber(value) {
  const normalized = value.trim().toUpperCase();
  return normalized || null;
}

export function validateTeacherInput({ instituteId, displayName, email, employeeNumber, phoneNumber }) {
  if (!instituteId?.trim()) throw new Error('Institute ID is required.');
  if (!displayName?.trim()) throw new Error('Teacher display name is required.');
  if (displayName.trim().length > 160) throw new Error('Teacher display name is too long.');
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizeEmail(email ?? ''))) {
    throw new Error('Invalid email address.');
  }
  const employee = normalizeEmployeeNumber(employeeNumber ?? '');
  if (employee && !/^[A-Z0-9][A-Z0-9_-]{1,31}$/.test(employee)) {
    throw new Error('Invalid employee number.');
  }
  const phone = phoneNumber?.trim() || null;
  if (phone && !/^\+?[0-9][0-9 ()-]{6,22}$/.test(phone)) {
    throw new Error('Invalid phone number.');
  }
  return { employeeNumber: employee, email: normalizeEmail(email), phoneNumber: phone };
}

export function meetsPasswordPolicy(value) {
  return value.length >= 10
    && /[A-Z]/.test(value)
    && /[a-z]/.test(value)
    && /[0-9]/.test(value)
    && /[^A-Za-z0-9]/.test(value);
}
