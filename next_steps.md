# Next steps

State at c2e734d on `feat/jobber-verification` (pushed): jobber verification 3a (identity, guarantor)
and 3b (trusted contact, safety briefing) are implemented and green. Nothing has been tried on a
real phone, and no reviewer other than the author has read the branch.

## Before merging

1. **Review the branch.** Run `/code-review` on `feat/jobber-verification`. 3b had a self-review only.
2. **Try it on a real phone.** Install the jobber debug APK and go through all four steps: identity
   photos with the in-app camera, guarantor, adding a trusted contact, entering the code, the briefing.
   Then replace a confirmed contact and check the notice and the 72 h delay in the console.
3. **Open a PR to `main`** once 1 and 2 are done.

## Decisions to take (owner: product)

- **WhatsApp sending.** Decided: messages are always sent from the admin app, on the device that holds
  the official number. Still to decide: is that the web console on that device (what is built now:
  a one-time `wa.me` link) or the Flutter staff app, which already opens WhatsApp for device
  enrolment? The second is a new task.
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

- **Staff-app sending of contact codes** (if chosen above): staff app lists "À envoyer" and "À prévenir",
  opens WhatsApp with the written message, never shows or stores the number. Needs a plan.
- **Applications and bookings**, which will enforce J1 (nothing enforces it today; the tier is only
  computed and shown). This is the next big plan.
- **Out of scope so far:** tier J2 and commune of service, linked-account detection (shared guarantor,
  bill or phone across accounts) and a banned-guarantor rule, automated guarantor call, real SMS,
  liveness check, payment.

## Housekeeping

- Delete the git-ignored `.superpowers/sdd/` workspaces when the final review is done.
- Threat-model rows marked "partly built" or "not built" (reason-for-access prompts, alerts on unusual
  staff volume, screenshot blocking on a phone) stay open.
