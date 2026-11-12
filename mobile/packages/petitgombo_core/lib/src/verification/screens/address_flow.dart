import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../widgets/message_banner.dart';
import '../capture.dart';
import '../verification_controller.dart';
import '../verification_copy.dart';
import 'flow_scaffold.dart';
import 'photo_step.dart';

/// Proof of address step: choose the document, photograph it, say where the home is, send.
class AddressFlow extends ConsumerStatefulWidget {
  const AddressFlow({super.key});

  @override
  ConsumerState<AddressFlow> createState() => _AddressFlowState();
}

class _AddressFlowState extends ConsumerState<AddressFlow> {
  final _quartier = TextEditingController();
  String? _documentType;
  CapturedPhoto? _photo;
  String? _commune;
  bool _showErrors = false;

  @override
  void dispose() {
    _quartier.dispose();
    super.dispose();
  }

  void _back() {
    setState(() {
      if (_photo != null) {
        _photo = null;
      } else {
        _documentType = null;
      }
      _showErrors = false;
    });
    ref.read(verificationControllerProvider.notifier).clearError();
  }

  Future<void> _send() async {
    final quartier = _quartier.text.trim();
    if (_commune == null || quartier.isEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    final sent = await ref.read(verificationControllerProvider.notifier).sendAddress(
          documentType: _documentType!,
          photo: _photo!,
          commune: _commune!,
          quartier: quartier,
        );
    if (sent && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _documentType == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: _step(context),
    );
  }

  Widget _step(BuildContext context) {
    final theme = Theme.of(context);
    if (_documentType == null) {
      return FlowScaffold(
        title: VerificationCopy.chooseAddressDocument,
        children: [
          Text(VerificationCopy.addressNote, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Gaps.lg),
          for (final entry in VerificationCopy.addressTypes.entries)
            ChoiceCard(label: entry.value, onTap: () => setState(() => _documentType = entry.key)),
        ],
      );
    }
    if (_photo == null) {
      return PhotoStep(
        kind: PhotoKind.addressProof,
        onAccepted: (photo) => setState(() => _photo = photo),
      );
    }
    final state = ref.watch(verificationControllerProvider);
    final communes = state.checklist?.communes ?? const <String>[];
    return FlowScaffold(
      title: VerificationCopy.addressFormTitle,
      banner: state.error == null ? null : MessageBanner(message: state.error!),
      children: [
        DropdownButtonFormField<String>(
          value: _commune,
          isExpanded: true,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            labelText: VerificationCopy.commune,
            errorText: _showErrors && _commune == null ? VerificationCopy.communeRequired : null,
          ),
          items: [
            for (final commune in communes) DropdownMenuItem(value: commune, child: Text(commune)),
          ],
          onChanged: (value) => setState(() => _commune = value),
        ),
        const SizedBox(height: Gaps.lg),
        TextField(
          controller: _quartier,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          maxLength: 80,
          style: theme.textTheme.bodyLarge,
          onChanged: (_) {
            if (_showErrors) setState(() {});
          },
          onSubmitted: (_) => _send(),
          decoration: InputDecoration(
            labelText: VerificationCopy.quartier,
            counterText: '',
            errorText: _showErrors && _quartier.text.trim().isEmpty
                ? VerificationCopy.quartierRequired
                : null,
          ),
        ),
        const SizedBox(height: Gaps.xl),
        BusyButton(label: VerificationCopy.send, onPressed: _send, busy: state.sending),
      ],
    );
  }
}
