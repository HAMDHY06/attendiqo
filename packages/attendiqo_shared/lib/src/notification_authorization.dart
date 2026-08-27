import 'authentication.dart';
import 'enums.dart';
import 'notification_routing.dart';

/// Notification payloads never bypass the current trusted session decision.
abstract final class NotificationAuthorization {
  static bool canOpen({required NotificationTapRoute route, required AuthenticationState state, required AppAudience audience}) {
    final profile = state.profile;
    if (state.status != AuthenticationStatus.authenticated || profile == null || !profile.active) return false;
    final decision = AuthenticationPolicy.evaluate(profile, audience);
    if (!decision.isAllowed) return false;
    if (audience == AppAudience.connect) return const {'home','children','childProfile','attendance','notices','profile'}.contains(route.destination);
    if (profile.role == UserRole.teacher && const {'institutes','monitoring','audit'}.contains(route.destination)) return false;
    return true;
  }
}
