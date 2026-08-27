import 'dart:async';
import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

/// Callable-only device lifecycle. Safe failures leave Connect usable.
class FirebaseNotificationLifecycle implements AppNotificationLifecycle {
  FirebaseNotificationLifecycle({
    FirebaseMessaging? messaging,
    FirebaseFunctions? functions,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _functions = functions ?? FirebaseFunctions.instance;
  final FirebaseMessaging _messaging;
  final FirebaseFunctions _functions;
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
    final result = await _functions
        .httpsCallable('registerNotificationDevice')
        .call({
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
    _tokenId = result.data is Map ? result.data['tokenId'] as String? : null;
  }

  Future<void> _refresh(String token) async {
    if (_tokenId == null) return _register(token);
    final result = await _functions
        .httpsCallable('refreshNotificationDevice')
        .call({
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
    _tokenId = result.data is Map ? result.data['tokenId'] as String? : null;
  }

  @override
  Future<void> clearForSignOut() async {
    if (_tokenId != null) {
      try {
        await _functions.httpsCallable('deactivateNotificationDevice').call({
          'tokenId': _tokenId,
        });
      } on FirebaseFunctionsException {
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

  Future<void> dispose() async {
    await clearForSignOut();
    await _permissions.close();
    await _taps.close();
    await _foreground.close();
  }
}
