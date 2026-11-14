# Next steps

Updated 2026-11-15. Branch `feat/jobber-verification` is pushed up to 4104c10. Everything
after it is local and **not pushed**: the stage 3 plan and all 12 tasks of stage 3.

## What is built

| Piece | State |
|-------|-------|
| Enrolment, householder verification, job offers | Done, on the branch |
| Jobber verification 3a (identity, guarantor) and 3b (trusted contact, safety briefing) | Done; contact codes are sent from the staff app |
| Applications (stage 1): J1 jobbers apply, the householder accepts one | Done |
| Payment and address release (stage 2): manual payment checked by staff, cancel, refund, exact pin, jobber name and photo | Done |
| Staff app payments queue (check a payment, record a refund) | Done |
| **Stage 3: the job and after** (check-in/out, confirmation, payout, disputes, reviews) | **Done: backend, console, householder and jobber apps** (README "The job and after") |

Everything is covered by automated tests and the debug APKs build. **Nothing has been tried on a real
phone.** Jobber verification 3a/3b and the applications stage went through a `/code-review`; the
payment stage, the staff payments queue and all of stage 3 have had a self-review only.

## What stage 3 changed that you should know

- **The jobber app now asks for the location permission**, once, at the first "Je suis arrivé(e)".
  A refusal still checks in, without a distance.
- **Payouts and disputes are in the web console only** ("Paiements aux jobbers", "Signalements"),
  for the group `payment_agent`. The staff app does not have them yet.
- Decisions I took where the plan was silent or wrong (check them):
  - a **split** dispute pays the jobber's share even though the payment is then "refund due" (the plan
    would have blocked it);
  - a **full refund** still shows everything the householder paid, fee included, as stage 2 did; only
    a split shows a smaller amount. Same thing while the fee is 0;
  - a **dispute refund** cancels the booking and closes the offer (it is not offered again);
  - the householder's booking page **stays available after completion** (needed for the review);
  - "J'ai terminé" asks to confirm, so a mis-tap does not end the job.
- Two old tests depended on today's date and started failing on 2026-11-14; both are fixed.
- To run the backend tests, the database must be up: `docker compose up -d db`.

## Before merging

1. **Review the branch.** Run `/code-review` on `feat/jobber-verification`, which now includes the
   payment stage, the staff payments queue and stage 3 (none of them reviewed by a second pair of eyes).
   Points to look at first: paying twice or paying a refunded booking, the three sweeps, a dispute
   raised late or twice, reviews leaking before both are in.
2. **Try it on real phones**, end to end, with a jobber account, a householder account and one staff phone:
   - jobber app: identity photos, guarantor, trusted contact (the code arrives by WhatsApp from the
     staff phone), briefing; then apply to an offer;
   - householder app: accept the applicant, pay from a real mobile-money app, send the reference and a
     gallery screenshot;
   - staff phone: confirm the payment in "Paiements"; check the address appears for the jobber 3 hours
     before the start, and the householder sees the jobber's name and photo;
   - cancel from each side and record the refund; let an unpaid booking expire;
   - the job: "Je suis arrivé(e)" at the door (allow, then refuse, the location), "J'ai terminé",
     "Confirmer que c'est fait"; pay the jobber from the console and check "Paiement envoyé";
   - a dispute from each side and each of the three decisions; a review from each side, and check
     neither shows before the other is in.
3. **Open a PR to `main`** once 1 and 2 are done.

## Decisions to take (owner: product)

- **Payment accounts.** Who holds the platform's Wave, MTN MoMo and Orange Money accounts, who is on
  duty to check payments, and how staff compare a payment with the account's real history. A
  screenshot alone is not proof.
- **Legal.** Holding customers' money may need a licence or a partner: a legal review before launch.
  Also the lawful basis for holding a guarantor's and a trusted contact's name and number (privacy
  notice sections "Informations sur votre garant" and "Informations sur votre personne de confiance").
- **Money rules.** The platform fee (0 until decided), the refund rule for a late cancellation
  (today: full refund), and whether the fee is kept on a refund.
- **Payout number.** The jobber is paid on their account phone. Decide whether they may give another
  mobile-money number.
- **Dispute rules.** What staff look at and how they choose between pay, refund and share; how long
  they have to answer. The review wording too.
- **Messages: decided (2026-11-15).** No SMS and no push for now. Every message goes to the staff app
  and is sent by staff on WhatsApp; alerts for staff are in the staff app too (README "Messages and
  alerts"). Still to settle for stage 4: who is on duty and at what hours, and the exact wording of
  each message.
- **Real briefing cards.** The three cards seeded by migration `0006` are placeholders; write the real
  ones in the console ("Cartes de briefing") before launch. Decide whether videos are needed.
- **A contact who says "I never agreed".** Contacts can only be replaced, never removed, so define how
  staff take such a number off the list. Staff workload of sending every contact code by hand.
- Guarantor open points: written consent, what staff do when a guarantor does not answer, the call
  script and the number staff call from, bills accepted without a utility bill.

## Build next: stage 4, the staff app runs the operations

Everything staff must do or send, on the staff phone. Not started: no design and no plan yet. Start
with the design (`superpowers:brainstorming`, then a spec in `docs/superpowers/specs/` and a plan in
`docs/superpowers/plans/`), on a new branch once this one is merged.

**Scope**

1. **Messages by WhatsApp.** The backend queues a message at each event (the list is in the README,
   "Messages and alerts"); the staff app shows "Messages à envoyer", oldest first; "Ouvrir WhatsApp"
   opens the written message and marks it sent. Same rules as the contact codes: the number only
   inside a one-time link, a permission, an audit row, nothing cached or kept on the phone.
2. **Alerts for staff.** Counts on the staff home screen and markers in the queues: a payment, a
   payout or a refund waiting too long, an open dispute, a far check-in, a message not sent.
3. **Payouts in the staff app.** "Paiements à verser": the amount, the jobber's phone (audited, never
   cached), record the reference. Today console only.
4. **Disputes in the staff app.** "Litiges": the report, the times and the distance, the three
   decisions with a reason. Today console only.

**What exists to build on**

- The WhatsApp link pattern: `apps/verification/services/contacts.py`, `apps/accounts/api/staff_views.py`
  (`whatsapp_url`, `OFFICIAL_WHATSAPP_NUMBER`), and the staff app's contacts and enrolment queues.
- The staff payments queue (`apps/bookings/api/staff_views.py`, staff app "Paiements") as the model
  for the payouts and disputes queues.
- The services are done and tested: `services/payouts.py`, `services/reports.py`. Stage 4 adds staff
  API routes and screens over them, not new rules.
- Every event already writes an audit row (`booking.accept`, `booking.payment.confirm`,
  `booking.check_out`, `booking.complete`, `booking.payout.pay`, `booking.dispute.resolve`...): the
  message queue hooks into the same places.

**Questions the design must answer**

- One message per event, or grouped when several wait for the same person?
- What happens to a message that is no longer true when staff get to it (the booking was cancelled
  meanwhile): dropped, or replaced?
- Night and weekends: which messages can wait, which cannot ("the address is available" a few hours
  before a job).
- A new permission and group for sending messages, or the existing `payment_agent` and
  `enrolment_agent`?
- How many messages a day one phone can send before WhatsApp restricts the number, and what the
  queue does then.
- Does a person have to agree to be written to on WhatsApp (wording at enrolment, privacy notice)?

**After stage 4**, in the order I would take them:

1. Strikes for repeated cancellations and no-shows, shown to staff.
2. Fake-GPS detection at check-in (the distance is recorded but trusts the phone).
3. Two stage 2 minors: an audit row is written at every view of the booking once the jobber's name is
   shown, and a refused proof returns the booking to "accepted" with its original time, which can leave
   little time to send another.

## Out of scope so far

Tier J2 and commune of service; linked-account detection (a guarantor, bill or phone shared across
accounts) and a banned-guarantor rule; automated guarantor call; SMS and push (messages go through the staff app and WhatsApp for now);
liveness check; cash with
the QR code; live tracking, the door handshake, the dead-man timer, SOS and chat; recurring offers;
several jobbers on one offer.

## Housekeeping

- Delete the git-ignored `.superpowers/sdd/` workspaces when the final review is done.
- Threat-model rows marked "partly built" or "not built" (reason-for-access prompts, alerts on unusual
  staff volume, screenshot blocking checked on a phone) stay open.
- Deferred minors from the reviews are recorded in each plan's ledger under `.superpowers/sdd/`.
