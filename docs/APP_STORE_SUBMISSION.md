# Droob iOS — App Store submission runbook

Status legend: ✅ done in the project · ⚠️ **must fix before submit** · ☐ to do in App Store Connect / externally.

---

## PART A — Blockers to fix IN THE APP first (these cause rejection)

### A1. ⚠️ In-App Purchase for course sales — Guideline 3.1.1 (BIGGEST risk)
The app sells courses via an **external checkout** (no StoreKit found). Apple requires **In-App Purchase** for digital content consumed inside the app. External payment for courses → **rejected**.
Options:
- Implement **StoreKit 2 IAP** for course purchases/subscriptions (most likely required), **or**
- Restructure as a qualifying **"reader" app** (no in-app buying/CTA at all; purchases happen on your website with no link) — strict, and you lose in-app buying, **or**
- Confirm with Apple if a regional exception applies (rare).
👉 Decide this first — it shapes the whole payments flow.

### A2. ⚠️ Account deletion — Guideline 5.1.1(v) (guaranteed rejection if missing)
The app creates accounts but has **no in-app "Delete my account"**. Apple requires it to be in-app and reachable. Add a Delete Account action (Profile → Settings → Security/Account) that calls a backend delete endpoint and signs out.

### A3. ⚠️ Camera-required gate — Guideline 5.1.1
We currently **block the video if camera access is denied** (`requireCameraToView = true`). Apple often rejects apps that withhold core functionality when a permission is declined. Safer:
- Let the lesson still play with the **watermark only** when camera is denied (set `requireCameraToView = false`), **or**
- Keep it but be ready to **justify in review notes** that monitored viewing is the core, contracted feature. Risky — recommend the graceful fallback.

### A4. ✅ Privacy Manifest — `PrivacyInfo.xcprivacy` (DONE)
Created + bundled. Declares: no tracking, collected types (email/name/userID/purchases/usage/user-content), and the UserDefaults required-reason API. **Verify each collected type matches your backend** and keep it identical to the App Store Connect privacy answers.

### A5. ✅ Sign in with Apple (DONE) — required because Google sign-in is offered (4.8).

---

## PART B — Apple Developer / App Store Connect setup

### B1. ☐ Program & agreements
- Apple Developer Program (Organization) active.
- **Paid Apps Agreement** signed in ASC → Business (required to sell, even via IAP) + banking/tax filled in.

### B2. ✅ Identifiers / signing
- Bundle ID `sa.droob.studentapp`, Team `97DNR5Y3Y5`. Signing handled by **fastlane match** (App Store profile) — already configured.
- If you add IAP/other capabilities, enable them on the App ID and re-run `match`.

### B3. ☐ Create the app record in App Store Connect
- My Apps → + → New App → iOS → name, primary language, bundle ID, SKU.
- Category: **Education**. Set content rights + age rating (see D4).

---

## PART C — App Privacy & review (heaviest scrutiny for THIS app)

### C1. ☐ App Privacy questionnaire (ASC → App Privacy)
Answer it to **match `PrivacyInfo.xcprivacy`**: collected = email, name, user ID, purchases, product interaction, user content; **not** used for tracking. 
Important: the **front-camera / face data is processed on-device and never leaves the device**, so it is **not "collected"** in Apple's sense — but be ready to explain that.

### C2. ☐ Privacy Policy URL (required)
Must be live and must explicitly cover: continuous front-camera monitoring during protected videos, on-device face embedding (stored locally, deletable, never uploaded), and KSA PDPL / Egypt data-protection handling.

### C3. ☐ Review Notes (App Review Information) — write these carefully
- **Demo account (REQUIRED):** the app is login-gated → provide a working email + password (and a course already enrolled so the reviewer can reach a protected video).
- **Camera justification:** "The front camera is used only while a protected course video plays, on-device, to confirm a single enrolled viewer and deter piracy. Processing is on-device; no images/video are stored or transmitted. Gated behind an explicit consent screen."
- Note the **jailbreak block** and **screen-recording protection** so the reviewer isn't surprised by black frames during their own screen recording.

---

## PART D — Store listing metadata & assets

- **D1. ☐ Screenshots** — required per device: **6.9"/6.7" iPhone** and, because the app is **universal (iPad)**, **13" iPad** screenshots too. (No iPad screenshots = can't submit for iPad.)
- **D2. ☐ Description, keywords, promotional text, support URL** (required), marketing URL (optional).
- **D3. ✅ App icon** — 1024 + all sizes present.
- **D4. ☐ Age rating** questionnaire.
- **D5. ☐ Export compliance** — `ITSAppUsesNonExemptEncryption = false` is set (HTTPS/standard crypto only). With FairPlay later it's still exempt, but re-confirm the answer at submit.
- **D6. (note)** Deployment target is **iOS 26** → only iOS 26 devices can install. That's allowed but it shrinks your audience a lot; consider lowering (e.g., 16–17) for reach.

---

## PART E — Build & upload

1. Version/build: `MARKETING_VERSION = 1.0`, build auto-incremented by fastlane.
2. Set the **release** API base if needed (currently `https://api.droob-sa.net`).
3. Upload to TestFlight (already wired): `bundle exec fastlane beta` with the App Store Connect API key + `match` env vars, **or** push to `main` (GitHub Actions `testflight.yml`).
4. Let the build finish processing in ASC, then attach it to the version.

---

## PART F — Submit for review
1. ASC → your version → add screenshots, description, privacy, build, age rating, export compliance.
2. Add the **demo account** + **review notes** (Part C3).
3. Submit. Expect questions about the camera and payments — the review notes pre-empt them.

---

## One-page checklist
- [ ] ⚠️ Course purchases via **StoreKit IAP** (or qualifying reader-app model)
- [ ] ⚠️ **Delete account** in-app
- [ ] ⚠️ Camera-denied **graceful fallback** (or justification)
- [x] Privacy Manifest bundled
- [x] Sign in with Apple
- [x] App icon, version, signing, encryption flag, no background camera
- [ ] Privacy Policy URL (camera + face wording)
- [ ] App Privacy answers match the manifest
- [ ] iPhone **and** iPad screenshots
- [ ] Demo account + review notes (camera + recording-block + jailbreak)
- [ ] Paid Apps Agreement + banking/tax
- [ ] Upload via fastlane → submit
