import 'dart:async';

import 'authentication.dart';
import 'enums.dart';
import 'notification_service.dart';
import 'notification_tap_coordinator.dart';
import 'notification_routing.dart';

/// Starts device work only after a trusted authenticated session exists.
class NotificationLifecycleCoordinator {
  NotificationLifecycleCoordinator(
    this.auth,
    this.service, {
    this.onTap,
    this.onForeground,
  });
  final AuthenticationController auth;
  final AppNotificationLifecycle service;
  final void Function(NotificationTapRoute route)? onTap;
  final void Function(NotificationTapRoute route)? onForeground;
  bool _started = false;
  final _tapCoordinator = NotificationTapCoordinator();
  StreamSubscription<NotificationTapRoute>? _tapSubscription;
  StreamSubscription<NotificationTapRoute>? _foregroundSubscription;

  void start() {
    auth.addListener(_sync);
    _tapSubscription ??= service.taps.listen(_handleTap);
    _foregroundSubscription ??= service.foregroundRoutes.listen(
      _handleForeground,
    );
    _sync();
  }

  void _handleTap(NotificationTapRoute route) {
    final accepted = _tapCoordinator.accept(route, auth.state, auth.audience);
    if (accepted != null) onTap?.call(accepted);
  }

  void _handleForeground(NotificationTapRoute route) {
    final accepted = _tapCoordinator.accept(route, auth.state, auth.audience);
    if (accepted != null) onForeground?.call(accepted);
  }

  Future<void> _sync() async {
    if (auth.state.status == AuthenticationStatus.authenticated) {
      if (!_started) {
        _started = true;
        try {
          await service.start();
        } catch (_) {
          // Notification setup must never break an authenticated app session.
        }
      }
    } else if (_started) {
      _started = false;
      await service.clearForSignOut();
    }
  }

  Future<void> dispose() async {
    auth.removeListener(_sync);
    await _tapSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await service.clearForSignOut();
  }
}
