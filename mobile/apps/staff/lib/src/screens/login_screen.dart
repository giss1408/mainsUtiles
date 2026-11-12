import 'package:flutter/material.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import '../staff_copy.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSubmit, this.busy = false, this.error});

  final void Function(String username, String password) onSubmit;
  final bool busy;
  final String? error;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _username.text.trim();
    if (widget.busy || username.isEmpty || _password.text.isEmpty) return;
    widget.onSubmit(username, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScreenScaffold(
      title: StaffCopy.loginTitle,
      icon: Icons.lock_outline,
      banner: widget.error == null ? null : MessageBanner(message: widget.error!),
      children: [
        TextField(
          controller: _username,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          style: theme.textTheme.bodyLarge,
          decoration: const InputDecoration(labelText: StaffCopy.username),
        ),
        const SizedBox(height: Gaps.lg),
        TextField(
          controller: _password,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          style: theme.textTheme.bodyLarge,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: StaffCopy.password),
        ),
        const SizedBox(height: Gaps.xl),
        FilledButton(
          onPressed: widget.busy ? null : _submit,
          child: widget.busy
              ? const SizedBox.square(
                  dimension: Gaps.xl,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(StaffCopy.signIn),
        ),
      ],
    );
  }
}
