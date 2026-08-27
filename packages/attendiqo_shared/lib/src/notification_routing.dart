/// Firebase-free, user-safe parsing of notification tap payloads.
/// Callers must still re-check current authentication and authorization.
class NotificationTapRoute {
  const NotificationTapRoute._(this.destination);
  final String destination;

  static NotificationTapRoute? parse(Map<String, Object?> payload, {required bool connect}) {
    if (payload.length != 1 || payload['route'] is! String) return null;
    final route = payload['route'] as String;
    final allowed = connect
        ? const {'home', 'children', 'childProfile', 'attendance', 'notices', 'profile'}
        : const {'home', 'myClasses', 'attendance', 'notices', 'profile', 'institutes', 'monitoring', 'audit'};
    return allowed.contains(route) ? NotificationTapRoute._(route) : null;
  }
}
