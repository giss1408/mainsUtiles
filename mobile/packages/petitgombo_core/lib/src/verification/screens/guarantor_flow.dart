import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../enrolment/phone_format.dart';
import '../../app/spacing.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../capture.dart';
import '../verification_controller.dart';
import '../verification_copy.dart';
import 'flow_scaffold.dart';
import 'photo_step.dart';

/// Guarantor step: who vouches, which document, a photo of it, a summary, send.
class GuarantorFlow extends ConsumerStatefulWidget {
  const GuarantorFlow({super.key});

  @override
  ConsumerState<GuarantorFlow> createState() => _GuarantorFlowState();
}

class _GuarantorFlowState extends ConsumerState<GuarantorFlow> {
  static const _steps = 4;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _relationship;
  String? _documentType;
  CapturedPhoto? _photo;
  bool _showErrors = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;
  bool get _phoneOk => normaliseIvorianPhone(_phone.text) != null;

  void _chooseRelationship(String key) {
    if (!_nameOk || !_phoneOk) {
      setState(() => _showErrors = true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _relationship = key);
  }

  void _back() {
    setState(() {
      if (_photo != null) {
        _photo = null;
      } else if (_documentType != null) {
        _documentType = null;
      } else {
        _relationship = null;
      }
    });
    ref.read(verificationControllerProvider.notifier).clearError();
  }

  Future<void> _send() async {
    final sent = await ref.read(verificationControllerProvider.notifier).sendGuarantor(
          documentType: _documentType!,
          photo: _photo!,
          guarantorName: _name.text.trim(),
          guarantorPhone: _phone.text,
          relationship: _relationship!,
        );
    if (sent && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _relationship == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: _step(context),
    );
  }

  Widget _step(BuildContext context) {
    final theme = Theme.of(context);
    if (_relationship == null) {
      return FlowScaffold(
        title: VerificationCopy.guarantorFlowTitle,
        step: 1,
        steps: _steps,
        children: [
          TextField(
            key: const Key('guarantor-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            maxLength: 120,
            style: theme.textTheme.bodyLarge,
            onChanged: (_) {
              if (_showErrors) setState(() {});
            },
            decoration: InputDecoration(
              labelText: VerificationCopy.guarantorNameLabel,
              counterText: '',
              errorText: _showErrors && !_nameOk ? VerificationCopy.guarantorNameRequired : null,
            ),
          ),
          const SizedBox(height: Gaps.lg),
          TextField(
            key: const Key('guarantor-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            style: theme.textTheme.bodyLarge,
            onChanged: (_) {
              if (_showErrors) setState(() {});
            },
            decoration: InputDecoration(
              labelText: VerificationCopy.guarantorPhoneLabel,
              errorText: _showErrors && !_phoneOk ? VerificationCopy.guarantorPhoneInvalid : null,
            ),
          ),
          const SizedBox(height: Gaps.xl),
          Text(VerificationCopy.guarantorRelationshipHint, style: theme.textTheme.titleMedium),
          const SizedBox(height: Gaps.md),
          for (final entry in VerificationCopy.guarantorRelationships.entries)
            ChoiceCard(label: entry.value, onTap: () => _chooseRelationship(entry.key)),
          const SizedBox(height: Gaps.lg),
          const PrivacyNote(VerificationCopy.guarantorPrivacy),
        ],
      );
    }
    if (_documentType == null) {
      return FlowScaffold(
        title: VerificationCopy.chooseGuarantorDocument,
        step: 2,
        steps: _steps,
        children: [
          Text(VerificationCopy.guarantorNote, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Gaps.lg),
          for (final entry in VerificationCopy.guarantorDocumentTypes.entries)
            ChoiceCard(label: entry.value, onTap: () => setState(() => _documentType = entry.key)),
        ],
      );
    }
    final photo = _photo;
    if (photo == null) {
      return PhotoStep(
        kind: PhotoKind.guarantorBill,
        step: 3,
        steps: _steps,
        onAccepted: (taken) => setState(() => _photo = taken),
      );
    }
    final state = ref.watch(verificationControllerProvider);
    return FlowScaffold(
      title: VerificationCopy.guarantorSummaryTitle,
      step: 4,
      steps: _steps,
      banner: state.error == null ? null : MessageBanner(message: state.error!),
      children: [
        Text(_name.text.trim(), style: theme.textTheme.titleMedium),
        Text(_phone.text.trim(), style: theme.textTheme.bodyLarge),
        Text(
          VerificationCopy.guarantorRelationships[_relationship]!,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Gaps.lg),
        Text(
          VerificationCopy.guarantorDocumentTypes[_documentType]!,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Gaps.xs),
        PhotoPreview(photo: photo, height: 140, label: VerificationCopy.captureGuarantorBill),
        const SizedBox(height: Gaps.xl),
        BusyButton(
          label: state.error == null ? VerificationCopy.send : VerificationCopy.retry,
          onPressed: _send,
          busy: state.sending,
        ),
      ],
    );
  }
}
