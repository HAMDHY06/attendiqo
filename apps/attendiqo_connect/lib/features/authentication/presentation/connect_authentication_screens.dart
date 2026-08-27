import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

class ConnectForgotPasswordScreen extends StatefulWidget {
  const ConnectForgotPasswordScreen({super.key, required this.controller});
  final AuthenticationController controller;
  @override
  State<ConnectForgotPasswordScreen> createState() =>
      _ConnectForgotPasswordScreenState();
}

class _ConnectForgotPasswordScreenState
    extends State<ConnectForgotPasswordScreen> {
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
    setState(() {
      _sending = true;
      _message = null;
    });
    final sent = await widget.controller.requestPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _message = sent
          ? 'If an eligible account exists, password-reset instructions have been sent.'
          : widget.controller.state.message;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reset password')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 72),
                const SizedBox(height: 16),
                const Text(
                  'Enter your email and we will send secure reset instructions.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: FieldValidators.email,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send reset email'),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _message!,
                      key: const Key('resetMessage'),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ConnectChangePasswordScreen extends StatefulWidget {
  const ConnectChangePasswordScreen({
    super.key,
    required this.controller,
    this.message,
  });
  final AuthenticationController controller;
  final String? message;
  @override
  State<ConnectChangePasswordScreen> createState() =>
      _ConnectChangePasswordScreenState();
}

class _ConnectChangePasswordScreenState
    extends State<ConnectChangePasswordScreen> {
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Create a new password'),
      automaticallyImplyLeading: false,
      actions: [
        TextButton(
          onPressed: widget.controller.signOut,
          child: const Text('Sign out'),
        ),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.password_rounded, size: 72),
                const SizedBox(height: 16),
                const Text(
                  'Please replace your temporary password before continuing.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    helperText:
                        '10+ characters with upper, lower, number and special character',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: PasswordValidator.validateForCreation,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmation,
                  obscureText: _obscure,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                  validator: (value) =>
                      value == _password.text ? null : 'Passwords do not match',
                ),
                if (widget.message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      widget.message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      widget.controller.changePassword(_password.text);
                    }
                  },
                  child: const Text('Change password'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ConnectAccessBlockedScreen extends StatelessWidget {
  const ConnectAccessBlockedScreen({
    super.key,
    required this.message,
    required this.onSignOut,
  });
  final String message;
  final Future<void> Function() onSignOut;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.block_rounded,
                size: 72,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 20),
              Text(
                message,
                key: const Key('accessBlockedMessage'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text('Support: dev.hamdhytech@gmail.com'),
              const SizedBox(height: 24),
              FilledButton(onPressed: onSignOut, child: const Text('Sign out')),
            ],
          ),
        ),
      ),
    ),
  );
}

class ParentMembershipAccessScreen extends StatefulWidget {
  const ParentMembershipAccessScreen({super.key, required this.controller});
  final AuthenticationController controller;
  @override
  State<ParentMembershipAccessScreen> createState() =>
      _ParentMembershipAccessScreenState();
}

class _ParentMembershipAccessScreenState
    extends State<ParentMembershipAccessScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  MembershipWorkflowRepository? get _workflow =>
      widget.controller.repository is MembershipWorkflowRepository
      ? widget.controller.repository as MembershipWorkflowRepository
      : null;
  String get _statusMessage {
    final status = widget.controller.state.memberships
        .where((item) => item.status != InstituteMembershipStatus.active)
        .map((item) => item.status)
        .firstOrNull;
    return switch (status) {
      InstituteMembershipStatus.pending =>
        'Your Parent Connect request is pending approval.',
      InstituteMembershipStatus.rejected =>
        'Your Parent Connect request was not approved. You may submit a new request.',
      InstituteMembershipStatus.suspended =>
        'Your Parent Connect access is suspended. Contact the institute.',
      InstituteMembershipStatus.revoked =>
        'Your Parent Connect access was revoked. Request access again if appropriate.',
      _ =>
        'Enter your institute join code to request Parent Connect access. Approval is required.',
    };
  }

  Future<void> _request() async {
    final workflow = _workflow;
    if (workflow == null || _code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await workflow.requestMembership(
        joinCode: _code.text,
        requestedRole: UserRole.parent,
      );
      if (mounted) {
        setState(
          () => _message =
              'Your Parent Connect request is pending Institute Admin approval.',
        );
      }
    } on MembershipWorkerFailure catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Parent Connect approval')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.family_restroom_outlined, size: 64),
              const SizedBox(height: 16),
              Text(_message ?? _statusMessage, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Institute join code',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _request,
                child: Text(
                  _busy ? 'Submitting…' : 'Request Parent Connect access',
                ),
              ),
              TextButton(
                onPressed: _busy ? null : widget.controller.signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
