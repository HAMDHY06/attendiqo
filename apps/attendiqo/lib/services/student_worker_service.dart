import 'dart:convert';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class StudentWorkerService {
  StudentWorkerService({
    FirebaseAuth? auth,
    http.Client? client,
    String? endpoint,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client(),
       _endpoint = (endpoint ?? AttendiqoServiceEndpoints.workerBaseUrl)
           .replaceAll(RegExp(r'/+$'), '');

  final FirebaseAuth _auth;
  final http.Client _client;
  final String _endpoint;
  String? lastCreatedQrPayload;

  Future<List<Student>> list() async {
    final result = await _post('/v1/students/teacher/list', const {});
    final values = result['students'];
    if (values is! List) {
      throw const Failure(
        'The student service returned an invalid response.',
        code: 'backend-invalid-response',
      );
    }
    return values
        .whereType<Map>()
        .map((value) => _student(Map<String, dynamic>.from(value)))
        .whereType<Student>()
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  Future<Student> create(Student value, String targetClassId) async {
    final result = await _post('/v1/students/teacher/create', {
      ..._editable(value),
      'classId': targetClassId,
    });
    lastCreatedQrPayload = result['qrPayload'] as String?;
    return _studentResult(result);
  }

  Future<Student> update(Student value) async => _studentResult(
    await _post('/v1/students/teacher/update', _editable(value)),
  );

  Map<String, Object?> _editable(Student value) => {
    'studentId': value.studentId,
    'studentNumber': value.studentNumber,
    'fullName': value.fullName,
    'preferredName': value.preferredName,
    'address': value.address,
    'primaryParentName': value.primaryParentName,
    'primaryParentMobile': value.primaryParentMobile,
    'secondaryParentName': value.secondaryParentName,
    'secondaryParentMobile': value.secondaryParentMobile,
    'parentEmail': value.parentEmail,
    'emergencyContactName': value.emergencyContactName,
    'emergencyContactMobile': value.emergencyContactMobile,
    'status': value.status.name,
    'active': value.active,
  };

  Student _studentResult(Map<String, dynamic> result) {
    final raw = result['student'];
    final student = raw is Map
        ? _student(Map<String, dynamic>.from(raw))
        : null;
    if (student == null) {
      throw const Failure(
        'The student service returned an invalid response.',
        code: 'backend-invalid-response',
      );
    }
    return student;
  }

  Student? _student(Map<String, dynamic> value) {
    for (final field in ['createdAt', 'updatedAt', 'dateOfBirth']) {
      final raw = value[field];
      if (raw is String) value[field] = DateTime.tryParse(raw)?.toUtc();
    }
    return Student.tryFromMap(Map<String, Object?>.from(value));
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> payload,
  ) async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken(true);
    if (user == null || token == null || token.isEmpty) {
      throw const Failure(
        'Sign in again to use the secure student service.',
        code: 'unauthenticated',
      );
    }
    try {
      final response = await _client.post(
        Uri.parse('$_endpoint$path'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const Failure(
          'The student service is temporarily unavailable.',
          code: 'backend-unavailable',
        );
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }
      throw Failure(
        decoded['message'] is String
            ? decoded['message'] as String
            : 'The student service is temporarily unavailable.',
        code: decoded['error'] is String
            ? (decoded['error'] as String).replaceAll('_', '-')
            : 'backend-unavailable',
      );
    } on Failure {
      rethrow;
    } on FormatException {
      throw const Failure(
        'The student service returned an invalid response.',
        code: 'backend-invalid-response',
      );
    } on http.ClientException {
      throw const Failure(
        'The student service is temporarily unavailable.',
        code: 'network-error',
      );
    }
  }
}
