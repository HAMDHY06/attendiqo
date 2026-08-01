import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.controller});
  final AuthenticationController controller;
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  String? _message;
  bool _sending = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _sending = true; _message = null; });
    final sent = await widget.controller.requestPasswordReset(_email.text);
    if (!mounted) return;
    setState(() { _sending = false; _message = sent ? 'If an eligible account exists, password-reset instructions have been sent.' : widget.controller.state.message; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reset password')),
        body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.mark_email_read_outlined, size: 72),
            const SizedBox(height: 16),
            const Text('Enter your account email. Firebase will send a secure reset link.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email'), validator: FieldValidators.email),
            const SizedBox(height: 16),
            FilledButton(onPressed: _sending ? null : _send, child: _sending ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send reset email')),
            if (_message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!, key: const Key('resetMessage'), textAlign: TextAlign.center)),
          ])),
        ))),
      );
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.controller, this.message});
  final AuthenticationController controller;
  final String? message;
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) widget.controller.changePassword(_password.text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create a new password'), automaticallyImplyLeading: false, actions: [TextButton(onPressed: widget.controller.signOut, child: const Text('Sign out'))]),
        body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.password_rounded, size: 72),
            const SizedBox(height: 16),
            Text('Your temporary password must be replaced before continuing.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            TextFormField(key: const Key('newPasswordField'), controller: _password, obscureText: _obscure, decoration: InputDecoration(labelText: 'New password', helperText: '10+ characters with upper, lower, number and special character', suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined))), validator: PasswordValidator.validateForCreation),
            const SizedBox(height: 16),
            TextFormField(controller: _confirmation, obscureText: _obscure, decoration: const InputDecoration(labelText: 'Confirm new password'), validator: (value) => value == _password.text ? null : 'Passwords do not match'),
            if (widget.message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(widget.message!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 20),
            FilledButton(onPressed: _submit, child: const Text('Change password')),
          ])),
        ))),
      );
}

class AccessBlockedScreen extends StatelessWidget {
  const AccessBlockedScreen({super.key, required this.message, required this.onSignOut});
  final String message;
  final Future<void> Function() onSignOut;
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(32), child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.block_rounded, size: 72, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 20),
          Text(message, key: const Key('accessBlockedMessage'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text('Support: dev.hamdhytech@gmail.com', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(onPressed: onSignOut, child: const Text('Sign out')),
        ]),
      )))));
}
