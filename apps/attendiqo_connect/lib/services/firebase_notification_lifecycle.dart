import 'dart:async';
import 'dart:convert';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart' as permissions;

/// Callable-only device lifecycle. Safe failures leave Connect usable.
class FirebaseNotificationLifecycle implements AppNotificationLifecycle {
  FirebaseNotificationLifecycle({
    FirebaseMessaging? messaging,
    FirebaseAuth? auth,
    http.Client? client,
    String? endpoint,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client(),
       _endpoint = (endpoint ?? AttendiqoServiceEndpoints.workerBaseUrl).replaceAll(RegExp(r'/+$'), '');
  final FirebaseMessaging _messaging;
  final FirebaseAuth _auth;
  final http.Client _client;
  final String _endpoint;
  final _permissions =
      StreamController<NotificationPermissionState>.broadcast();
  final _taps = StreamController<NotificationTapRoute>.broadcast();
  final _foreground = StreamController<NotificationTapRoute>.broadcast();
  StreamSubscription<RemoteMessage>? _sub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenSub;
  String? _tokenId;
  @override
  Stream<NotificationPermissionState> get permissionStates =>
      _permissions.stream;
  @override
  Stream<NotificationTapRoute> get taps => _taps.stream;
  @override
  Stream<NotificationTapRoute> get foregroundRoutes => _foreground.stream;
  @override
  Future<NotificationPermissionState> requestPermission() async {
    final settings = await _messaging.requestPermission();
    final state =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional
        ? NotificationPermissionState.granted
        : settings.authorizationStatus == AuthorizationStatus.denied
        ? NotificationPermissionState.denied
        : NotificationPermissionState.unknown;
    _permissions.add(state);
    return state;
  }

  @override
  Future<bool> openSystemSettings() => permissions.openAppSettings();
  @override
  Future<void> start() async {
    _foregroundSub ??= FirebaseMessaging.onMessage.listen((message) {
      final route = NotificationTapRoute.parse(
        Map<String, Object?>.from(message.data),
        connect: true,
      );
      if (route != null) _foreground.add(route);
    });
    _sub ??= FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final route = NotificationTapRoute.parse(
        Map<String, Object?>.from(message.data),
        connect: true,
      );
      if (route != null) _taps.add(route);
    });
    _tokenSub ??= _messaging.onTokenRefresh.listen(_refresh);
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      final route = NotificationTapRoute.parse(
        Map<String, Object?>.from(initial.data),
        connect: true,
      );
      if (route != null) _taps.add(route);
    }
    final token = await _messaging.getToken();
    if (token != null) await _register(token);
  }

  Future<void> _register(String token) async {
    final result = await _post('/v1/notifications/register', {
          'token': token,
          'appPackage': 'com.hamdhytech.attendiqo.connect',
          'platform': 'android',
          'appVersion': '1.0.0',
          'deviceHash': notificationDeviceHash(
            token,
            'com.hamdhytech.attendiqo.connect',
          ),
          'permissionStatus': 'granted',
        });
    _tokenId = result['tokenId'] as String?;
  }

  Future<void> _refresh(String token) async {
    if (_tokenId == null) return _register(token);
    final result = await _post('/v1/notifications/refresh', {
          'oldTokenId': _tokenId,
          'token': token,
          'appPackage': 'com.hamdhytech.attendiqo.connect',
          'platform': 'android',
          'appVersion': '1.0.0',
          'deviceHash': notificationDeviceHash(
            token,
            'com.hamdhytech.attendiqo.connect',
          ),
          'permissionStatus': 'granted',
        });
    _tokenId = result['tokenId'] as String?;
  }

  @override
  Future<void> clearForSignOut() async {
    if (_tokenId != null) {
      try {
        await _post('/v1/notifications/deactivate', {
          'tokenId': _tokenId,
        });
      } catch (_) {
        /* A network failure must not block local sign-out. */
      }
    }
    await _sub?.cancel();
    await _foregroundSub?.cancel();
    await _tokenSub?.cancel();
    _sub = null;
    _foregroundSub = null;
    _tokenSub = null;
    _tokenId = null;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, Object?> data) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw StateError('Sign in to register notifications.');
    final response = await _client.post(Uri.parse('$_endpoint$path'), headers: {
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
    }, body: jsonEncode(data));
    final value = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300 || value is! Map<String, dynamic>) {
      throw StateError('Notification service unavailable.');
    }
    return value;
  }

  Future<void> dispose() async {
    await clearForSignOut();
    await _permissions.close();
    await _taps.close();
    await _foreground.close();
  }
}
