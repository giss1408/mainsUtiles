import 'package:flutter/material.dart';

import '../app/spacing.dart';
import 'brand.dart';

/// One task per screen: a title, content, and actions that stay reachable.
/// Scrolls when the content is taller than the screen (small phones, large text).
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.title,
    required this.children,
    this.banner,
    this.icon,
  });

  final String title;
  final List<Widget> children;
  final Widget? banner;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Gaps.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (banner != null) ...[banner!, const SizedBox(height: Gaps.lg)],
              const SizedBox(height: Gaps.sm),
              const Align(alignment: Alignment.centerLeft, child: BrandMark(size: 44)),
              const SizedBox(height: Gaps.xl),
              if (icon != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(icon, size: Gaps.xxxl, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: Gaps.lg),
              ],
              Text(title, style: theme.textTheme.headlineMedium),
              const SizedBox(height: Gaps.lg),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
