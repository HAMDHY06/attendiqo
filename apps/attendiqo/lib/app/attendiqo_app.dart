import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

import '../features/authentication/presentation/authentication_screens.dart';
import '../features/authentication/presentation/login_screen.dart';
import '../features/foundation/presentation/foundation_screens.dart';
import '../routing/app_router.dart';
import '../services/firebase_authentication_repository.dart';
import '../theme/attendiqo_theme.dart';

class AttendiqoApp extends StatefulWidget {
  const AttendiqoApp({
    super.key,
    this.firebaseReady = false,
    this.authenticationRepository,
  });
  final bool firebaseReady;
  final AuthenticationRepository? authenticationRepository;

  @override
  State<AttendiqoApp> createState() => _AttendiqoAppState();
}

class _AttendiqoAppState extends State<AttendiqoApp> {
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
      audience: AppAudience.management,
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Attendiqo',
    debugShowCheckedModeBanner: false,
    theme: AttendiqoTheme.light(),
    onGenerateRoute: (settings) =>
        AppRouter.generate(settings, controller: _controller),
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
    AuthenticationStatus.blocked => AccessBlockedScreen(
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
    ),
  };
}
