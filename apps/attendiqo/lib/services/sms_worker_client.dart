import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Non-secret Worker client. The endpoint is a public routing value supplied
/// with --dart-define=SMS_WORKER_URL; credentials stay in the Worker.
class SmsWorkerClient {
  SmsWorkerClient({FirebaseAuth? auth, http.Client? client, String? endpoint})
    : _auth = auth ?? FirebaseAuth.instance,
      _client = client ?? http.Client(),
      _endpoint = endpoint ?? const String.fromEnvironment('SMS_WORKER_URL');

  final FirebaseAuth _auth;
  final http.Client _client;
  final String _endpoint;

  Future<SmsWorkerResponse> updateSettings({
    required String? instituteIdForSuperAdmin,
    required bool enabled,
    required int monthlyLimit,
    required List<String> allowedEvents,
    Map<String, String> templates = const {},
  }) {
    final payload = <String, Object>{
      'enabled': enabled,
      'monthlyLimit': monthlyLimit,
      'allowedEvents': allowedEvents,
      'templates': templates,
    };
    final instituteId = instituteIdForSuperAdmin;
    if (instituteId != null) payload['instituteId'] = instituteId;
    return _post('/v1/settings', payload);
  }

  Future<SmsWorkerResponse> usage({String? instituteIdForSuperAdmin}) {
    final payload = <String, Object>{};
    final instituteId = instituteIdForSuperAdmin;
    if (instituteId != null) payload['instituteId'] = instituteId;
    return _post('/v1/usage', payload);
  }

  /// The caller may submit a source event key but never a phone number,
  /// message body, role, or Institute Admin institute ID.
  Future<SmsWorkerResponse> requestManualEvent({
    required String studentId,
    required String eventType,
    required String sourceEventKey,
  }) => _post('/v1/send', {
    'studentId': studentId,
    'eventType': eventType,
    'sourceEventKey': sourceEventKey,
  });

  Future<SmsWorkerResponse> _post(
    String path,
    Map<String, Object> payload,
  ) async {
    if (_endpoint.isEmpty) {
      return const SmsWorkerResponse.unavailable();
    }
    final user = _auth.currentUser;
    if (user == null) {
      return const SmsWorkerResponse.error('Sign in to use SMS.');
    }
    // SMS is a privileged Worker boundary. Refresh the Firebase ID token so
    // recently-issued role claims (especially the Super Admin claim) are not
    // accidentally evaluated from an older cached session.
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      return const SmsWorkerResponse.error(
        'Your session could not be verified.',
      );
    }
    try {
      final response = await _client.post(
        Uri.parse('$_endpoint$path'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      final value = jsonDecode(response.body);
      if (value is! Map<String, dynamic>) {
        return const SmsWorkerResponse.error('SMS is temporarily unavailable.');
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return SmsWorkerResponse.success(value);
      }
      return SmsWorkerResponse.error(
        value['message'] is String
            ? value['message'] as String
            : 'SMS is temporarily unavailable.',
      );
    } catch (_) {
      return const SmsWorkerResponse.error('SMS is temporarily unavailable.');
    }
  }
}

class SmsWorkerResponse {
  const SmsWorkerResponse._(this.data, this.message, this.isUnavailable);
  const SmsWorkerResponse.success(Map<String, dynamic> data)
    : this._(data, null, false);
  const SmsWorkerResponse.error(String message) : this._(null, message, false);
  const SmsWorkerResponse.unavailable()
    : this._(null, 'SMS is not configured for this build.', true);

  final Map<String, dynamic>? data;
  final String? message;
  final bool isUnavailable;
  bool get isSuccess => data != null;
}
