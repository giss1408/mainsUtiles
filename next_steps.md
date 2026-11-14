# Next steps

Updated 2026-11-14. Branch `feat/jobber-verification` is pushed up to 684169f.

## What is built

| Piece | State |
|-------|-------|
| Enrolment, householder verification, job offers | Done, on the branch |
| Jobber verification 3a (identity, guarantor) and 3b (trusted contact, safety briefing) | Done; contact codes are sent from the staff app |
| Applications (stage 1): J1 jobbers apply, the householder accepts one | Done |
| Payment and address release (stage 2): manual payment checked by staff, cancel, refund, exact pin, jobber name and photo | Done |
| Staff app payments queue (check a payment, record a refund) | Done |
| **Stage 3: the job and after** (check-in/out, confirmation, payout, disputes, reviews) | **Not started: next** |

Everything is covered by automated tests and the debug APKs build. **Nothing has been tried on a real
phone.** Jobber verification 3a/3b and the applications stage went through a `/code-review`; the
payment stage and the staff payments queue have had a self-review only.

## Before merging

1. **Review the branch.** Run `/code-review` on `feat/jobber-verification`, which now includes the
   payment stage and the staff payments queue.
2. **Try it on real phones**, end to end, with a jobber account, a householder account and one staff phone:
   - jobber app: identity photos, guarantor, trusted contact (the code arrives by WhatsApp from the
     staff phone), briefing; then apply to an offer;
   - householder app: accept the applicant, pay from a real mobile-money app, send the reference and a
     gallery screenshot;
   - staff phone: confirm the payment in "Paiements"; check the address appears for the jobber 3 hours
     before the start, and the householder sees the jobber's name and photo;
   - cancel from each side and record the refund; let an unpaid booking expire.
3. **Open a PR to `main`** once 1 and 2 are done.

## Decisions to take (owner: product)

- **Payment accounts.** Who holds the platform's Wave, MTN MoMo and Orange Money accounts, who is on
  duty to check payments, and how staff compare a payment with the account's real history. A
  screenshot alone is not proof.
- **Legal.** Holding customers' money may need a licence or a partner: a legal review before launch.
  Also the lawful basis for holding a guarantor's and a trusted contact's name and number (privacy
  notice sections "Informations sur votre garant" and "Informations sur votre personne de confiance").
- **Money rules.** The platform fee (0 until decided), and the refund rule for a late cancellation
  (today: full refund).
- **Messages.** SMS or push for "you were accepted", "pay now", "your payment was refused" and "the
  address is available". Today the apps only show the state when opened or refreshed, and many phones
  rarely open an app.
- **Real briefing cards.** The three cards seeded by migration `0006` are placeholders; write the real
  ones in the console ("Cartes de briefing") before launch. Decide whether videos are needed.
- **A contact who says "I never agreed".** Contacts can only be replaced, never removed, so define how
  staff take such a number off the list. Staff workload of sending every contact code by hand.
- Guarantor open points: written consent, what staff do when a guarantor does not answer, the call
  script and the number staff call from, bills accepted without a utility bill.

## Build next

**Stage 3 of piece 4: the job and after** (design:
`docs/superpowers/specs/2026-11-13-applications-and-bookings-design.md`). Needs its own plan. It covers:

- the jobber's check-in ("Je suis arrivé(e)") and check-out ("J'ai terminé"), with the position recorded;
- the householder's confirmation, or an automatic one after `RELEASE_TIMEOUT_HOURS` (24);
- the payout: staff send the jobber `pay_xof` by hand and record the reference (a queue "Paiements à
  verser", in the console and the staff app);
- "Signaler un problème" and disputes (the payout is frozen, staff decide: release, refund or split);
- reviews in both directions, published together, and the rating on the applicant card and the trust line;
- sweeping `checked_in` and `completion_pending` bookings that nobody closes.

Smaller follow-ups, in the order I would take them:

1. Alerts for a payment waiting too long (a late marker exists; nothing pushes it).
2. Strikes for repeated cancellations, shown to staff.
3. Two stage 2 minors: an audit row is written at every view of the booking once the jobber's name is
   shown, and a refused proof returns the booking to "accepted" with its original time, which can leave
   little time to send another.

## Out of scope so far

Tier J2 and commune of service; linked-account detection (a guarantor, bill or phone shared across
accounts) and a banned-guarantor rule; automated guarantor call; real SMS; liveness check; cash with
the QR code; live tracking, the door handshake, the dead-man timer, SOS and chat; recurring offers;
several jobbers on one offer.

## Housekeeping

- Delete the git-ignored `.superpowers/sdd/` workspaces when the final review is done.
- Threat-model rows marked "partly built" or "not built" (reason-for-access prompts, alerts on unusual
  staff volume, screenshot blocking checked on a phone) stay open.
- Deferred minors from the reviews are recorded in each plan's ledger under `.superpowers/sdd/`.
