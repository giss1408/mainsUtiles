import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../application_copy.dart';
import '../job_target.dart';
import '../review_models.dart';

const reviewCommentMax = 300;

/// Five stars and a short comment about the other side of a completed job.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.target});

  final JobTarget target;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _comment = TextEditingController();
  int _stars = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => widget.target.clearError(ref));
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final navigator = Navigator.of(context);
    final sent = await widget.target.submitReview(ref, _stars, _comment.text.trim());
    if (sent && mounted) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = widget.target.error(ref);
    return FlowScaffold(
      title: widget.target.householder
          ? ApplicationCopy.reviewTitle
          : ApplicationCopy.reviewTitleJobber,
      banner: error == null ? null : MessageBanner(message: error),
      children: [
        Text(ApplicationCopy.reviewStarsLabel, style: theme.textTheme.bodySmall),
        const SizedBox(height: Gaps.xs),
        Wrap(
          children: [
            for (var value = 1; value <= 5; value++)
              IconButton(
                key: Key('star-$value'),
                tooltip: ApplicationCopy.starsLabel(value),
                isSelected: value <= _stars,
                onPressed: () => setState(() => _stars = value),
                icon: const Icon(Icons.star_border),
                selectedIcon: const Icon(Icons.star, color: AppColors.spark),
              ),
          ],
        ),
        if (_stars > 0) Text(ApplicationCopy.starsLabel(_stars), style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gaps.md),
        TextField(
          key: const Key('review-comment'),
          controller: _comment,
          maxLength: reviewCommentMax,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: ApplicationCopy.reviewCommentLabel,
            helperText: ApplicationCopy.reviewCommentHint,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: Gaps.md),
        const PrivacyNote(ApplicationCopy.reviewWhen),
        const SizedBox(height: Gaps.lg),
        BusyButton(
          label: ApplicationCopy.reviewSend,
          onPressed: _stars == 0 ? null : _send,
          busy: widget.target.sending(ref),
        ),
      ],
    );
  }
}

/// The review card of a completed job: the invitation, then "Avis envoyé", then both reviews
/// once they are published.
class ReviewSection extends ConsumerWidget {
  const ReviewSection({super.key, required this.target, required this.reviewable});

  final JobTarget target;

  /// The server still accepts a review from this side.
  final bool reviewable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final review = target.review(ref);
    final mine = review?.mine;
    final theirs = review?.theirs;
    if (mine == null && theirs == null && !reviewable) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mine == null && reviewable) ...[
            Text(
              target.householder ? ApplicationCopy.reviewAsk : ApplicationCopy.reviewAskJobber,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Gaps.xs),
            Text(ApplicationCopy.reviewWhen, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Gaps.md),
            FilledButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => ReviewScreen(target: target)),
              ),
              child: Text(
                target.householder ? ApplicationCopy.reviewAsk : ApplicationCopy.reviewAskJobber,
              ),
            ),
          ],
          if (mine != null) ...[
            Text(ApplicationCopy.reviewSent, style: theme.textTheme.titleMedium),
            const SizedBox(height: Gaps.xs),
            _Review(item: mine),
            if (theirs == null) ...[
              const SizedBox(height: Gaps.sm),
              Text(ApplicationCopy.reviewWhen, style: theme.textTheme.bodySmall),
            ],
          ],
          if (theirs != null) ...[
            if (mine != null) const Divider(height: Gaps.xl),
            Text(
              target.householder
                  ? ApplicationCopy.reviewOfJobber
                  : ApplicationCopy.reviewOfHousehold,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Gaps.xs),
            _Review(item: theirs),
          ],
        ],
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.item});

  final ReviewItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: ApplicationCopy.starsLabel(item.stars),
          excludeSemantics: true,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Gaps.sm,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var value = 1; value <= 5; value++)
                    Icon(
                      value <= item.stars ? Icons.star : Icons.star_border,
                      size: 18,
                      color: value <= item.stars ? AppColors.spark : AppColors.textMuted,
                    ),
                ],
              ),
              Text(ApplicationCopy.starsLabel(item.stars), style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        if (item.comment.isNotEmpty) ...[
          const SizedBox(height: Gaps.xs),
          Text(item.comment, style: theme.textTheme.bodyLarge),
        ],
      ],
    );
  }
}
