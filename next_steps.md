# Next steps

Updated 2026-11-15. Branch `feat/jobber-verification` is pushed up to 4104c10. Everything
after it is local and **not pushed**: the stage 3 plan and all 12 tasks of stage 3, and stage 4 on
the branch `feat/staff-operations` (stacked on `feat/jobber-verification`).

## What is built

| Piece | State |
|-------|-------|
| Enrolment, householder verification, job offers | Done, on the branch |
| Jobber verification 3a (identity, guarantor) and 3b (trusted contact, safety briefing) | Done; contact codes are sent from the staff app |
| Applications (stage 1): J1 jobbers apply, the householder accepts one | Done |
| Payment and address release (stage 2): manual payment checked by staff, cancel, refund, exact pin, jobber name and photo | Done |
| Staff app payments queue (check a payment, record a refund) | Done |
| **Stage 3: the job and after** (check-in/out, confirmation, payout, disputes, reviews) | **Done: backend, console, householder and jobber apps** (README "The job and after") |

| **Stage 4: the staff app runs the operations** (messages by WhatsApp, alerts, payouts, disputes) | **Done: backend, console, staff app** (README "Messages and alerts") |

Everything is covered by automated tests and the debug APKs build. **Nothing has been tried on a real
phone.** Jobber verification 3a/3b and the applications stage went through a `/code-review`; the
payment stage, the staff payments queue, all of stage 3 and all of stage 4 have had a self-review only.
End-to-end tests come next, now that stage 4 is in.

## What stage 3 changed that you should know

- **The jobber app now asks for the location permission**, once, at the first "Je suis arrivé(e)".
  A refusal still checks in, without a distance.
- Payouts and disputes were console only in stage 3; stage 4 put them in the staff app too.
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

## What stage 4 changed that you should know

- **Every booking event now queues a message** for staff to send on WhatsApp (staff app, "Messages").
  Until someone on duty sends them, nobody is told anything: the queue must be watched.
- **New right `bookings.send_message`**, given to `payment_agent` and `enrolment_agent` by migration.
- **The staff app has two more sections**: "Messages", and "Jobs" with the tabs "À verser" and
  "Litiges". Counts on the section bar turn red when something is late.
- Decisions I took where the plan was silent or wrong (check them):
  - payouts and disputes are **one section "Jobs"** with two tabs; the design listed "À verser" as a
    third tab of "Paiements" and "Litiges" as its own section. Moving them is a small change;
  - "you have an applicant" is **withdrawn once the householder has chosen**, and is not sent unless
    the offer is still published with a pending application;
  - a kind that has **no wording for the recipient's role is skipped**, so a missing text never
    blocks a payment or a cancellation;
  - a send that **fails without a connection keeps the message** in the queue (it is removed only
    when sent, withdrawn or already sent by a colleague);
  - **far check-ins are a banner** on "Jobs" that points to the console; there is no list in the app;
  - the console page and the app share `reports.report_details`; the app lists **open disputes only**,
    never a private remark.
- Known gap: **withdrawing an offer that has a booking** cancels it without a message to the jobber.

## Before merging

1. **Review the branches.** Run `/code-review` on `feat/jobber-verification` (payment stage, staff
   payments queue, stage 3) and on `feat/staff-operations` (stage 4): none of them was reviewed by a
   second pair of eyes. Points to look at first: paying twice or paying a refunded booking, the three
   sweeps, a dispute raised late or twice, reviews leaking before both are in; for stage 4, a stale
   message sent anyway, two staff sending the same message, a message hook breaking a money
   transition, a phone or a text read without the right.
2. **Try it on real phones**, end to end, with a jobber account, a householder account and one staff phone:
   - jobber app: identity photos, guarantor, trusted contact (the code arrives by WhatsApp from the
     staff phone), briefing; then apply to an offer;
   - householder app: accept the applicant, pay from a real mobile-money app, send the reference and a
     gallery screenshot;
   - staff phone: confirm the payment in "Paiements"; check the address appears for the jobber 3 hours
     before the start, and the householder sees the jobber's name and photo;
   - cancel from each side and record the refund; let an unpaid booking expire;
   - the job: "Je suis arrivé(e)" at the door (allow, then refuse, the location), "J'ai terminé",
     "Confirmer que c'est fait"; pay the jobber from the staff app ("Jobs", "À verser") and check
     "Paiement envoyé";
   - staff phone, "Messages": at each step above a message appears; open it, "Ouvrir WhatsApp", and
     check the text arrives written, to the right person, with no address, name, number or reference;
     cancel a booking while its message waits and check it is withdrawn at send; check the badges;
   - a dispute from each side and each of the three decisions, taken in the staff app ("Litiges"); a review from each side, and check
     neither shows before the other is in.
3. **Open a PR to `main`** once 1 and 2 are done (`feat/jobber-verification` first, then
   `feat/staff-operations`).

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
  alerts"). Stage 4 is built on it. Still to settle: who is on duty and at what
  hours, what may wait at night, and the exact wording of each message (mine are in
  `services/messages.py`, to be reread by someone who knows the users).
- **WhatsApp.** How many messages a day one phone can send before WhatsApp restricts the number, and
  whether a person must agree to be written to (wording at enrolment, privacy notice).
- **Real briefing cards.** The three cards seeded by migration `0006` are placeholders; write the real
  ones in the console ("Cartes de briefing") before launch. Decide whether videos are needed.
- **A contact who says "I never agreed".** Contacts can only be replaced, never removed, so define how
  staff take such a number off the list. Staff workload of sending every contact code by hand.
- Guarantor open points: written consent, what staff do when a guarantor does not answer, the call
  script and the number staff call from, bills accepted without a utility bill.

## Build next

End-to-end tests first (the flows of "Before merging", point 2, automated where they can be). Then,
in the order I would take them:

1. Strikes for repeated cancellations and no-shows, shown to staff.
2. Fake-GPS detection at check-in (the distance is recorded but trusts the phone).
3. A message to the jobber when an offer with a booking is withdrawn.
4. Two stage 2 minors: an audit row is written at every view of the booking once the jobber's name is
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
