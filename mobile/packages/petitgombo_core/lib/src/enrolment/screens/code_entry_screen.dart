import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/spacing.dart';
import '../../widgets/screen_scaffold.dart';
import '../enrolment_copy.dart';

const _codeLength = 6;

class CodeEntryScreen extends StatefulWidget {
  const CodeEntryScreen({super.key, required this.onSubmit, this.errorMessage, this.banner});

  final Future<void> Function(String code) onSubmit;
  final String? errorMessage;
  final Widget? banner;

  @override
  State<CodeEntryScreen> createState() => _CodeEntryScreenState();
}

class _CodeEntryScreenState extends State<CodeEntryScreen> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _complete => _controller.text.length == _codeLength;

  Future<void> _submit() async {
    if (!_complete || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_controller.text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScreenScaffold(
      title: EnrolmentCopy.codeTitle,
      banner: widget.banner,
      children: [
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_codeLength),
          ],
          style: theme.textTheme.bodyLarge,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(hintText: '000000', errorText: widget.errorMessage),
        ),
        const SizedBox(height: Gaps.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: Gaps.xl, color: theme.colorScheme.primary),
            const SizedBox(width: Gaps.sm),
            Expanded(child: Text(EnrolmentCopy.codeNote, style: theme.textTheme.bodyMedium)),
          ],
        ),
        const SizedBox(height: Gaps.xl),
        FilledButton(
          onPressed: _complete && !_busy ? _submit : null,
          child: const Text(EnrolmentCopy.validateLabel),
        ),
      ],
    );
  }
}
