import 'dart:async';

import 'enums.dart';
import 'notification_routing.dart';

/// Platform adapters own FCM. This contract deliberately exposes no token.
abstract interface class AppNotificationLifecycle {
  Future<NotificationPermissionState> requestPermission();
  Future<bool> openSystemSettings();
  Stream<NotificationPermissionState> get permissionStates;
  Stream<NotificationTapRoute> get taps;

  /// A route-only foreground event. It contains no notification body or IDs.
  Stream<NotificationTapRoute> get foregroundRoutes;
  Future<void> start();
  Future<void> clearForSignOut();
}

class UnavailableNotificationService implements AppNotificationLifecycle {
  const UnavailableNotificationService();
  @override
  Future<void> clearForSignOut() async {}
  @override
  Stream<NotificationPermissionState> get permissionStates =>
      Stream.value(NotificationPermissionState.unknown);
  @override
  Future<NotificationPermissionState> requestPermission() async =>
      NotificationPermissionState.unknown;
  @override
  Future<bool> openSystemSettings() async => false;
  @override
  Future<void> start() async {}
  @override
  Stream<NotificationTapRoute> get taps => const Stream.empty();
  @override
  Stream<NotificationTapRoute> get foregroundRoutes => const Stream.empty();
}
