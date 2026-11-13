import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/spacing.dart';
import '../../app/theme.dart';
import '../../enrolment/phone_format.dart';
import '../../widgets/message_banner.dart';
import '../../widgets/ui_kit.dart';
import '../contacts_controller.dart';
import '../verification_controller.dart';
import '../verification_copy.dart';
import '../verification_models.dart';
import 'flow_scaffold.dart';

enum _View { list, form, code }

/// The jobber's trusted contacts: a list, a form to add or replace one, and the code screen.
/// A contact is never removed, only replaced by another one who confirms the same way.
class TrustedContactFlow extends ConsumerStatefulWidget {
  const TrustedContactFlow({super.key});

  @override
  ConsumerState<TrustedContactFlow> createState() => _TrustedContactFlowState();
}

class _TrustedContactFlowState extends ConsumerState<TrustedContactFlow> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  _View _view = _View.list;

  /// The contact being replaced, when the form is a replacement.
  String? _replacing;

  /// The contact the code screen confirms.
  String? _codeFor;
  bool _showErrors = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(contactsControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  ContactsController get _controller => ref.read(contactsControllerProvider.notifier);

  bool get _nameOk => _name.text.trim().isNotEmpty;
  bool get _phoneOk => normaliseIvorianPhone(_phone.text) != null;

  void _go(_View view) {
    _controller.clearError();
    setState(() {
      _view = view;
      _showErrors = false;
    });
  }

  void _openForm({String? replacing}) {
    _replacing = replacing;
    _name.clear();
    _phone.clear();
    _go(_View.form);
  }

  void _openCode(String id) {
    _codeFor = id;
    _code.clear();
    _go(_View.code);
  }

  Future<void> _submit(String relationship) async {
    if (!_nameOk || !_phoneOk) {
      setState(() => _showErrors = true);
      return;
    }
    FocusScope.of(context).unfocus();
    final name = _name.text.trim();
    final replacing = _replacing;
    final contact = replacing == null
        ? await _controller.add(name: name, phone: _phone.text, relationship: relationship)
        : await _controller.replace(replacing,
            name: name, phone: _phone.text, relationship: relationship);
    if (contact != null && mounted) _openCode(contact.id);
  }

  Future<void> _confirm() async {
    final confirmed = await _controller.confirm(_codeFor!, _code.text);
    if (confirmed && mounted) _go(_View.list);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _view == _View.list,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_View.list);
      },
      child: switch (_view) {
        _View.list => _list(context),
        _View.form => _form(context),
        _View.code => _codeScreen(context),
      },
    );
  }

  Widget _list(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(contactsControllerProvider);
    final contacts = state.contacts;
    // A replacement takes the place of the contact it replaces.
    final taken = {for (final c in contacts ?? const <TrustedContact>[]) c.replaces};
    final used = (contacts ?? const <TrustedContact>[]).where((c) => !taken.contains(c.id)).length;
    return FlowScaffold(
      title: VerificationCopy.contactsTitle,
      banner: state.error == null ? null : MessageBanner(message: state.error!),
      children: [
        Text(VerificationCopy.contactsIntro(state.max), style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gaps.lg),
        if (contacts == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          for (final contact in contacts)
            _ContactCard(
              contact: contact,
              busy: state.sending,
              onEnterCode: () => _openCode(contact.id),
              onRequestCode: () => _controller.requestCode(contact.id),
              // A contact already being replaced waits for its replacement: change that one.
              canChange: !taken.contains(contact.id),
              onChange: () => _openForm(replacing: contact.id),
            ),
          if (used < state.max) ...[
            const SizedBox(height: Gaps.sm),
            FilledButton(
              onPressed: () => _openForm(),
              child: const Text(VerificationCopy.addContact),
            ),
          ],
        ],
      ],
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(contactsControllerProvider);
    final confirmedTarget = _replacing != null &&
        (state.contacts ?? const <TrustedContact>[])
            .any((c) => c.id == _replacing && c.status == ContactState.confirmed);
    return FlowScaffold(
      title: VerificationCopy.contactFormTitle,
      step: 1,
      steps: 2,
      banner: state.error == null ? null : MessageBanner(message: state.error!),
      children: [
        if (confirmedTarget) ...[
          Text(VerificationCopy.contactReplaceNote, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Gaps.lg),
        ],
        TextField(
          key: const Key('contact-name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          maxLength: 120,
          style: theme.textTheme.bodyLarge,
          onChanged: (_) {
            if (_showErrors) setState(() {});
          },
          decoration: InputDecoration(
            labelText: VerificationCopy.contactNameLabel,
            counterText: '',
            errorText: _showErrors && !_nameOk ? VerificationCopy.contactNameRequired : null,
          ),
        ),
        const SizedBox(height: Gaps.lg),
        TextField(
          key: const Key('contact-phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          style: theme.textTheme.bodyLarge,
          onChanged: (_) {
            if (_showErrors) setState(() {});
          },
          decoration: InputDecoration(
            labelText: VerificationCopy.contactPhoneLabel,
            errorText: _showErrors && !_phoneOk ? VerificationCopy.contactPhoneInvalid : null,
          ),
        ),
        const SizedBox(height: Gaps.xl),
        Text(VerificationCopy.contactRelationshipHint, style: theme.textTheme.titleMedium),
        const SizedBox(height: Gaps.md),
        for (final entry in VerificationCopy.contactRelationships.entries)
          ChoiceCard(label: entry.value, onTap: state.sending ? () {} : () => _submit(entry.key)),
        const SizedBox(height: Gaps.lg),
        const PrivacyNote(VerificationCopy.contactPrivacy),
      ],
    );
  }

  Widget _codeScreen(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(contactsControllerProvider);
    final hours = ref.watch(verificationControllerProvider).checklist?.reviewHours ?? 24;
    return FlowScaffold(
      title: VerificationCopy.contactCodeTitle,
      step: 2,
      steps: 2,
      banner: state.error == null ? null : MessageBanner(message: state.error!),
      children: [
        Text(VerificationCopy.contactCodeBody(hours), style: theme.textTheme.bodyLarge),
        const SizedBox(height: Gaps.lg),
        TextField(
          key: const Key('contact-code'),
          controller: _code,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          style: theme.textTheme.headlineSmall,
          decoration: const InputDecoration(
            labelText: VerificationCopy.contactCodeLabel,
            counterText: '',
          ),
        ),
        const SizedBox(height: Gaps.xl),
        BusyButton(
          label: VerificationCopy.confirmCode,
          onPressed: _confirm,
          busy: state.sending,
        ),
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.busy,
    required this.onEnterCode,
    required this.onRequestCode,
    required this.canChange,
    required this.onChange,
  });

  final TrustedContact contact;
  final bool busy;
  final VoidCallback onEnterCode;
  final VoidCallback onRequestCode;
  final bool canChange;
  final VoidCallback onChange;

  String get _status {
    if (contact.status == ContactState.confirmed) {
      final ends = contact.endsAt;
      return ends == null ? 'Confirmé' : VerificationCopy.contactReplacedOn(ends);
    }
    return contact.awaitingCode ? VerificationCopy.contactAwaiting : VerificationCopy.contactSent;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = contact.status == ContactState.pending;
    return Container(
      margin: const EdgeInsets.only(bottom: Gaps.md),
      padding: const EdgeInsets.all(Gaps.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(contact.name, style: theme.textTheme.titleMedium),
          Text(
            VerificationCopy.contactRelationships[contact.relationship] ?? '',
            style: theme.textTheme.bodyMedium!.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: Gaps.xs),
          Text(_status, style: theme.textTheme.bodyMedium),
          if (pending && !contact.awaitingCode) ...[
            const SizedBox(height: Gaps.md),
            FilledButton(onPressed: onEnterCode, child: const Text(VerificationCopy.enterCode)),
          ],
          if (pending) ...[
            const SizedBox(height: Gaps.sm),
            OutlinedButton(
              onPressed: busy ? null : onRequestCode,
              child: const Text(VerificationCopy.requestNewCode),
            ),
          ],
          if (canChange) ...[
            const SizedBox(height: Gaps.sm),
            OutlinedButton(onPressed: onChange, child: const Text(VerificationCopy.changeContact)),
          ],
        ],
      ),
    );
  }
}
