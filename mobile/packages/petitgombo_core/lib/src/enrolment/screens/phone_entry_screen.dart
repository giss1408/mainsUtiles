import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/spacing.dart';
import '../../info/info_screens.dart';
import '../../widgets/screen_scaffold.dart';
import '../../widgets/ui_kit.dart';
import '../enrolment_copy.dart';

class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({
    super.key,
    required this.copy,
    required this.onSubmit,
    this.busy = false,
    this.banner,
  });

  final EnrolmentCopy copy;
  final ValueChanged<String> onSubmit;
  final bool busy;
  final Widget? banner;

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.busy) widget.onSubmit(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScreenScaffold(
      title: widget.copy.phoneTitle,
      banner: widget.banner,
      children: [
        TextField(
          controller: _controller,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
          style: theme.textTheme.bodyLarge,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            // Always visible, unlike prefixText which hides until the field has focus.
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: Gaps.lg, right: Gaps.sm),
              child: Text(EnrolmentCopy.phonePrefix, style: theme.textTheme.bodyLarge),
            ),
            prefixIconConstraints: const BoxConstraints(),
            hintText: EnrolmentCopy.phoneHint,
          ),
        ),
        const SizedBox(height: Gaps.sm),
        Text(widget.copy.phoneNote, style: theme.textTheme.bodyMedium),
        const SizedBox(height: Gaps.xl),
        FilledButton(
          onPressed: widget.busy ? null : _submit,
          child: widget.busy
              ? const SizedBox.square(
                  dimension: Gaps.xl,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(EnrolmentCopy.continueLabel),
        ),
        const SizedBox(height: Gaps.xl),
        const PrivacyNote(
          'Le numéro sert à la connexion et aux échanges liés aux missions. '
          'Continuer vaut acceptation de la politique de confidentialité.',
        ),
        const SizedBox(height: Gaps.md),
        const LegalFooter(),
      ],
    );
  }
}
