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
| Lure listings | Mini-jobber | Verified householder with proof of address (rule 2); address only for a confirmed booking (3); listing moderation; trusted contacts, tracking and server timer (5) | partly built | Householder verification is built: identity, proof of address in the householder's own name and a home position recorded on site, each confirmed by staff (`test_verification_review.py`, `test_verification_console.py`). Job offers are built: only H1 householders at a confirmed address can publish; screening signals and human review; every householder's first offer is reviewed; no contact path yet (`test_offer_screening.py`, `test_offer_service.py`, `test_offer_moderation.py`). Not built: applications, bookings, tracking and timers
| Lure aimed at a jobber's identity | Mini-jobber | A jobber must pass identity photos and a guarantor before tier J1; staff compare the selfie with the document; statuses only in the API | partly built | Identity and guarantor review built (`test_jobber_tier.py`, `test_jobber_verification_api.py`, `test_guarantor_review.py`). Not built: liveness, applications gated on J1 |
| Forged guarantor bill | Both | Photo taken in the app only; the bill must be under 3 months old; staff call the guarantor and compare the holder's name | tested | `test_guarantor_submissions.py`, `test_guarantor_review.py` (age, name match, call required) |
| Guarantor's phone is the jobber's own number | Both | The number is normalised (`+225…`, `00225…`, spaces) and compared with the jobber's; refused as `guarantor_phone_own` | tested | `test_guarantor_submissions.py` (`test_guarantor_phone_same_as_jobber_is_refused_in_any_format`) |
| One bill backing many jobbers | Both | A bill reference may back at most `GUARANTOR_MAX_JOBBERS` jobbers, expired guarantors included; compared by keyed hash | tested | `test_guarantor_review.py` (`test_reference_cap_counts_expired_and_other_users_only`) |
| Insider reads guarantor data | Both | Name, phone and bill reference encrypted; the bill photo is served only through a permission-checked console view; every view and call is audited; the API never returns them | partly built | `test_guarantor_console.py`, `test_jobber_verification_api.py` (`test_response_never_contains_guarantor_name_phone_or_photo`). Not built: reason-for-access prompts, alerts on unusual read volume |
| WhatsApp spam to a third party's number | Third party | A jobber can only ask for a code; staff send it. At most `TRUSTED_CONTACT_MAX_ADDS_PER_DAY` contacts (replacements included) per day and one request at a time | tested | `test_trusted_contacts.py` (`test_adds_per_day_cap_counts_replaced_contacts`, `test_request_code_waits_while_staff_have_not_sent_and_then_for_the_delay`) |
| Guessing the confirmation code | Both | 6 digits, locked after `TRUSTED_CONTACT_CODE_MAX_ATTEMPTS` wrong tries until staff send a new code; code valid `TRUSTED_CONTACT_CODE_TTL_MINUTES`; only its hash is stored | tested | `test_trusted_contacts.py` (`test_wrong_code_counts_attempts_then_locks_until_a_new_code`, `test_expired_code_refused`) |
| Trusted contact is the jobber or the guarantor | Both | The number is compared in any format with the jobber's own and the guarantor's; refused | tested | `test_trusted_contacts.py` (`test_own_phone_is_refused_in_any_format`, `test_guarantor_phone_is_refused_in_any_format`) |
| Swapping trusted contacts to evade the check | Both | A contact is never removed, only replaced; the replacement is confirmed by the same code; the old one counts until staff warned its number and the delay passed | tested | `test_trusted_contacts.py` (`test_replacing_a_confirmed_contact_keeps_it_until_...`, `test_no_service_removes_a_contact`) |
| Insider reads a trusted contact's data | Both | Name and number encrypted; staff see the name, and the number only inside the one-time WhatsApp link; each view and send is audited; the API never returns the number or the code | partly built | `test_trusted_contact_console.py`, `test_jobber_contacts_briefing_api.py` (`test_no_response_contains_a_phone_a_code_or_the_answer_key`). Not built: reason-for-access prompts, alerts on unusual volume |
| Briefing answered by guessing or copied | Mini-jobber | A wrong answer shows why but nothing is learned about the key from the cards API; the briefing is a safety lesson, not a gate against a determined jobber | built | `test_briefing.py` (`test_cards_never_expose_the_answer`) |
| Account lending or substitution | Household | Door handshake with selfie match (6); one account per identity document | planned | |
| Address harvesting | Household | Blurred listings, address released only to the booked jobber and expiring at check-out (3); weekly release limits; address access log (9) | partly built | Offers expose the commune and quartier only, never the address, position, name or phone number (`test_offers_api.py`, `test_my_offers_api.py`). Not built: address release at booking, weekly limits, access log |
| Collusion between accounts | Both | Linked accounts do not build trust; ratings only between unrelated accounts | planned | |
| Forged or reused documents | Both | In-app camera capture only; reuse detection on images and customer numbers; staff review | partly built | Built: photos taken only with the in-app camera; the same image on two accounts is flagged; one identity document number and one bill or certificate number per account, compared without case or punctuation; under-18 and expired documents refused (`test_verification_submissions.py`, `test_verification_review.py`). Not built: liveness, automatic document checks; a person compares the selfie with the document |
| Fake GPS | Both | Mock-location, root and emulator detection; network cross-check; `integrity_verdict` recorded at enrolment | planned | |
| Relayed QR codes | Both | Signed, short-lived, device-bound, rotating codes; screenshot blocking | planned | |
| SIM swap and account takeover | Both | Staff-approved device enrolment with a single-use WhatsApp confirmation number; sign-in with a device-bound key; rotating refresh tokens; one active device per account | tested | `test_enrolment_service.py` (all), `test_device_auth.py` (all), `test_full_flow.py` |
| Fake support agents and cloned apps | Both | "Staff never ask for this number" wording in every confirmation; official-channels page | built | `test_enrolment_screens_test.dart` (code screen note); official-channels page not built yet |
| Payment fraud | Both | Idempotent payment states; signed webhooks; cash confirmed by QR scan | planned | |
| Harassment | Both | In-app chat with contact filtering (7); block and report; human review (8) | planned | |
| Data breach | Both | Field-level encryption for addresses and identity data (9); no secrets or codes in logs; hashes only for codes and tokens | partly built | Built: identity photos, names, dates of birth, document numbers and home positions are encrypted with `FIELD_ENCRYPTION_KEY`; photos are served only through a permission-checked console view that logs every view; the householder API never returns them (`test_encryption.py`, `test_verification_api.py`, `test_verification_console.py`). Not built: key rotation, reason-for-access prompts, second-staff approval, alerts on unusual read volume |
| Insider misuse | Both | Role permissions; append-only audit of staff actions; no bulk export; second approval for sensitive actions (9) | planned | |
| Stolen staff password | Both | Staff sign in with a password and a phone activated by an administrator; one active phone per staff member; lock after 5 wrong passwords; 10-minute access tokens; staff phones revocable from the console | tested | `test_staff_api.py` (all) |
| Leak of numbers from a staff phone | Both | Staff app blocks screenshots and screen recording; the WhatsApp link with the confirmation number is opened and dropped, never shown, stored or logged; tokens in memory only | built | `screens_test.dart` (WhatsApp send), `staff_controller_test.dart` (nothing written to storage); screenshot blocking not checked on a phone |
| Dodging enrolment limits with a forged network address | Both | Client address taken from the reverse proxy's own `X-Forwarded-For` entry, only when `TRUST_PROXY_HEADERS=1`; application port not published | tested | `test_production_settings.py` |

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
