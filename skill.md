---
name: petitgombo
description: Build and extend petitGombo, a safety-first mini-job marketplace for Côte d'Ivoire (Flutter apps, Django backend). Use for any work on this project - features, data model, payments, identity verification, safety flows, admin tools, tests, or reviews of whether a change weakens the safety model.
---

# Skill: Build "petitGombo"

**Name:** "petitGombo". A "gombo" is West African slang for a side job that brings in extra money ("faire un petit gombo"), understood in Côte d'Ivoire, Cameroon, Burkina Faso and beyond. Android application ids: `com.regisse.petitgombo` (householders), `com.regisse.petitgombo.jobber`, `com.regisse.petitgombo.staff`. The brand speaks to 20 to 30 year olds: informal "tu", short sentences, energetic tone in the jobber app; the householder app keeps the same name with a more neutral "vous". Trademark, domain and store availability are unverified and listed as an open item.
**Tagline:** *Ton petit gombo, près de chez toi.*
**App names:** "petitGombo" (householders), "petitGombo Jobber" (mini-jobbers), "petitGombo Staff" (staff).
**Logo concept:** two hands forming a home outline with a checkmark; warm orange accent, deep green, white background; must stay readable at app-icon size.

## 1. Purpose

petitGombo connects householders in Côte d'Ivoire with nearby young adults (18+) looking for mini-jobs: elderly accompaniment, house cleaning, cooking. The goal is income opportunities for youth **without exposing either side to physical harm**.

Two harms drive every design decision:

- **Harm to the mini-jobber**: a fake or malicious householder uses a listing to lure someone to a location (kidnapping, assault, trafficking, sexual exploitation).
- **Harm to the household**: a jobber, or someone using a jobber's account, uses a booking to learn an address, a layout and a schedule (burglary, home invasion).

The platform cannot make these impossible. It works by **deterrence** (everyone who meets is identified and traceable), **exposure limits** (nobody learns more than the booking requires, and newcomers get low-risk bookings first), and **fast response** (a missed check-out is noticed by a human within minutes). Never write copy, badges or marketing that promise more than that.

## 2. Non-negotiable safety rules

These are invariants. A feature that breaks one is wrong even if it was requested; stop and raise it.

1. **Adults only.** Both roles are 18+, proven by the identity check. No exceptions for "helpers" or siblings.
2. **No meeting without two verified parties.** Both sides hold a verified identity before any booking can be confirmed.
3. **No address without a confirmed booking.** Listings show commune and quartier plus a blurred area (a random offset of several hundred metres, fixed per listing). The exact pin and directions go only to the booked jobber, only once the booking is confirmed (prepaid by mobile money, or cash agreed by a householder whose access fee was paid by mobile money), and only inside a configurable window before the start time.
4. **No booking off the record.** Price, place, time, scope and payment method (mobile money or cash) live in the booking. Any change to place or time after acceptance needs both parties to reconfirm and is flagged for review. Cash is allowed, but it is only counted as paid when the jobber scans the householder's payment QR code (section 6); cash handed over outside a booking is not protected.
5. **Every job has a server-side timer.** Check-in and check-out are expected at known times. Silence triggers the escalation ladder (section 4). Safety must never depend on the phone staying online or on background tracking surviving.
6. **The person at the door is the person in the app.** A door handshake (section 4) confirms both identities at check-in.
7. **Contact details stay hidden.** Chat is in-app; phone numbers, links and handles are filtered and flagged until a booking is confirmed, and off-platform arrangement attempts are a reportable pattern.
8. **Humans decide sanctions; machines can pause.** Automation may freeze a booking or hold an account pending review. Permanent bans and accusations need a human reviewer and an audit record.
9. **Address and identity data are the crown jewels.** Field-level encryption, no bulk export, every staff read logged with a reason. A leaked table of addresses and schedules would itself be a burglary tool.

## 3. Trust tiers

Exposure grows with track record. All thresholds are configuration, not code.

**Mini-jobber**

| Tier | Requirements | Allowed |
|------|--------------|---------|
| J0 | Device enrolled (staff-approved, WhatsApp confirmation) | Browse blurred listings only |
| J1 | ID document + liveness check, confirmed guarantor (see below), trusted contact set, safety briefing completed | Daytime one-off jobs with an adult householder present throughout |
| J2 | J1 + in-person onboarding at a partner point + N completed jobs with good ratings | Recurring jobs, elderly accompaniment, longer shifts |

**Householder**

| Tier | Requirements | Allowed |
|------|--------------|---------|
| H0 | Device enrolled (staff-approved, WhatsApp confirmation) | Draft listings |
| H1 | ID document + liveness, proof of address in the householder's name: water or electricity bill, or certificat de résidence (see below), mobile-money account name matching the ID, home pin captured on site (GPS at the address) | Daytime one-off bookings, short duration |
| H2 | H1 + N completed bookings without upheld reports | Recurring bookings, shifts up to 8 hours |

**Householder proof of address.** This is the main protection against lure listings: a jobber is only ever sent to a home that a utility company ties to the verified householder.

- The householder uploads a photo of one of two documents, each issued within a configurable number of months and showing their name and the address of the home:
  - a water or electricity bill in their name, or
  - a **certificat de résidence** in their name, issued by the competent local authority (mairie or police station). This is a full alternative to the bill, so a tenant or family member who holds one does not need the third-party bill route below. Staff check the issuing authority, stamp, signature and date; if the authority offers a way to verify certificates, use it.
- Verification staff check that the name on the document matches the verified identity document, and that the address on it is consistent with the commune, quartier and the GPS pin captured on site. Bill addresses are often informal (lot, îlot, quartier), so the match is at quartier level and decided by a person, not by exact text comparison.
- Status: `submitted / in_review / confirmed / refused / expired`, renewed after a configurable period. One bill (customer number) or certificate (reference number) can back only one householder account.
- Each additional address a householder wants to post jobs for needs its own bill or certificate and its own on-site pin. A booking can only take place at a confirmed address.
- When the bill is in someone else's name (tenant on the landlord's meter, shared courtyard, family home) and the householder has no certificat de résidence, the householder follows the **third-party bill route**, which needs all of the following:
  1. The bill for the address, plus the bill holder's name, phone and relationship (landlord, parent, spouse, relative).
  2. Staff phone the bill holder, who confirms that the householder lives at that address and agrees to be contacted if a problem arises. The bill holder's phone must not be the householder's own number or device.
  3. Proof of presence: the householder's app confirms their location at the home on several separate days, including at least one evening (counts and spacing are configuration). This shows they live there rather than visited once, and needs no paperwork.
  4. Optional accelerator: a lease or rent receipt in the householder's name replaces the waiting days in step 3. Never make these mandatory, since many rentals are informal.
- Householders confirmed by this route start with tighter limits until a configurable number of bookings complete without an upheld report: shorter jobs, experienced (J2) jobbers only, and a safety-desk call to the jobber at the first check-in.
- A bill holder can confirm several householders at one address (a landlord with many tenants on one meter), up to a configurable cap; staff review anything above it. A bill holder linked to accounts later banned cannot confirm again.
- Accepted document types are configuration (for example a prepaid-meter subscription document). Storage rules are the same as for the guarantor's bill: encrypted, verification staff only, every view logged. Jobbers see only "Adresse confirmée".

**Guarantor (garant).** The local practice: the jobber provides a recent water or electricity bill in the guarantor's name, plus the guarantor's phone number. The guarantor is usually a parent, relative or landlord, and the bill ties them to a fixed address where they can be found. This is the main burglary deterrent.

- The jobber uploads a photo of the bill (issued within a configurable number of months) and enters the guarantor's name, phone and relationship. Accepted document types are configuration, so a prepaid-meter subscription document or similar can be added for households that receive no bill.
- Staff, or an automated call followed by staff review, contact the guarantor on that number to confirm that they know the jobber, confirm the jobber's identity and place of residence, and agree to be contacted if a problem arises. The guarantor needs no app and no account.
- Checks before confirming: the name on the bill matches the guarantor's stated name, the bill is recent and not already used beyond a configurable number of jobbers, and the guarantor's phone is not the jobber's own number or device.
- Guarantor status: `submitted / contacted / confirmed / refused / expired`. Confirmation is renewed after a configurable period. A guarantor linked to accounts later banned cannot vouch again.
- The bill shows a name, address and customer number: store it encrypted, show it only to verification staff, log each view, and never expose it to householders. Householders see only "Garant confirmé".

**Launch constraints (configurable):** jobs between 06:00 and 19:00 only, no overnight stays, no key handover, no jobs requiring travel outside the jobber's declared service area, an adult household member present at check-in and check-out.

## 4. Safety mechanics

**Listing moderation.** Before publication, screen listings automatically and queue doubtful ones for a human: pay far above the category norm, vague duties, requests about age, gender or appearance, mentions of travel, lodging or "abroad", statements that the home will be empty, contact details in text. Jobber gender or photo is never a search filter.

**Selection without a catalogue.** Applicants appear with first name, tier, rating, completed jobs and skills. The jobber's verified photo and full name are released to the householder only on confirmed booking. The jobber sees the householder's tier, rating and completed bookings before applying.

**Trusted contacts.** Each jobber registers at least one friend or parent (up to a configurable number, default two). The contact's phone is confirmed by a code and they accept the role once; they need no app and no account. Without a confirmed contact a jobber cannot be booked.

**Live tracking and location sharing.** The jobber is followed from departure until the task is finished.

- Tracking starts when the jobber taps "Je pars" (or automatically at the address-release time if they have started moving) and stops at check-out, once payment is confirmed. An optional "Je suis bien rentré(e)" extension keeps sharing on until the jobber confirms they are home; on by default for jobs ending near nightfall.
- During the session the app sends location pings from a foreground service with a permanent notification ("Suivi de sécurité actif"). Ping frequency adapts: frequent while travelling, sparse while stationary at the job, to save battery and data. Pings are queued offline and sent when the connection returns.
- At departure each trusted contact receives an SMS with a private link to a follow page on the website: a live map, the booking category and time window, the current status (en route, arrived, on the job, finished), the time remaining, and a button to call the jobber or the safety desk. The link is unguessable, tied to that booking, and expires when the session ends.
- What the contact sees: the jobber's exact position while travelling. Once the jobber has checked in at the home, the page shows "Sur place" with the quartier and the blurred area rather than the exact pin, so that a household's address is not handed to an unverified third party. The exact position and address are revealed to the contact automatically the moment any alert fires. The safety desk sees the exact track at all times.
- Tracking signals that raise an alert on the escalation ladder: the jobber leaves the home's geofence during the job without checking out; the phone falls silent beyond a configurable delay while the timer is running; the jobber moves away from the destination for a sustained period after "Je pars"; the jobber never arrives. Because cheap phones lose signal and firmware kills background work, a single missed ping never alerts by itself; the first step is always a prompt to the jobber.
- The jobber cannot switch tracking off during a booking; turning off location or force-closing the app is itself a signal. Outside bookings the app never tracks. This is explained at sign-up and in a learning video, with explicit consent recorded.
- The householder is told in the booking that the jobber's safety tracking is active during the job.
- Location history is sensitive: stored encrypted, visible only to the safety desk, deleted a configurable number of days after a booking closes without incident, and kept under legal hold when there is one.

**Door handshake.** At arrival the householder's app shows a one-time code or QR; the jobber's app scans it inside the geofence. The jobber's app then takes a selfie matched against the verified face (prevents account lending and substitution). The householder sees the verified photo to compare with the person at the door. Mismatch on either side cancels the booking with no penalty to the party who refused.

**Check-in, check-out, dead-man timer.** Check-in starts a server timer for the booked duration. Shifts over 2 hours get a mid-shift "tout va bien?" prompt. Escalation when check-in, a prompt or check-out is missed (delays configurable):

1. Push notification and in-app alarm to the jobber.
2. Automated SMS and call.
3. Trusted contacts alerted by SMS and call with booking details, exact address and the live or last known location; safety desk calls both parties.
4. Safety desk runs the incident protocol, including handing the booking record to the authorities.

**SOS.** A hold-to-trigger button, available to both roles during a booking, sends location and booking ID to the safety desk and the trusted contact. If there is no data connection, the app sends a pre-formatted SMS instead. A discreet variant (a duress PIN that looks like a normal check-out) raises the same alert silently. Show the locally configured emergency numbers; never imply police are dispatched automatically.

**Account integrity.** One account per identity document; device binding with re-verification on device or SIM change (SIM swap is common); app PIN or biometric to open bookings; Play Integrity / App Attest to hinder emulator farms; alerts on patterns such as many applications with few completions, repeated cancellations after address release, or one device used by several accounts.

**After the job.** Reviews only for completed bookings, both directions, published simultaneously. A "something felt wrong" private report goes to the safety desk without notifying the other party. Address access expires at check-out.

**What the software cannot do.** These are operational prerequisites; document them as open until the business confirms them: a staffed safety desk during all job hours, the guarantor and partner-point network, a written incident protocol and a contact at the police, insurance cover for jobbers and households, and legal review (section 9).

## 5. Product surfaces

- **Householder app**: verification, listings, applicant review, payment, door code, check-out confirmation, reports, reviews.
- **Mini-jobber app**: verification, trusted contact and guarantor, profile and availability, browse and apply, booking status, handshake, check-in/out, SOS, earnings.
- **Operations console (web)**: device enrolment queue, moderation queue, verification review, live board of bookings in progress with timer state, incident handling, disputes and refunds, account holds, audit log.
- **Staff app (mobile)**: the same queues as the console on a phone, for staff who work away from a desk. It starts with the device enrolment queue, where sending the WhatsApp confirmation is one tap because WhatsApp is on the same phone; verification review, guarantor calls, the live board and incident handling are added as those features are built. It is distributed privately to staff, never listed publicly.
- **Public website**: explains the service and hosts the learning videos (see below).

**Website and learning videos.** A public, mobile-first site in French with no login:

- Pages: how it works for householders, how it works for mini-jobbers, safety (what is verified, what is not, how to get help), the guarantor explained for the person asked to vouch, prices, FAQ, download links, terms and privacy, contact.
- An "official channels" page listing the only genuine support numbers and accounts, with the statement that staff never ask for a PIN, a confirmation number or money. This counters fake support agents.
- A learning section ("Apprendre") of short videos (about 1 to 3 minutes) grouped by audience and topic: signing up and verification, providing a guarantor's bill, posting a task, applying, the door handshake, check-in and check-out, paying by mobile money, paying cash with the QR code, using SOS, reporting a problem, plus practical job tips for cleaning, cooking and accompaniment.
- Each video has French captions, a short text summary with screenshots for people who cannot afford the data, and a share link suited to WhatsApp.
- Staff add, order, publish and unpublish videos from the operations console; no release is needed.
- The same video catalogue is served to the apps: the J1 safety briefing is a set of required videos, each followed by a short confirmation question, and help buttons on app screens open the matching video.
- Videos must show the safety steps users follow, not the internal detection rules (moderation patterns, alert thresholds).

Design for the real market: mostly low-end Android phones, costly and patchy data, informal addresses (GPS pin plus landmark description, never a street address form), French first with short sentences, icons and optional audio prompts for users with limited literacy, amounts in XOF.

**Usability rules**

- Sign-up is long (identity, proof of address or guarantor, trusted contact, briefing), so make it a visible checklist with one step per screen, progress saved after every step, and the ability to stop and resume days later. Users can browse while verification is pending.
- The phone number is the account. No email, no password to remember: a device-bound key plus a short app PIN or fingerprint.
- Document capture guides the user: frame overlay, on-device blur and glare detection, and an immediate "photo unreadable, retake" before upload, so that staff rejections are rare. Publish a target time for staff review (configurable, for example under 24 hours) and notify the result by push and SMS.
- Listings are built from category templates: a checklist of duties, duration presets and a suggested pay range. Less typing for the householder, clearer scope for the jobber, and less free text to moderate.
- "Rebook" and favourites: after a completed job, either side can propose working together again in two taps. Repeat pairs are also the safest bookings.
- Large touch targets, one primary action per screen, high contrast readable in sunlight, system font scaling respected.
- Every status is stated in plain words with the next step ("En attente de confirmation du garant. Nous l'appelons sous 24 h."). Errors say what to do, never show codes.
- Offline is a normal state: actions are accepted, shown as "enregistré, envoi dès que possible", and sent automatically. Never lose typed input.
- Critical events (booking confirmed, start reminder, payment, alerts) are sent by push and by SMS, because push is unreliable on many low-end phones.
- Voice notes in chat once a booking is confirmed, for users more comfortable speaking than writing.
- Help is one tap away on every screen: the matching learning video, a call-back request, and the official support line.

## 6. Core flows

**Listing fields:** category, description, quartier and pin, date and start time, duration (accompaniment up to 8 hours), recurrence, pay, household instructions. Remind users not to enter medical details or absence schedules in free text.

**Booking state machine** (enforced in the backend, every transition audited):

`requested → accepted → confirmed → address_released → checked_in → completion_pending → completed`
with side exits `cancelled`, `disputed`, and `safety_hold` (reachable from any active state, exits only by staff action). `confirmed` means prepaid by mobile money, or cash chosen and agreed by both parties.

**Payment by mobile money.** Householder pays through a licensed mobile-money provider when confirming. Release to the jobber follows householder confirmation or a timeout, according to the provider's settlement model. Do not build a wallet or use the word "escrow" unless the provider and the regulator's rules support it. Payment states `pending / successful / failed / refunded / disputed` are handled idempotently; webhooks are signature-verified.

**Payment by cash.** The householder chooses cash when confirming; the amount is fixed in the booking. At check-out the householder's app shows a one-time payment QR code carrying the booking and the amount. The jobber counts the cash, then scans the code inside the geofence: this records `cash_confirmed`, completes the booking and gives both parties a receipt. The code is signed by the server, single use, and works offline with later sync. If the jobber does not scan within a configurable delay after check-out, the booking moves to `disputed` and the householder cannot open new bookings until it is resolved. Cash states: `cash_due / cash_confirmed / cash_disputed`. The platform never handles the cash, so any commission on cash jobs is a business decision to record as open.

**Householder access fee.** A configurable paid plan, with price, renewal and cancellation shown before payment. It is always paid by mobile money, never cash: it filters out throwaway accounts and keeps every householder tied to a named mobile-money account even when their jobs are paid in cash. Do not add a way around it without a decision from the business.

**Disputes and cancellations.** A visible "Signaler un problème" action for both parties; configurable cancellation windows, no-show handling, partial completion and refund rules; a human reviews every dispute.

## 7. Technical approach

A modular monolith. Do not split into microservices.

**Backend (Python)**
- Django 5 + Django REST Framework, OpenAPI schema generated with drf-spectacular. Django is preferred over FastAPI here because the ORM, migrations, permissions, GeoDjango and the admin cover most of the operations console and audit needs out of the box.
- PostgreSQL + PostGIS for geofences, distance search and blurred locations.
- Redis + Celery (with beat) for notifications, webhooks and the safety timers. Timers are rows in the database with a due time, swept by a periodic task, so a worker restart never loses one.
- Apps: `accounts`, `verification`, `listings`, `bookings`, `payments`, `safety`, `messaging`, `moderation`, `audit`, `website`, `learning`.
- Business rules and state machines live here, never in the client.

**Mobile (Flutter)**
- One repository, two apps (householder, jobber) sharing packages for API client (generated from the OpenAPI schema), design system, auth and safety components.
- Riverpod for state, go_router for navigation, a local SQLite cache (Drift) so bookings, the door code and SOS work offline, secure storage for tokens.
- Android first. Build per-ABI APKs to keep downloads small and test on entry-level devices (2 GB RAM).
- A foreground service with a visible notification during a job for location pings. Treat pings as best effort: Tecno, Infinix and Itel firmware kills background work aggressively, which is why rule 5 puts the timer on the server.

**Operations console**
- Start with Django admin (customised) plus a few server-rendered views for the live board. Do not build it in Flutter web.

**Staff app**
- A third Flutter app in the same repository, sharing the core package. It uses a separate staff API (`/api/v1/staff/...`) that calls the same backend services as the console, so rules and audit are identical whichever tool staff use.
- Staff sign in with their identifier and password on a device that an administrator has activated in the web console; the device holds its own key like user devices. Sessions are short, failed sign-ins are rate-limited, and every screen blocks screenshots and screen recording.
- The app shows only what the staff member's permissions allow, and the same staff-access rules apply (reason prompts, second approval, logging). A lost phone is revoked from the web console.
- The web console stays: it is where administrators manage staff accounts, permissions and devices, and it is the fallback when the app is unavailable.

**Public website**
- A `website` Django app with server-rendered templates and light CSS, no JavaScript framework: pages stay small and fast on weak connections, are indexable by search engines, and share the video catalogue with the API (`/api/learning/videos`).
- Host the video files on a video platform rather than on our own servers, so playback adapts to the viewer's connection and bandwidth costs nothing; YouTube is the default candidate. Store only the video reference, title, audience, topic, order, caption and summary. Load the player only when the viewer taps the thumbnail.
- Serve it on the main domain behind a CDN, separate from the API and console hostnames, and keep the console off the public site's navigation.

**Low-bandwidth rules**

- Budgets, measured in CI and treated as failing tests when exceeded (values are configuration): app download size per ABI, data used by a complete booking excluding verification, data used by one hour of tracking, weight of each website page.
- Every write carries an idempotency key and is retried with backoff, so a request repeated on a flaky network never creates a duplicate booking, payment or alert.
- No polling. A push message tells the app to sync; sync is incremental (changes since the last cursor), compressed, paginated in small pages, with conditional requests so unchanged data costs almost nothing. Chat uses the same mechanism rather than a permanent socket.
- Photos are compressed on the device to a legible target size before upload, and uploads are resumable in chunks so a dropped connection does not restart them. Thumbnails are served small and in a modern format.
- Choose the identity provider partly on data cost: prefer still-image liveness and on-device capture over video streaming, and measure the megabytes a full verification consumes.
- Maps are the heaviest screen. Show the blurred area as one small static image; cache the tiles around a booked job in advance; for navigation hand over to the maps app already on the phone. The trusted contact's follow page has a text-only status that works when the map cannot load.
- Location pings are batched into compact payloads.
- Videos never autoplay, show their size before playing, and always have the text-and-screenshot alternative. A "mode économie de données" setting turns off images and map tiles outside bookings.
- No custom fonts, no heavy animation or image assets in the apps; the website uses no JavaScript framework and no web fonts.

**Provider adapters** (each behind an interface, with a mock for development)
- `PaymentProvider`: collection, payout, refund, webhook verification. Candidates to evaluate: Wave, Orange Money, MTN MoMo, Moov Money directly, or an aggregator such as CinetPay, Hub2, PayDunya or Paystack.
- `IdentityProvider`: document check, liveness, face match. Candidates: Smile ID, or the national identity office (ONECI) verification service.
- `MessagingProvider`: WhatsApp enrolment confirmations (manual send at first), notification and alert SMS, automated calls, with a second route for failover; FCM for push.
- `MapProvider`: OpenStreetMap tiles via MapLibre by default to avoid per-request map costs.

Confirm availability, pricing and contract terms with each provider before treating it as real; until then ship against the mock and list it as an open item.

**Later, not in the first release:** a USSD or WhatsApp channel for jobbers without a smartphone, masked voice calls, iOS release, additional languages.

## 8. Security and privacy

- **Device enrolment is approved by staff and confirmed over WhatsApp.** No device gets access automatically:
  1. The user enters their phone number in the app. The app creates an enrolment application carrying the number, device model and identifier, integrity-check result, approximate location, and whether this is a new account or a new device for an existing one.
  2. The application appears in the enrolment queue of the operations console. Staff review it; a new device for an existing account also requires a fresh selfie match before it can be approved.
  3. On approval the console generates the confirmation number (staff never choose it). The staff member sends it manually from the official WhatsApp Business number, using a "send by WhatsApp" button that opens the chat with the message prefilled. The console records who approved, who sent, and when.
  4. The user types the number into the app, which binds the device. The number is single use, valid only for that device and application, expires after a configurable delay, and locks after a few wrong attempts.
  - Applications can be refused or held with a reason; the user sees a plain status ("Demande reçue, confirmation par WhatsApp sous X h") and the published response time for staffed hours.
  - Limit applications per phone number, per device and per network; flag one device applying for several numbers.
  - The message states that staff never ask for this number back and that it must not be shared. The official WhatsApp number is listed on the website's official-channels page.
  - Fallback for a user without WhatsApp is configurable: a manual SMS or a call from the official number, logged the same way.
  - Keep the sending step behind the `MessagingProvider` interface so that it can later be automated through the WhatsApp Business API without changing the approval step.
- Short-lived access tokens with rotating refresh tokens bound to the device, rate limits on login.
- Role and ownership checks on every endpoint; object-level permission tests for every resource.
- Field-level encryption for addresses, pins, identity attributes and trusted-contact numbers, with keys in a managed secret store.
- Identity documents and selfies stay with the identity provider where possible; store the result, a reference and the face template only if the legal basis is confirmed.
- Staff access by role, with two-factor authentication, reason-for-access prompts on addresses and identity data, no bulk export, and alerts on unusual read volume.
- No PINs, passwords, tokens, documents or exact coordinates in logs.
- Defined retention: location pings deleted a set number of days after a booking closes without incident; identity data deleted on account closure subject to legal holds.
- The WhatsApp confirmation number is used only to enrol a device and to recover an account. Daily sign-in uses a key bound to the device plus the app PIN or fingerprint. Recovery on a new device or SIM requires a fresh selfie match, and sensitive changes (payout number, trusted contact, guarantor) have a cooling-off delay with notice sent to the old number.
- Fake GPS apps are widespread and would defeat the geofence, proof of presence and tracking. Detect mock-location settings, rooted devices and emulators; cross-check GPS against network location; treat a failed check as a signal for review, and never accept check-in or proof of presence from a device that fails it.
- Documents (identity, bills, certificates) are captured with the in-app camera only, never picked from the gallery, with capture time and location recorded. Detect reuse of the same image or the same customer or reference number across accounts. The liveness check must resist photos, screens and synthetic faces; require independent test evidence from the provider.
- Door and payment QR codes are signed, bound to the booking and to both devices, valid for a short time and rotated on screen, so a screenshot sent to someone else is useless. Keys for offline checking are delivered at address release. Screens showing an address or a code block screenshots and screen recording.
- Ratings and tier progress count only bookings between unrelated accounts. Accounts that share a device, guarantor, bill, payment number or trusted contact are linked, and bookings between linked accounts do not build trust. Limit how many addresses a jobber can have released per week, and count cancellations made after release.
- Four-eyes rule in the console: revealing an address or location track outside an active incident, lifting a safety hold, overriding a tier, and changing a payout number each need a second staff member's approval. Console access requires strong two-factor sign-in and is restricted by network.
- Calls to guarantors and bill holders come from the published official number, follow a script, and never disclose the user's data to the person called.
- Follow links for trusted contacts are long random tokens, rate-limited, excluded from search engines, revocable, and every access is logged.
- Engineering hygiene: dependency and secret scanning in CI, certificate pinning and code obfuscation in release builds, encrypted backups with a tested restore, key rotation, an independent penetration test before launch, a written breach-response plan, and a public address for reporting vulnerabilities.
- Threat model kept in the repository and updated with each feature. It must cover: lure listings, account lending, address harvesting, collusion between accounts, forged or reused documents, fake GPS, relayed QR codes, SIM swap and account takeover, fake support agents and cloned apps, payment fraud, harassment, data breach and insider misuse.

## 9. Legal and compliance items to confirm

Do not assume; list each as open in the setup documentation until the business supplies an answer.

- Data protection: registration or authorisation with the regulator (ARTCI) under the personal-data law, especially for biometric processing and for hosting outside the country.
- Payments: whether holding funds between collection and payout needs a licensed partner under the regional central bank's rules.
- Labour: status of jobbers, minimum pay, rules on domestic work.
- Emergency numbers and the police contact used in the incident protocol.
- Insurance for jobbers and households.

## 10. Data model

`User`, `Device`, `DeviceEnrolmentRequest`, `IdentityVerification`, `HouseholderProfile`, `JobberProfile`, `TrustTier`, `Guarantor`, `TrustedContact`, `HomeLocation`, `TaskListing`, `Application`, `Booking`, `BookingEvent`, `CheckIn`, `TrackingSession`, `LocationPing`, `FollowLink`, `SafetyTimer`, `SafetyAlert`, `Incident`, `Payment`, `Payout`, `Subscription`, `Dispute`, `Review`, `Message`, `Report`, `ModerationDecision`, `AddressAccessLog`, `AdminAction`, `LearningVideo`, `VideoCompletion`, `SitePage`.

## 11. Build order

Work in small, reviewable increments. Before each one, state assumptions and which safety rules it touches.

1. Repository layout, CI, threat model document, provider interfaces with mocks.
2. Accounts: device enrolment applications, console enrolment queue with WhatsApp confirmation, device binding, roles, permissions.
3. Verification and trust tiers, trusted contact, guarantor.
4. Listings with blurred location and the moderation queue.
5. Applications and the booking state machine.
6. Payments: mobile money in sandbox or mock mode, and cash with QR confirmation.
7. Address release, door handshake, check-in/out, live tracking with the trusted-contact follow page, safety timers, escalation ladder, SOS with SMS fallback.
8. Operations console: live board, incidents, disputes, audit.
9. Reviews, reports, messaging filters.
10. Public website and learning videos, including the in-app safety briefing and help links.
11. Launch hardening: low-end device testing, offline behaviour, load test of the timer sweep, setup and operations documentation.

There is no pilot phase. The product launches openly and evolves in production: service zones, tier thresholds, time limits, escalation delays and fees are all configuration that staff can change without a release, and every release must be safe to ship to all users. Add feature flags and basic product metrics (sign-ups, verification drop-off, bookings, alerts, disputes) from the start so changes are driven by real use.

**Never** invent provider credentials, claim an integration works without testing it, or bypass a safety rule to make a demo flow shorter. If a decision or credential is missing, build the labelled mock and record what is needed.

## 12. Definition of done

- Main flows work end to end in a test environment for both apps.
- Automated tests cover: permission failures on every resource, every booking transition including invalid ones, address never present in any response before `address_released`, timer escalation at each step including after a worker restart, SOS over data and over SMS, tracking (follow link expiry, exact address hidden from the contact until an alert, geofence exit alert, offline ping queue, no tracking outside a booking), duplicate and out-of-order payment webhooks, cash QR confirmation (reuse, wrong booking, outside geofence, offline sync, unscanned timeout), tier limits, retried writes creating no duplicates, mock-location rejection at check-in, expired or relayed QR codes, linked accounts not building trust, four-eyes actions refused without a second approver.
- The low-bandwidth budgets pass in CI, and the main flows have been run on an entry-level phone over a throttled 2G/3G connection.
- The threat model is current, and each of the nine safety rules maps to at least one test.
- Setup documentation lists every integration, configuration value, and open operational or legal decision.
