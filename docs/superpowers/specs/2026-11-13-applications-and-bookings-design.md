# Applications, bookings and payment — design

Date: 2026-11-13. Product spec: `skill.md` (sections 3, 4, 6 "Booking state machine", "Payment by
mobile money"). Builds on householder verification, job offers and jobber verification. This is
piece 4 of 4, built as three plans.

## Goal

Work like Airbnb, for mini-jobs. A verified jobber (J1) finds an offer and applies. The householder
picks one applicant. The householder pays the platform first, by mobile money; the booking is then
confirmed and the exact address is released to the jobber shortly before the start. After the duty
is done the platform pays the jobber, and both sides review each other.

The aim is that a real job can happen safely through the app, with price, place, time, duties and
payment all on the record (safety rule 4: no booking off the record).

## Decisions already taken (by the product owner)

- Airbnb-style flow applied to the existing offers; not a house-rental product.
- The householder **chooses** among applicants (request and accept). There is no instant booking.
- **The householder pays the platform first**, by mobile money. The platform pays the jobber after
  the duty is done.
- **Mobile money only** in this piece. Cash, with the QR code scan, comes later.

## Goals

- J1 is enforced: only a J1 jobber can apply, and J1 is checked again at accept and at payment.
- One offer, one jobber, one booking. Accepting is safe against two taps and two devices.
- The address stays hidden until the booking is confirmed and the release window opens.
- Every transition is audited. Every payment call is idempotent.
- The householder sees applicants with first name, tier, rating and jobs done; the jobber sees the
  householder's tier, rating and jobs done before applying. The jobber's photo and full name go to
  the householder only once the booking is confirmed.

## Non-goals

- Live tracking, the door handshake, the dead-man timer, SOS, chat, push and SMS notifications.
  The apps show the new state when opened or refreshed. (Later pieces.)
- Cash and the payment QR code; the householder access fee; recurring or multi-day offers; several
  jobbers on one offer; tier J2 rules; favourites and "rebook"; tips.
- A real payment provider. The `PaymentProvider` interface and a mock exist; the real one is a
  business decision (Wave, Orange, MTN or an aggregator).

## Anti-goals (a failure even if it works)

- The jobber learns an address, or the householder a full name or photo, before payment succeeds.
- A booking, a payment or a payout created twice by a retry, a double tap or a repeated webhook.
- Copy that promises more than the platform can do, or the word "escrow" in the apps, before the
  provider and the regulator allow holding customer money.
- A jobber or householder who cannot tell, from the screen, whose turn it is.

## Approaches considered

| | What | Trade-off |
|--|------|-----------|
| A | Apply and accept only; booking record, nothing else | Smallest. Enforces J1 but delivers no job: the two sides would arrange the rest outside the app. |
| B | Apply, accept, confirm and release the address | A job can happen safely, but no payment, so no Airbnb feel. |
| **C (chosen)** | Apply, accept, pay first, release the address, complete, release payment, review | The full Airbnb loop, minus tracking and cash. Bigger, so built as three plans. |

Chosen with the product owner. Within C, payment is built behind `PaymentProvider` with a mock; the
provider's settlement model decides how the money is held (see Open decisions).

## The flow

```
published offer ──apply──▶ application (pending)
                               │ householder accepts one, the others are declined
                               ▼
booking: accepted ──pay──▶ confirmed ──window opens──▶ address_released
                               │                            │ jobber taps "Je suis arrivé(e)"
        cancel / not paid      ▼                            ▼
        ▼                  (refund)                    checked_in ──"J'ai terminé"──▶ completion_pending
     cancelled / expired                                                  │ householder confirms, or timeout
                                                                          ▼
                                            completed ──▶ payout to the jobber ──▶ reviews
   side exits: disputed (staff decide), safety_hold (staff only)
```

## Plans

1. **Applications** (`apps/bookings`): apply, list, withdraw, accept; the booking is created
   `accepted`; the offer leaves the jobber list.
2. **Payment and address release** (`apps/payments`): pay, confirm, expiry, cancellation and refund,
   the release window.
3. **The job and after**: check-in and check-out, householder confirmation and timeout, payout,
   disputes in the console, reviews, rating on the applicant card.

## Rules

**Applying.** Jobber is J1 (`jobber_tier`) and the offer is `published` and not yet started. One
live application per jobber and offer. At most `APPLICATIONS_MAX_OPEN` (5) open applications per
jobber, and `APPLICATIONS_MAX_PER_OFFER` (20) per offer. A short message (up to 200 characters) goes
through the same screening as offers (contact details, phone numbers); a hit is refused with a
clear message, not queued. A jobber with an open dispute cannot apply. A jobber cannot apply to an
offer that overlaps a booking of theirs.

**Withdrawing.** A jobber can withdraw a pending application at any time.

**Accepting.** Only the offer's author. In one transaction with the offer row locked: the offer must
be `published` and not started; the chosen applicant must still be J1; the booking is created
`accepted` with a snapshot of category, duties, start, duration, pay, commune and quartier; the
other applications become `declined`; the offer becomes `booked` (hidden from jobbers).

**Paying.** The householder has `PAYMENT_WINDOW_HOURS` (12) after accepting, and never past the
release window's opening. They pay `pay_xof` plus the platform fee (`PLATFORM_FEE_PERCENT`, default
0, a business decision) from a mobile-money number they enter. The payment starts `pending`; a
signed webhook (idempotent, by provider reference) sets it `successful` or `failed`. On success the
booking becomes `confirmed`, and the jobber's photo and full name are released to the householder.
If the window passes unpaid, the booking becomes `expired`, the applicant is told, and the offer is
`published` again if it has not started.

**Releasing the address.** Only to the accepted jobber, only for a `confirmed` booking, only from
`ADDRESS_RELEASE_HOURS` (3) before the start until check-out. Each release is audited. Before then
the jobber sees commune and quartier only.

**Cancelling.** Before check-in, either side can cancel; a `confirmed` booking is refunded in full
(`CANCEL_FREE_HOURS`, default 24 h before the start; after that the refund rule is a business
decision, default full refund and a recorded strike). Repeated cancellations are flagged for staff
(`CANCEL_STRIKES_FLAG`, 3 in 30 days). The offer goes back to `published` if it has not started.

**Completing.** The jobber taps "Je suis arrivé(e)" (position recorded, no geofence yet) then
"J'ai terminé". The householder confirms, or `RELEASE_TIMEOUT_HOURS` (24) pass and it completes by
itself. The householder can instead report a problem inside that window: the booking becomes
`disputed`, the payout is frozen and staff decide (release, refund or split). On `completed` the
platform pays the jobber `pay_xof` to their mobile-money number. Payout is idempotent.

**Reviews.** Only for a `completed` booking, both ways, 1 to 5 stars and a short comment, hidden until
both are in or `REVIEW_WINDOW_DAYS` (7) pass, then published together. A private "quelque chose
n'allait pas" report goes to staff without telling the other side.

## Data

- `Application` (offer, jobber, message, status `pending/accepted/declined/withdrawn`, timestamps).
- `Booking` (offer, application, householder, jobber, snapshot fields, state per the diagram, per-state
  timestamps, `cancelled_by`, `cancel_reason`).
- `Payment` (booking, amount, fee, state `pending/successful/failed/refunded/disputed`, payout state
  `none/pending/paid/failed`, provider references, an idempotency key; unique per booking attempt).
- `Review` (booking, author, about, stars, comment, published_at); `Report` for private reports.
- `Offer.Status` gains `booked`.
- Every transition writes an `AdminAction`-style audit row (actor may be the user, a task or staff).

## Surfaces

- **Jobber app:** offer detail gains the householder's trust line and "Postuler"; "Mes candidatures";
  "Mes jobs" with state, the address when released, "Je suis arrivé(e)" and "J'ai terminé", reviews.
  A jobber below J1 sees what is still missing, with a link to the checklist.
- **Householder app:** each offer shows its applicants; accepting; the payment screen; the booking
  with state, "Confirmer que c'est fait", "Signaler un problème", reviews.
- **Console (staff):** bookings board, disputes, payment problems, strikes, reports. Staff app: later.
- **Backend:** apps `bookings` and `payments`; the existing `PaymentProvider` and a mock; Celery tasks
  for expiry, release timeout and review publication.

## Constraints

Copy in French (jobber "tu", householder "vous"); amounts as `3 500 FCFA`; rules in services; errors
as `{error, message}`; every limit a setting read from the environment; nothing returned to a jobber
may include the householder's name, phone, id or exact address before release; nothing returned to a
householder may include the jobber's phone, ever; webhooks verified and idempotent; 320dp at text
scale 2 without overflow; threat-model rows added for each new risk.

## Open decisions for the business

- The payment provider and its settlement model (can it hold funds until release? does it pay out to
  a mobile-money number?). Until then the mock stands in. Do not say "escrow" in the apps.
- The platform fee and who bears it; the refund rule for a late cancellation.
- Whether SMS or push is needed for "you were accepted" and "pay now", given phones that rarely open
  the app. (Probably yes before launch; out of scope here.)
- The review wording and the dispute rules staff follow.

## Left to the builder

Screen layouts inside the existing tokens; the exact message texts; names of settings beyond those
given; the shape of the mock provider's webhook; query and index choices.

## Calls I made (to check)

- Request and accept, no instant booking; the offer is hidden (`booked`) the moment it is accepted.
- Payment window 12 h, address release 3 h before, release timeout 24 h, review window 7 days:
  placeholders, all settings.
- Application message screened like offers, refused rather than queued.
- Check-in has no geofence yet; the door handshake is a later piece.
- One application cannot overlap another booking of the same jobber.
- A late cancellation refunds in full for now and records a strike.
