import 'package:flutter/material.dart';

import '../app/spacing.dart';
import '../app/theme.dart';
import 'brand.dart';

/// The product name as it appears in headers.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(),
        const SizedBox(width: Gaps.sm),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'petit', style: style),
                TextSpan(text: 'Gombo', style: style.copyWith(color: AppColors.primary)),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A white card with a hairline border; tappable when [onTap] is set.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.card);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.md),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding ?? const EdgeInsets.all(Gaps.lg), child: child),
        ),
      ),
    );
  }
}

/// A rounded square holding an icon, used at the start of cards and rows.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.size = 44});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(Radii.field),
      ),
      child: Icon(icon, color: AppColors.primary, size: size * 0.5),
    );
  }
}

/// A small fact about an offer: an icon and a few words.
class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: Gaps.lg, color: AppColors.textMuted),
        ),
        const SizedBox(width: Gaps.sm),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

/// A status shown as an icon and a word on a tinted pill, never colour alone.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.icon, required this.label, this.strong = false});

  final IconData icon;
  final String label;

  /// Green tint for a positive, current state; neutral otherwise.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = strong ? AppColors.primary : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.xs),
      decoration: BoxDecoration(
        color: strong ? AppColors.primarySoft : AppColors.background,
        borderRadius: BorderRadius.circular(Gaps.xl),
        border: Border.all(color: strong ? AppColors.primarySoft : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: Gaps.lg, color: color),
          const SizedBox(width: Gaps.xs),
          Flexible(
            child: Text(label, style: theme.textTheme.bodyMedium!.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

/// A small heading above a group of cards or rows.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Gaps.lg, bottom: Gaps.sm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// What a list shows when it has nothing: an icon, one sentence, at most one action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(Gaps.xl),
      child: Column(
        children: [
          IconTile(icon: icon, size: 64),
          const SizedBox(height: Gaps.lg),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: Gaps.sm),
            Text(
              body!,
              style: theme.textTheme.bodyMedium!.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[const SizedBox(height: Gaps.lg), action!],
        ],
      ),
    );
  }
}

/// A short reassurance at the point where personal data is asked for.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gaps.md),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, color: AppColors.primary, size: 20),
          const SizedBox(width: Gaps.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// A row that opens another screen: icon, label, optional detail, chevron.
class NavRow extends StatelessWidget {
  const NavRow({super.key, required this.icon, required this.label, this.detail, this.onTap});

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minTouchTarget + Gaps.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.md),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textMuted),
              const SizedBox(width: Gaps.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.bodyLarge),
                    if (detail != null)
                      Text(
                        detail!,
                        style: theme.textTheme.bodyMedium!.copyWith(color: AppColors.textMuted),
                      ),
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A white block grouping rows, with dividers between them.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: Gaps.lg),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// The icon that stands for a category of offer, guessed from its name.
IconData categoryIcon(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('ménage') || lower.contains('menage') || lower.contains('nettoy')) {
    return Icons.cleaning_services_outlined;
  }
  if (lower.contains('cuisine') || lower.contains('repas')) return Icons.restaurant_outlined;
  if (lower.contains('âgée') || lower.contains('agee') || lower.contains('accompagnement')) {
    return Icons.elderly_outlined;
  }
  if (lower.contains('course')) return Icons.shopping_basket_outlined;
  if (lower.contains('jardin')) return Icons.yard_outlined;
  if (lower.contains('enfant') || lower.contains('garde')) return Icons.child_care_outlined;
  if (lower.contains('linge') || lower.contains('repass')) {
    return Icons.local_laundry_service_outlined;
  }
  return Icons.handyman_outlined;
}
