import 'package:flutter/material.dart';

import '../staff_copy.dart';

/// Asks for the reason of a refusal or a hold. Returns null when cancelled.
Future<String?> showReasonDialog(BuildContext context, {required String title}) =>
    showDialog<String>(context: context, builder: (_) => _ReasonDialog(title: title));

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title});

  final String title;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _controller.text.trim();
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        maxLength: 500,
        textCapitalization: TextCapitalization.sentences,
        style: Theme.of(context).textTheme.bodyLarge,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: StaffCopy.reasonLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(StaffCopy.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: reason.isEmpty ? null : () => Navigator.of(context).pop(reason),
          child: const Text(StaffCopy.confirm),
        ),
      ],
    );
  }
}
