# Next steps

State on `feat/jobber-verification`: jobber verification 3a (identity, guarantor), 3b (trusted
contact, safety briefing) and piece 4 stage 1 (applications and accepting one applicant) are
implemented and green. Nothing has been tried on a
real phone, and no reviewer other than the author has read the branch.

## Before merging

1. **Review the branch.** Run `/code-review` on `feat/jobber-verification`. 3b had a self-review only.
2. **Try it on real phones.** Install the staff app on the official-number phone and the jobber debug APK and go through all four steps: identity
   photos with the in-app camera, guarantor, adding a trusted contact, entering the code, the briefing.
   Then replace a confirmed contact and check the notice and the 72 h delay in the console.
3. **Open a PR to `main`** once 1 and 2 are done.

## Decisions to take (owner: product)

- **WhatsApp sending.** Decided and built: messages are sent from the staff app, on the device that
  holds the official number (the console link stays as a fallback). Check on a real staff phone.
- **Staff workload** of sending every contact code by hand, and who is on duty.
- **Real briefing cards.** The three cards seeded by migration `0006` are placeholders; write the real
  ones in the console ("Cartes de briefing") before launch. Decide whether videos are needed.
- **Lawful basis** for holding a guarantor's and a trusted contact's name and number (lawyer review of
  the privacy notice sections "Informations sur votre garant" and "Informations sur votre personne
  de confiance").
- **A contact who says "I never agreed".** Contacts can only be replaced, never removed, so define how
  staff take such a number off the list.
- Guarantor open points: written consent, what staff do when a guarantor does not answer, the call
  script and the number staff call from, bills accepted without a utility bill.

## Build next

- **Applications and bookings, stage 2 of 3: payment and address release** (design:
  `docs/superpowers/specs/2026-11-13-applications-and-bookings-design.md`). The householder pays the
  platform first by mobile money (a mock provider behind `PaymentProvider`), the booking becomes
  `confirmed`, the exact address is released shortly before the start, and either side can cancel.
  Needs its own plan. Today an accepted booking waits for a payment that cannot be made yet.
- **Stage 3:** check-in and check-out, householder confirmation, payout to the jobber, disputes in
  the console, reviews and ratings.
- **Before launch (business):** the payment provider and its settlement model, the platform fee, the
  late-cancellation rule, and SMS or push for "you were accepted" and "pay now".
- **Out of scope so far:** tier J2 and commune of service, linked-account detection (shared guarantor,
  bill or phone across accounts) and a banned-guarantor rule, automated guarantor call, real SMS,
  liveness check, cash with the QR code, live tracking, the door handshake, SOS, chat.

## Housekeeping

- Delete the git-ignored `.superpowers/sdd/` workspaces when the final review is done.
- Threat-model rows marked "partly built" or "not built" (reason-for-access prompts, alerts on unusual
  staff volume, screenshot blocking on a phone) stay open.
