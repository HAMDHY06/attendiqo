import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

import '../../../routing/app_router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller, this.errorMessage});
  final AuthenticationController controller;
  final String? errorMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.controller.signIn(email: _email.text, password: _password.text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF8FAFC), Color(0xFFEEF2FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.asset(
                          'assets/images/Admin_Logo.png',
                          height: 132,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.verified_user_rounded, size: 88),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Attendiqo',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Secure attendance management by HamdhyTech',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Center(
                          child: Chip(
                            avatar: Icon(Icons.lock_outline_rounded, size: 17),
                            label: Text('Email/password • Secure role routing'),
                          ),
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          key: const Key('emailField'),
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: FieldValidators.email,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('passwordField'),
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => FieldValidators.required(
                            value,
                            label: 'Password',
                          ),
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              AppRoutes.forgotPassword,
                            ),
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        if (widget.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                widget.errorMessage!,
                                key: const Key('authenticationError'),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        FilledButton(
                          key: const Key('loginButton'),
                          onPressed: _submit,
                          child: const Text('Log in'),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Need help? dev.hamdhytech@gmail.com',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
