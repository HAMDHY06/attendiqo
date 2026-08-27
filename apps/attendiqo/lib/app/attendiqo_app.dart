import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

import '../features/authentication/presentation/authentication_screens.dart';
import '../features/authentication/presentation/login_screen.dart';
import '../features/foundation/presentation/foundation_screens.dart';
import '../features/academic_management/presentation/academic_management_screens.dart';
import '../routing/app_router.dart';
import '../services/firebase_authentication_repository.dart';
import '../services/firebase_notification_lifecycle.dart';
import '../theme/attendiqo_theme.dart';

class AttendiqoApp extends StatefulWidget {
  const AttendiqoApp({
    super.key,
    this.firebaseReady = false,
    this.authenticationRepository,
    this.superAdminBuilder,
    this.instituteAdminBuilder,
  });
  final bool firebaseReady;
  final AuthenticationRepository? authenticationRepository;
  final Widget Function(AuthenticationController controller)? superAdminBuilder;
  final Widget Function(AuthenticationController controller)?
  instituteAdminBuilder;

  @override
  State<AttendiqoApp> createState() => _AttendiqoAppState();
}

class _AttendiqoAppState extends State<AttendiqoApp> {
  late final AuthenticationController _controller;
  final ValueNotifier<String?> _notificationDestination = ValueNotifier(null);
  NotificationLifecycleCoordinator? _notifications;
  AppNotificationLifecycle? _notificationService;

  @override
  void initState() {
    super.initState();
    final repository =
        widget.authenticationRepository ??
        (widget.firebaseReady
            ? FirebaseAuthenticationRepository()
            : const UnavailableAuthenticationRepository());
    _controller = AuthenticationController(
      repository: repository,
      audience: AppAudience.management,
    )..start();
    if (widget.firebaseReady) {
      _notificationService = FirebaseNotificationLifecycle();
      _notifications = NotificationLifecycleCoordinator(
        _controller,
        _notificationService!,
        onTap: _openNotificationDestination,
        onForeground: _openNotificationDestination,
      )..start();
    }
  }

  @override
  void dispose() {
    _notifications?.dispose();
    _notificationDestination.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Attendiqo',
    debugShowCheckedModeBanner: false,
    theme: AttendiqoTheme.light(),
    onGenerateRoute: (settings) => AppRouter.generate(
      settings,
      controller: _controller,
      notificationService: _notificationService,
    ),
    home: AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => _screenFor(_controller.state),
    ),
  );

  Widget _screenFor(AuthenticationState state) => switch (state.status) {
    AuthenticationStatus.checking ||
    AuthenticationStatus.authenticating => SplashScreen(
      message: state.status == AuthenticationStatus.authenticating
          ? 'Signing you in securely...'
          : 'Checking your secure session...',
    ),
    AuthenticationStatus.signedOut => LoginScreen(controller: _controller),
    AuthenticationStatus.failure => LoginScreen(
      controller: _controller,
      errorMessage: state.message,
    ),
    AuthenticationStatus.blocked =>
      state.profile?.active == true &&
              state.profile?.role != UserRole.parent &&
              _controller.repository is MembershipWorkflowRepository
          ? MembershipAccessScreen(controller: _controller)
          : AccessBlockedScreen(
              message: state.message ?? 'This account cannot use Attendiqo.',
              onSignOut: _controller.signOut,
            ),
    AuthenticationStatus.mustChangePassword => ChangePasswordScreen(
      controller: _controller,
      message: state.message,
    ),
    AuthenticationStatus.authenticated => AppRouter.screenForDestination(
      state.destination!,
      controller: _controller,
      superAdminBuilder: widget.superAdminBuilder,
      instituteAdminBuilder: widget.instituteAdminBuilder,
      teacherBuilder: widget.firebaseReady
          ? (controller) => AcademicManagementArea(authController: controller)
          : null,
      notificationDestination: _notificationDestination,
      activeInstituteId: state.activeMembership?.instituteId,
    ),
  };

  void _openNotificationDestination(NotificationTapRoute route) {
    // The route has already passed the current authentication/role gate. It is
    // route-only, so no document identifier can be trusted from an FCM payload.
    _notificationDestination.value = route.destination;
  }
}
