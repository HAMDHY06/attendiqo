import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

import '../features/authentication/presentation/connect_authentication_screens.dart';
import '../features/authentication/presentation/parent_login_screen.dart';
import '../features/foundation/presentation/connect_screens.dart';
import '../features/parent/data/parent_projection_repository.dart';
import '../routing/connect_router.dart';
import '../services/firebase_authentication_repository.dart';
import '../services/firebase_notification_lifecycle.dart';
import '../theme/connect_theme.dart';

class AttendiqoConnectApp extends StatefulWidget {
  const AttendiqoConnectApp({
    super.key,
    this.firebaseReady = false,
    this.authenticationRepository,
    this.parentProjectionRepository,
  });
  final bool firebaseReady;
  final AuthenticationRepository? authenticationRepository;
  final ParentProjectionRepository? parentProjectionRepository;
  @override
  State<AttendiqoConnectApp> createState() => _AttendiqoConnectAppState();
}

class _AttendiqoConnectAppState extends State<AttendiqoConnectApp> {
  late final AuthenticationController _controller;
  late final ParentProjectionRepository _parentRepository;
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
      audience: AppAudience.connect,
    )..start();
    _parentRepository =
        widget.parentProjectionRepository ??
        (widget.firebaseReady
            ? FirestoreParentProjectionRepository()
            : const UnavailableParentProjectionRepository());
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
    title: 'Attendiqo Connect',
    debugShowCheckedModeBanner: false,
    theme: ConnectTheme.light(),
    onGenerateRoute: (settings) => ConnectRouter.generate(
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
    AuthenticationStatus.authenticating => ConnectSplashScreen(
      message: state.status == AuthenticationStatus.authenticating
          ? 'Signing you in securely...'
          : 'Checking your secure session...',
    ),
    AuthenticationStatus.signedOut => ParentLoginScreen(
      controller: _controller,
    ),
    AuthenticationStatus.failure => ParentLoginScreen(
      controller: _controller,
      errorMessage: state.message,
    ),
    AuthenticationStatus.blocked =>
      state.profile?.active == true &&
              state.profile?.role == UserRole.parent &&
              _controller.repository is MembershipWorkflowRepository
          ? ParentMembershipAccessScreen(controller: _controller)
          : ConnectAccessBlockedScreen(
              message:
                  state.message ?? 'This account cannot use Attendiqo Connect.',
              onSignOut: _controller.signOut,
            ),
    AuthenticationStatus.mustChangePassword => ConnectChangePasswordScreen(
      controller: _controller,
      message: state.message,
    ),
    AuthenticationStatus.authenticated => ConnectRouter.screenForDestination(
      state.destination!,
      controller: _controller,
      parentRepository: state.activeMembership == null
          ? _parentRepository
          : InstituteScopedParentProjectionRepository(
              delegate: _parentRepository,
              instituteId: state.activeMembership!.instituteId,
            ),
      notificationDestination: _notificationDestination,
      activeInstituteId: state.activeMembership?.instituteId,
    ),
  };

  void _openNotificationDestination(NotificationTapRoute route) {
    // Parent payloads are route-only; child IDs and links are never trusted.
    _notificationDestination.value = route.destination;
  }
}
