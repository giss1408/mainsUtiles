import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../widgets/message_banner.dart';
import '../capture.dart';
import '../verification_copy.dart';
import 'flow_scaffold.dart';

/// Takes one photo with the in-app camera and lets the user check it before going on.
class PhotoStep extends ConsumerStatefulWidget {
  const PhotoStep({super.key, required this.kind, required this.onAccepted});

  final PhotoKind kind;
  final ValueChanged<CapturedPhoto> onAccepted;

  @override
  ConsumerState<PhotoStep> createState() => _PhotoStepState();
}

class _PhotoStepState extends ConsumerState<PhotoStep> {
  CapturedPhoto? _photo;
  CaptureFailure? _failure;
  bool _busy = false;

  Future<void> _take() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final photo = await ref.read(photoCaptureProvider).take(context, kind: widget.kind);
      if (!mounted) return;
      setState(() => _photo = photo ?? _photo);
    } on CaptureException catch (e) {
      if (mounted) setState(() => _failure = e.failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photo = _photo;
    final failure = _failure;
    final denied = failure == CaptureFailure.permissionDenied ||
        failure == CaptureFailure.permissionDeniedForever;
    return FlowScaffold(
      title: VerificationCopy.captureTitle(widget.kind),
      banner: failure == null
          ? null
          : MessageBanner(
              message: VerificationCopy.cameraFailure(failure),
              actionLabel: denied ? VerificationCopy.openSettings : null,
              onAction: denied ? () => ref.read(photoCaptureProvider).openSettings() : null,
            ),
      children: [
        if (photo == null) ...[
          Text(
            widget.kind == PhotoKind.selfie
                ? VerificationCopy.selfieHint
                : VerificationCopy.photoHint,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: Gaps.xl),
          BusyButton(label: VerificationCopy.takePhoto, onPressed: _take, busy: _busy),
        ] else ...[
          PhotoPreview(photo: photo, height: 280),
          const SizedBox(height: Gaps.xl),
          FilledButton(
            onPressed: _busy ? null : () => widget.onAccepted(photo),
            child: const Text(VerificationCopy.usePhoto),
          ),
          const SizedBox(height: Gaps.md),
          OutlinedButton(
            onPressed: _busy ? null : _take,
            child: const Text(VerificationCopy.retake),
          ),
        ],
      ],
    );
  }
}

/// Shows a captured photo from memory.
class PhotoPreview extends StatelessWidget {
  const PhotoPreview({super.key, required this.photo, required this.height, this.label});

  final CapturedPhoto photo;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.border.withOpacity(0.4),
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Image.memory(
          photo.bytes,
          fit: BoxFit.contain,
          semanticLabel: label,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.image_not_supported_outlined)),
        ),
      ),
    );
  }
}
