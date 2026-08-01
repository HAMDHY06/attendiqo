import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

import '../features/authentication/presentation/connect_authentication_screens.dart';
import '../features/authentication/presentation/parent_login_screen.dart';
import '../features/foundation/presentation/connect_screens.dart';
import '../routing/connect_router.dart';
import '../services/firebase_authentication_repository.dart';
import '../theme/connect_theme.dart';

class AttendiqoConnectApp extends StatefulWidget {
  const AttendiqoConnectApp({
    super.key,
    this.firebaseReady = false,
    this.authenticationRepository,
  });
  final bool firebaseReady;
  final AuthenticationRepository? authenticationRepository;
  @override
  State<AttendiqoConnectApp> createState() => _AttendiqoConnectAppState();
}

class _AttendiqoConnectAppState extends State<AttendiqoConnectApp> {
  late final AuthenticationController _controller;

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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Attendiqo Connect',
    debugShowCheckedModeBanner: false,
    theme: ConnectTheme.light(),
    onGenerateRoute: (settings) =>
        ConnectRouter.generate(settings, controller: _controller),
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
    AuthenticationStatus.blocked => ConnectAccessBlockedScreen(
      message: state.message ?? 'This account cannot use Attendiqo Connect.',
      onSignOut: _controller.signOut,
    ),
    AuthenticationStatus.mustChangePassword => ConnectChangePasswordScreen(
      controller: _controller,
      message: state.message,
    ),
    AuthenticationStatus.authenticated => ConnectRouter.screenForDestination(
      state.destination!,
      controller: _controller,
    ),
  };
}
