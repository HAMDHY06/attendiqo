import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter_test/flutter_test.dart';
void main(){test('tap coordinator drops logged-out and duplicate events',(){final c=NotificationTapCoordinator();final r=NotificationTapRoute.parse({'route':'attendance'},connect:false)!;const state=AuthenticationState(AuthenticationStatus.signedOut);expect(c.accept(r,state,AppAudience.management),isNull);});}
