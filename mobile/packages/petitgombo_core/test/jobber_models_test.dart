import 'package:flutter_test/flutter_test.dart';
import 'package:petitgombo_core/petitgombo_core.dart';

import 'support/verification_fixtures.dart';

void main() {
  test('a jobber checklist parses the four steps and the required list', () {
    final checklist = jobberChecklist(
      contact: contactStepJson(status: 'in_progress', pending: 1),
      briefing: briefingStepJson(status: 'in_progress', answered: 1),
    );
    expect(checklist.required, ['identity', 'guarantor', 'trusted_contact', 'briefing']);
    expect(checklist.trustedContact.status, StepStatus.inProgress);
    expect(checklist.trustedContact.pending, 1);
    expect(checklist.trustedContact.confirmed, 0);
    expect(checklist.briefing.status, StepStatus.inProgress);
    expect(checklist.briefing.answered, 1);
    expect(checklist.briefing.total, 3);
    expect(checklist.briefing.newCards, 2);
  });

  test('a checklist without the new keys still parses', () {
    final checklist = VerificationChecklist.fromJson({
      'tier': 'J0',
      'review_hours': 24,
      'identity': {'status': 'confirmed', 'reason': ''},
      'guarantor': {'status': 'not_started', 'reason': ''},
    });
    expect(checklist.required, ['identity', 'guarantor']);
    expect(checklist.trustedContact.status, StepStatus.notStarted);
    expect(checklist.briefing.status, StepStatus.notStarted);
    expect(checklist.briefing.total, 0);
  });

  test('a householder checklist has no jobber steps', () {
    final checklist = VerificationChecklist.fromJson(checklistJson());
    expect(checklist.trustedContact.status, StepStatus.notStarted);
    expect(checklist.forJobber, isFalse);
  });

  test('in progress is its own status and is not startable', () {
    expect(StepStatus.parse('in_progress'), StepStatus.inProgress);
    expect(StepStatus.inProgress.canStart, isFalse);
  });

  test('contacts and cards parse', () {
    final contact = TrustedContact.fromJson(
      contactJson(
          status: 'confirmed',
          awaitingCode: false,
          replaces: 'c-0',
          endsAt: '2026-11-20T10:00:00Z'),
    );
    expect(contact.name, 'Awa Koné');
    expect(contact.status, ContactState.confirmed);
    expect(contact.awaitingCode, isFalse);
    expect(contact.replaces, 'c-0');
    expect(contact.endsAt, DateTime.utc(2026, 11, 20, 10));
    expect(TrustedContact.fromJson(contactJson()).status, ContactState.pending);
    expect(TrustedContact.fromJson(contactJson(status: 'other')).status, ContactState.pending);

    final card = BriefingCard.fromJson(cardJson(answered: true));
    expect(card.choices, hasLength(3));
    expect(card.answered, isTrue);
    final answer =
        BriefingAnswer.fromJson({'correct': false, 'explanation': 'Parce que.', 'complete': false});
    expect(answer.correct, isFalse);
    expect(answer.explanation, 'Parce que.');
  });
}
