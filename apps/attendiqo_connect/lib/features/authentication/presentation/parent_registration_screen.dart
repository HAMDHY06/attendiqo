import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

import '../../../services/firebase_authentication_repository.dart';

class ParentRegistrationScreen extends StatefulWidget {
  const ParentRegistrationScreen({super.key, required this.repository});

  final ParentAccountWorkflowRepository repository;

  @override
  State<ParentRegistrationScreen> createState() =>
      _ParentRegistrationScreenState();
}

class _ParentRegistrationScreenState extends State<ParentRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.repository.registerParent(
        displayName: _name.text,
        mobileNumber: _mobile.text,
        email: _email.text,
        password: _password.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = failure.userMessage);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to create the account. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create parent account')),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Use the same mobile number recorded by your institute. After signing in, join the institute and link your child.',
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('registrationName'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (value) =>
                  FieldValidators.required(value, label: 'Full name'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('registrationMobile'),
              controller: _mobile,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile number'),
              validator: MobileNumberValidator.validateRequired,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('registrationEmail'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: FieldValidators.email,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('registrationPassword'),
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
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
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('registrationConfirmation'),
              controller: _confirmation,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              validator: (value) => value == _password.text
                  ? null
                  : 'Passwords do not match',
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                key: const Key('registrationError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              key: const Key('createParentAccountButton'),
              onPressed: _loading ? null : _submit,
              child: Text(_loading ? 'Creating account...' : 'Create account'),
            ),
          ],
        ),
      ),
    ),
  );
}
