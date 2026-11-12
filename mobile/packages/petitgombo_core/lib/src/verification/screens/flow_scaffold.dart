import 'package:flutter/material.dart';

import '../../app/spacing.dart';

/// Content never grows wider than this on tablets.
const double flowMaxWidth = 720;

/// One step of a flow: a back arrow, a title, scrolling content.
class FlowScaffold extends StatelessWidget {
  const FlowScaffold({super.key, required this.title, required this.children, this.banner});

  final String title;
  final List<Widget> children;
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: flowMaxWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Gaps.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (banner != null) ...[banner!, const SizedBox(height: Gaps.lg)],
                  Text(title, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: Gaps.lg),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tappable row in a list of choices.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.card),
      side: BorderSide(color: Theme.of(context).dividerColor),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.sm),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minTouchTarget),
            child: Padding(
              padding: const EdgeInsets.all(Gaps.lg),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
                  const SizedBox(width: Gaps.sm),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The primary button of a step, with a spinner while [busy].
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox.square(
              dimension: Gaps.xl,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}
