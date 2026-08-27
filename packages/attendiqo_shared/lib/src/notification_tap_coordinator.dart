import 'authentication.dart';
import 'enums.dart';
import 'notification_authorization.dart';
import 'notification_routing.dart';

/// Drops duplicate, malformed and unauthorized notification navigation events.
class NotificationTapCoordinator {
  String? _last;
  NotificationTapRoute? accept(
    NotificationTapRoute route,
    AuthenticationState state,
    AppAudience audience,
  ) {
    if (!NotificationAuthorization.canOpen(
      route: route,
      state: state,
      audience: audience,
    )) {
      return null;
    }
    // One route-only destination is enough to deduplicate a replayed FCM tap.
    // Payloads with identifiers are rejected by NotificationTapRoute before here.
    if (_last == route.destination) {
      return null;
    }
    _last = route.destination;
    return route;
  }

  void clear() => _last = null;
}
