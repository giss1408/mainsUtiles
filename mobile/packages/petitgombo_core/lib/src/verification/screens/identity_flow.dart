import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../widgets/message_banner.dart';
import '../capture.dart';
import '../verification_controller.dart';
import '../verification_copy.dart';
import '../../widgets/ui_kit.dart';
import 'flow_scaffold.dart';
import 'photo_step.dart';

/// Identity step: choose the document, photograph front and back, take a selfie, send.
class IdentityFlow extends ConsumerStatefulWidget {
  const IdentityFlow({super.key});

  @override
  ConsumerState<IdentityFlow> createState() => _IdentityFlowState();
}

class _IdentityFlowState extends ConsumerState<IdentityFlow> {
  static const _kinds = [PhotoKind.idFront, PhotoKind.idBack, PhotoKind.selfie];

  String? _documentType;

  /// Photos accepted so far, in the order of [_kinds]. Kept in memory only.
  final List<CapturedPhoto> _photos = [];

  void _back() {
    setState(() {
      if (_photos.isNotEmpty) {
        _photos.removeLast();
      } else {
        _documentType = null;
      }
    });
    ref.read(verificationControllerProvider.notifier).clearError();
  }

  Future<void> _send() async {
    final sent = await ref.read(verificationControllerProvider.notifier).sendIdentity(
          documentType: _documentType!,
          front: _photos[0],
          back: _photos[1],
          selfie: _photos[2],
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
    if (_documentType == null) {
      return FlowScaffold(
        title: VerificationCopy.chooseIdentityDocument,
        children: [
          for (final entry in VerificationCopy.identityTypes.entries)
            ChoiceCard(label: entry.value, onTap: () => setState(() => _documentType = entry.key)),
          const SizedBox(height: Gaps.lg),
          const PrivacyNote(
            'Vos photos sont chiffrées et vues seulement par notre équipe de vérification. '
            'Chaque consultation est enregistrée.',
          ),
        ],
      );
    }
    if (_photos.length < _kinds.length) {
      final kind = _kinds[_photos.length];
      return PhotoStep(
        key: ValueKey(kind),
        kind: kind,
        onAccepted: (photo) => setState(() => _photos.add(photo)),
      );
    }
    final state = ref.watch(verificationControllerProvider);
    return FlowScaffold(
      title: VerificationCopy.summaryTitle,
      banner: state.error == null ? null : MessageBanner(message: state.error!),
      children: [
        for (var i = 0; i < _kinds.length; i++) ...[
          Text(
            VerificationCopy.captureTitle(_kinds[i]),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: Gaps.xs),
          PhotoPreview(
            photo: _photos[i],
            height: 140,
            label: VerificationCopy.captureTitle(_kinds[i]),
          ),
          const SizedBox(height: Gaps.lg),
        ],
        BusyButton(label: VerificationCopy.send, onPressed: _send, busy: state.sending),
      ],
    );
  }
}
