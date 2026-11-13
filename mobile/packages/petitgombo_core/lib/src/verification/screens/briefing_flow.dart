import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../briefing_controller.dart';
import '../verification_copy.dart';
import '../verification_models.dart';
import 'flow_scaffold.dart';

/// The safety briefing, one card per screen. A wrong answer shows why and allows another try.
class BriefingFlow extends ConsumerStatefulWidget {
  const BriefingFlow({super.key});

  @override
  ConsumerState<BriefingFlow> createState() => _BriefingFlowState();
}

class _BriefingFlowState extends ConsumerState<BriefingFlow> {
  /// The card on screen, kept while its result is shown. Null: take the first unanswered one.
  String? _currentId;
  BriefingAnswer? _answer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(briefingControllerProvider.notifier).load();
    });
  }

  BriefingController get _controller => ref.read(briefingControllerProvider.notifier);

  Future<void> _choose(BriefingCard card, int index) async {
    final answer = await _controller.answer(card.id, index);
    if (answer != null && mounted) {
      setState(() {
        _currentId = card.id;
        _answer = answer;
      });
    }
  }

  void _next() {
    _controller.clearError();
    setState(() {
      _currentId = null;
      _answer = null;
    });
  }

  void _retry() {
    _controller.clearError();
    setState(() => _answer = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(briefingControllerProvider);
    final cards = state.cards;
    final banner = state.error == null
        ? null
        : MessageBanner(
            message: state.error!,
            actionLabel: cards == null ? VerificationCopy.retry : null,
            onAction: cards == null ? _controller.load : null,
          );
    if (cards == null) {
      return FlowScaffold(
        title: VerificationCopy.briefingTitle,
        banner: banner,
        children: [
          if (state.error == null) const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (cards.isEmpty) {
      return const FlowScaffold(
        title: VerificationCopy.briefingTitle,
        children: [
          EmptyState(
            icon: Icons.menu_book_outlined,
            title: VerificationCopy.briefingEmpty,
          ),
        ],
      );
    }
    final index = _currentId != null
        ? cards.indexWhere((c) => c.id == _currentId)
        : cards.indexWhere((c) => !c.answered);
    if (index < 0) return _done(context);
    return _card(context, cards, index, state, banner);
  }

  Widget _card(
    BuildContext context,
    List<BriefingCard> cards,
    int index,
    BriefingState state,
    Widget? banner,
  ) {
    final theme = Theme.of(context);
    final card = cards[index];
    final answer = _answer;
    return FlowScaffold(
      title: card.title,
      step: index + 1,
      steps: cards.length,
      stepWord: VerificationCopy.briefingCardWord,
      banner: answer == null ? banner : null,
      children: [
        Text(card.body, style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gaps.xl),
        if (answer == null) ...[
          Text(card.question, style: theme.textTheme.titleMedium),
          const SizedBox(height: Gaps.md),
          for (var i = 0; i < card.choices.length; i++)
            ChoiceCard(
              label: card.choices[i],
              onTap: state.sending ? () {} : () => _choose(card, i),
            ),
        ] else ...[
          Text(
            answer.correct ? VerificationCopy.briefingRight : VerificationCopy.briefingWrong,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Gaps.sm),
          Text(answer.explanation, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Gaps.xl),
          FilledButton(
            onPressed: answer.correct ? _next : _retry,
            child: Text(
              answer.correct ? VerificationCopy.briefingContinue : VerificationCopy.briefingRetry,
            ),
          ),
        ],
      ],
    );
  }

  Widget _done(BuildContext context) {
    return FlowScaffold(
      title: VerificationCopy.briefingDone,
      children: [
        Text(VerificationCopy.briefingDoneBody, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: Gaps.xl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(VerificationCopy.briefingFinish),
        ),
      ],
    );
  }
}
