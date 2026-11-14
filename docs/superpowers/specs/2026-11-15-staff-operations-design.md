# Staff operations design (stage 4)

Approved by the owner on 2026-11-15 (short design, in conversation).

## Intent

Everything staff must do or send is on the staff phone. Users are told what happens to their
booking by a WhatsApp message that staff send from a queue; staff see what is waiting; payouts and
disputes no longer need the web console. Why: there is no SMS and no push for now (README "Messages
and alerts"), and the people on duty work from the phone that holds the official WhatsApp number.

## Goals

- A message is queued at each event of a booking and sent by staff in two taps.
- Staff see counts of what waits and what is late.
- Payouts and disputes are worked in the staff app with the same rules as the console.

**Non-goals:** SMS, push, WhatsApp Business API, WhatsApp rate limits, consent wording, night rules,
strikes, fake-GPS detection, editing a message.

**Anti-goals:** a message that carries an address, a full name, the other side's number or a payment
reference; a number shown, stored or logged on the staff phone; a private remark that reaches the
other side; a stale message sent anyway; new money rules.

## Approaches

1. **A queue of messages written by the backend, sent through the existing one-time WhatsApp link
   (chosen).** Reuses `registry.get_messaging().whatsapp_link`, the staff queues and their audit.
   Costs staff time per message.
2. Staff type the messages themselves from a list of events. Rejected: free text leaks data and
   differs from one agent to the next.
3. WhatsApp Business API or SMS. Rejected by the owner for now (cost, provider, approval).

## Design

**Message** (`apps/bookings`): `offer`, `booking` (null for "you have an applicant"), `recipient`,
`kind`, `urgent`, `status` (`pending`, `sent`, `dropped`), `created_at`, `sent_by`, `sent_at`. At most
one pending message per (offer, recipient, kind). No text is stored: it is rendered from the kind
when staff open or send it.

**Kinds, recipient, and when it is still true** (checked when staff send; otherwise the message is
dropped and staff are told):

| Kind | To | Queued when | Still true while |
|------|----|-------------|------------------|
| `applicant` | householder | first pending application on an offer | the offer is published |
| `accepted` | jobber | the application is accepted | booking `accepted` or `payment_review` |
| `pay_reminder` (urgent) | householder | `PAYMENT_REMINDER_HOURS` (4) before the pay deadline, unpaid | booking `accepted` |
| `payment_confirmed` | householder | staff confirm the payment | booking `confirmed` or `address_released` |
| `payment_refused` | householder | staff refuse the payment | booking `accepted` |
| `job_confirmed` | jobber | staff confirm the payment | booking `confirmed` or `address_released` |
| `address_available` (urgent) | jobber | the release window opens (sweep) | booking `confirmed` or `address_released`, not ended |
| `confirm_job` | householder | the jobber checks out | booking `completion_pending` |
| `paid` | jobber | staff record the payout | always |
| `cancelled` | the other side | a party cancels | always |
| `no_show` | householder | the no-show sweep cancels | always |
| `expired` | jobber | an unpaid booking expires | always |
| `refunded` | householder | staff record the refund | always |
| `dispute_opened` | the other side (both when the system opens it) | a dispute is opened | booking `disputed` |
| `dispute_resolved` | both | staff decide | always |
| `review_invite` | both | the booking completes | the recipient may still review |

A concern never queues anything. Texts are French, "vous" for the householder and "tu" for the
jobber, name the job by category and day only, and end with "Ouvrez/Ouvre l'application petitGombo".

**Staff rights.** New permission `bookings.send_message`, given to `payment_agent` and
`enrolment_agent`. Payouts need `make_payout`, disputes `resolve_dispute` (existing).

**Staff API** (all `no-store`, staff device session):
- `GET staff/messages` (pending; urgent first, then oldest; `id, kind, kind_label, recipient_role,
  urgent, late, created_at`), `GET staff/messages/<id>` (adds `text`, `category_name`; audited),
  `POST staff/messages/<id>/send` → `{whatsapp_url}` and the message is `sent`; a stale message is
  dropped and answers 409 `message_stale`.
- `GET staff/payouts`, `GET staff/payouts/<id>` (adds the jobber's phone, audited),
  `POST staff/payouts/<id>/pay {reference}`.
- `GET staff/disputes`, `GET staff/disputes/<id>` (text, who wrote it, first names, times, distance,
  payment state; audited), `POST staff/disputes/<id>/resolve {outcome, note, jobber_xof?}`.
- `GET staff/alerts` → counts the caller may see: `payments_waiting, payments_late, refunds_waiting,
  payouts_waiting, payouts_late, disputes_open, disputes_late, messages_waiting, messages_late,
  far_checkins`.

**Late.** Messages: `MESSAGE_LATE_MINUTES` (60), urgent ones `MESSAGE_URGENT_LATE_MINUTES` (15).
Payouts: `PAYOUT_LATE_HOURS` (24). Disputes: `DISPUTE_LATE_HOURS` (24).

**Staff app.** Sections: Enrôlements, Contacts, Paiements (tabs "À vérifier", "Remboursements",
"À verser"), Messages, Litiges; each shown only with its right, with a count badge from the alerts.
Message detail shows the text and "Ouvrir WhatsApp". Nothing sensitive is kept after a screen closes.

**Console.** "Messages" read-only list (kind, state, dates, who sent), for oversight.

## Left to the builder

Exact wording of each message, screen layout within the existing staff app patterns, how the alert
counts refresh (with each queue refresh).
