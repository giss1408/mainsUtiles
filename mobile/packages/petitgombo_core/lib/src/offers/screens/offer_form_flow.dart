import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../verification/screens/flow_scaffold.dart';
import '../../verification/verification_controller.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/screen_scaffold.dart';
import '../my_offers_controller.dart';
import '../offer_copy.dart';
import '../offer_format.dart';
import '../offer_models.dart';
import '../offer_rules.dart';

String _clock(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

/// Creates an offer, or edits or copies a draft, one question per screen.
///
/// Times are Abidjan times, which are UTC all year, so the start is built as a UTC date.
class OfferFormFlow extends ConsumerStatefulWidget {
  const OfferFormFlow({super.key, this.draft});

  /// The offer to edit (a draft) or to copy (a refused, withdrawn or closed one).
  final MyOffer? draft;

  @override
  ConsumerState<OfferFormFlow> createState() => _OfferFormFlowState();
}

class _OfferFormFlowState extends ConsumerState<OfferFormFlow> {
  static const _pickerTime = TimeOfDay(hour: 9, minute: 0);

  int _step = 0;
  String? _id;
  int? _categoryId;
  final Set<String> _duties = {};
  DateTime? _date;
  TimeOfDay? _time;
  int? _duration;
  int? _pay;
  final _payController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft == null) return;
    _id = draft.id;
    _categoryId = draft.categoryId;
    _duties.addAll(draft.duties);
    final start = draft.startsAt.toUtc();
    _date = DateTime.utc(start.year, start.month, start.day);
    _time = TimeOfDay(hour: start.hour, minute: start.minute);
    _duration = draft.durationMinutes;
    _pay = draft.payXof;
    _payController.text = '${draft.payXof}';
    _noteController.text = draft.note;
  }

  @override
  void dispose() {
    _payController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Today in Abidjan.
  DateTime get _today {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  DateTime _startUtc() {
    final date = _date!;
    final time = _time!;
    return DateTime.utc(date.year, date.month, date.day, time.hour, time.minute);
  }

  OfferCategory? _categoryIn(List<OfferCategory> categories) {
    for (final category in categories) {
      if (category.id == _categoryId) return category;
    }
    return null;
  }

  List<String> _selectedDuties(OfferCategory category) =>
      category.duties.where(_duties.contains).toList();

  OfferDraft _draft(OfferCategory category) => OfferDraft(
        categoryId: category.id,
        duties: _selectedDuties(category),
        startsAt: _startUtc(),
        durationMinutes: _duration!,
        payXof: _pay!,
        note: _noteController.text.trim(),
      );

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  void _chooseCategory(OfferCategory category) {
    setState(() {
      if (category.id != _categoryId) _duties.clear();
      _categoryId = category.id;
      if (_duration != null && !category.durationsMinutes.contains(_duration)) _duration = null;
      _step = 1;
    });
  }

  Future<void> _pickDate(OfferLimits limits) async {
    final today = _today;
    final last = today.add(Duration(days: limits.maxDaysAhead));
    var initial = _date ?? today;
    if (initial.isBefore(today)) initial = today;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(last.year, last.month, last.day),
    );
    if (picked != null) {
      setState(() => _date = DateTime.utc(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? _pickerTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _time = picked);
  }

  /// Saves the draft (create or update). Null when the server refused it; the
  /// reason is then in the controller's error.
  Future<MyOffer?> _save(OfferCategory category) async {
    final saved =
        await ref.read(myOffersControllerProvider.notifier).saveDraft(_draft(category), id: _id);
    if (saved != null) _id = saved.id;
    return saved;
  }

  Future<void> _toSummary(OfferCategory category) async {
    setState(() => _step = 5);
    await _save(category);
  }

  Future<void> _publish(OfferCategory category) async {
    final controller = ref.read(myOffersControllerProvider.notifier);
    final saved = await _save(category);
    if (saved == null) return;
    final sent = await controller.publish(saved.id);
    if (sent == null || !mounted) return;
    final hours = ref.read(myOffersControllerProvider).data?.reviewHours ?? 24;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => _SentScreen(offer: sent, reviewHours: hours)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myOffersControllerProvider);
    final category = _categoryIn(state.categories);
    final limits = state.limits;
    final Widget page;
    if (limits == null) {
      page = const ScreenScaffold(
        title: OfferCopy.createOffer,
        children: [Text(OfferCopy.genericError)],
      );
    } else {
      page = switch (_step) {
        0 => _categoryStep(state.categories),
        1 when category != null => _dutiesStep(category),
        2 when category != null => _whenStep(category, limits),
        3 when category != null => _payStep(category, limits),
        4 => _noteStep(limits),
        5 when category != null => _summaryStep(category, state),
        _ => _categoryStep(state.categories),
      };
    }
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: page,
    );
  }

  Widget _categoryStep(List<OfferCategory> categories) => FlowScaffold(
        title: OfferCopy.categoryTitle,
        step: 1,
        steps: 6,
        children: [
          if (categories.isEmpty) const Text(OfferCopy.noCategory),
          for (final category in categories)
            ChoiceCard(label: category.name, onTap: () => _chooseCategory(category)),
        ],
      );

  Widget _dutiesStep(OfferCategory category) => FlowScaffold(
        title: OfferCopy.dutiesTitle,
        step: 2,
        steps: 6,
        children: [
          for (final duty in category.duties)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _duties.contains(duty),
              title: Text(duty),
              onChanged: (ticked) => setState(() {
                if (ticked == true) {
                  _duties.add(duty);
                } else {
                  _duties.remove(duty);
                }
              }),
            ),
          const SizedBox(height: Gaps.lg),
          BusyButton(
            label: OfferCopy.next,
            onPressed: _duties.isEmpty ? null : () => setState(() => _step = 2),
          ),
        ],
      );

  Widget _whenStep(OfferCategory category, OfferLimits limits) {
    final theme = Theme.of(context);
    final date = _date;
    final time = _time;
    final duration = _duration;
    final problem = time != null && duration != null
        ? timeWindowMessage(limits, time.hour * 60 + time.minute, duration)
        : null;
    final ready = date != null && time != null && duration != null && problem == null;
    return FlowScaffold(
      title: OfferCopy.whenTitle,
      step: 3,
      steps: 6,
      children: [
        Text(OfferCopy.dateLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: Gaps.sm),
        OutlinedButton(
          key: const Key('offer-date'),
          onPressed: () => _pickDate(limits),
          child: Text(date == null ? OfferCopy.dateLabel : formatDay(date)),
        ),
        const SizedBox(height: Gaps.lg),
        Text(OfferCopy.startLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: Gaps.sm),
        OutlinedButton(
          key: const Key('offer-time'),
          onPressed: _pickTime,
          child: Text(time == null ? OfferCopy.startLabel : _clock(time)),
        ),
        const SizedBox(height: Gaps.lg),
        Text(OfferCopy.durationLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: Gaps.sm),
        Wrap(
          spacing: Gaps.sm,
          runSpacing: Gaps.sm,
          children: [
            for (final minutes in category.durationsMinutes)
              ChoiceChip(
                label: Text(formatDuration(minutes)),
                selected: duration == minutes,
                onSelected: (_) => setState(() => _duration = minutes),
              ),
          ],
        ),
        if (problem != null) ...[
          const SizedBox(height: Gaps.lg),
          MessageBanner(message: problem),
        ],
        const SizedBox(height: Gaps.xl),
        BusyButton(
          label: OfferCopy.next,
          onPressed: ready ? () => setState(() => _step = 3) : null,
        ),
      ],
    );
  }

  Widget _payStep(OfferCategory category, OfferLimits limits) {
    final typed = _payController.text.trim().isNotEmpty;
    final problem = payMessage(limits, _pay);
    return FlowScaffold(
      title: OfferCopy.payTitle,
      step: 4,
      steps: 6,
      children: [
        TextField(
          key: const Key('offer-pay'),
          controller: _payController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: OfferCopy.payLabel,
            suffixText: 'FCFA',
            helperText: OfferCopy.suggestion(category.suggestedPayMin, category.suggestedPayMax),
          ),
          onChanged: (text) => setState(() => _pay = int.tryParse(text.replaceAll(' ', ''))),
        ),
        if (typed && problem != null) ...[
          const SizedBox(height: Gaps.md),
          MessageBanner(message: problem),
        ],
        const SizedBox(height: Gaps.xl),
        BusyButton(
          label: OfferCopy.next,
          onPressed: problem == null ? () => setState(() => _step = 4) : null,
        ),
      ],
    );
  }

  Widget _noteStep(OfferLimits limits) => FlowScaffold(
        title: OfferCopy.noteTitle,
        step: 5,
        steps: 6,
        children: [
          TextField(
            key: const Key('offer-note'),
            controller: _noteController,
            maxLines: 4,
            maxLength: limits.noteMaxLength,
            decoration: const InputDecoration(labelText: OfferCopy.noteLabel),
          ),
          const SizedBox(height: Gaps.sm),
          Text(OfferCopy.noteReminder, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: Gaps.xl),
          BusyButton(label: OfferCopy.next, onPressed: () => _toSummary(_categoryFromState())),
        ],
      );

  /// The category the summary and the save refer to; the form cannot reach a later
  /// step without one.
  OfferCategory _categoryFromState() =>
      _categoryIn(ref.read(myOffersControllerProvider).categories)!;

  Widget _summaryStep(OfferCategory category, MyOffersState state) {
    final theme = Theme.of(context);
    final address = ref.watch(verificationControllerProvider).checklist?.address;
    final note = _noteController.text.trim();
    return FlowScaffold(
      title: OfferCopy.summaryTitle,
      step: 6,
      steps: 6,
      banner: state.error == null ? null : MessageBanner(message: state.error!),
      children: [
        Text(category.name, style: theme.textTheme.titleMedium),
        const SizedBox(height: Gaps.sm),
        for (final duty in _selectedDuties(category))
          Text('• $duty', style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gaps.md),
        Text(formatWhen(_startUtc(), _duration!), style: theme.textTheme.bodyLarge),
        Text(formatXof(_pay!), style: theme.textTheme.bodyLarge),
        if (note.isNotEmpty) ...[
          const SizedBox(height: Gaps.sm),
          Text(note, style: theme.textTheme.bodyLarge)
        ],
        if (address != null && address.commune.isNotEmpty) ...[
          const SizedBox(height: Gaps.md),
          Text('${OfferCopy.placeLabel} : ${address.commune}, ${address.quartier}',
              style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Gaps.xl),
        BusyButton(
          label: OfferCopy.publish,
          busy: state.sending,
          onPressed: state.sending ? null : () => _publish(category),
        ),
      ],
    );
  }
}

/// Shown after an offer is sent: published, or waiting for staff.
class _SentScreen extends StatelessWidget {
  const _SentScreen({required this.offer, required this.reviewHours});

  final MyOffer offer;
  final int reviewHours;

  @override
  Widget build(BuildContext context) {
    final published = offer.status == OfferStatus.published;
    return ScreenScaffold(
      title: published ? OfferCopy.sentPublished : OfferCopy.sentForReview(reviewHours),
      icon: Icons.check_circle_outline,
      children: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Text(OfferCopy.backToOffers),
        ),
      ],
    );
  }
}
