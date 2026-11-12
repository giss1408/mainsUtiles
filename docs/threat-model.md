# petitGombo threat model

Kept current with each feature. Status values: `planned` (designed in the spec, not built),
`built` (code exists), `tested` (automated tests named in the last column).

The two harms that drive the design: a mini-jobber lured to a location (kidnapping, assault,
trafficking), and a household whose address and schedule are learned through a booking
(burglary, home invasion). Controls work by deterrence, exposure limits and fast response;
none of them makes harm impossible.

## Threats

| Threat | Who is harmed | Controls (spec safety rules) | Status | Tests |
|--------|---------------|------------------------------|--------|-------|
| Lure listings | Mini-jobber | Verified householder with proof of address (rule 2); address only for a confirmed booking (3); listing moderation; trusted contacts, tracking and server timer (5) | planned | |
| Account lending or substitution | Household | Door handshake with selfie match (6); one account per identity document | planned | |
| Address harvesting | Household | Blurred listings, address released only to the booked jobber and expiring at check-out (3); weekly release limits; address access log (9) | planned | |
| Collusion between accounts | Both | Linked accounts do not build trust; ratings only between unrelated accounts | planned | |
| Forged or reused documents | Both | In-app camera capture only; reuse detection on images and customer numbers; staff review | planned | |
| Fake GPS | Both | Mock-location, root and emulator detection; network cross-check; `integrity_verdict` recorded at enrolment | planned | |
| Relayed QR codes | Both | Signed, short-lived, device-bound, rotating codes; screenshot blocking | planned | |
| SIM swap and account takeover | Both | Staff-approved device enrolment with a single-use WhatsApp confirmation number; sign-in with a device-bound key; rotating refresh tokens; one active device per account | tested | `test_enrolment_service.py` (all), `test_device_auth.py` (all), `test_full_flow.py` |
| Fake support agents and cloned apps | Both | "Staff never ask for this number" wording in every confirmation; official-channels page | planned | |
| Payment fraud | Both | Idempotent payment states; signed webhooks; cash confirmed by QR scan | planned | |
| Harassment | Both | In-app chat with contact filtering (7); block and report; human review (8) | planned | |
| Data breach | Both | Field-level encryption for addresses and identity data (9); no secrets or codes in logs; hashes only for codes and tokens | planned | |
| Insider misuse | Both | Role permissions; append-only audit of staff actions; no bulk export; second approval for sensitive actions (9) | planned | |

## Safety rules and their tests

Each of the nine rules in `skill.md` section 2 must map to at least one automated test before launch.

| Rule | Tests |
|------|-------|
| 1. Adults only | |
| 2. No meeting without two verified parties | |
| 3. No address without a confirmed booking | |
| 4. No booking off the record | |
| 5. Every job has a server-side timer | |
| 6. The person at the door is the person in the app | |
| 7. Contact details stay hidden | |
| 8. Humans decide sanctions; machines can pause | |
| 9. Address and identity data are the crown jewels | |
