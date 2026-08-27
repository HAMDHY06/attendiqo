import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('notification routes require an active authorized current session', () {
    final route = NotificationTapRoute.parse({'route':'attendance'}, connect:false)!;
    expect(NotificationAuthorization.canOpen(route:route,state:const AuthenticationState(AuthenticationStatus.signedOut),audience:AppAudience.management),false);
  });
}
