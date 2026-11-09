# FairPlay DRM — End-to-end setup runbook

The **iOS client is already done** (`FairPlayContentKeyManager` + `FairPlayConfig`,
wired into `LessonPlayerView`). This document is the **backend / ops / Apple**
work needed to turn it on. Order matters — do the steps top to bottom.

Roles: **[Apple]** = Apple Developer portal, **[Backend]** = your API team,
**[Media]** = whoever encodes/packages video, **[iOS]** = already done unless noted.

---

## Step 0 — Prerequisites
- Apple Developer Program membership (**Organization**, not individual).
- An HLS pipeline (you already serve `manifest_url`).
- A device for testing (FairPlay does **not** work on the Simulator).
- Decide the **license-server route** now (Step 2) — it affects Steps 1 & 3.

---

## Step 1 — [Apple] Get FairPlay Streaming (FPS) credentials  *(~1–3 days for Apple approval)*
1. Go to **https://developer.apple.com/streaming/fps/** → request FPS credentials and accept the **FairPlay Streaming Deployment** license agreement.
2. Generate a private key + CSR (Apple's FPS package states the exact key spec — historically 1024-bit RSA / SHA-1 for the FPS CSR):
   ```bash
   openssl genrsa -out fairplay_private.pem 1024
   openssl req -new -sha1 -key fairplay_private.pem -out fairplay.csr \
     -subj "/CN=Droob FairPlay/O=YourOrg/C=SA"
   ```
3. Upload the CSR; Apple issues the **FairPlay Streaming Certificate** (`fairplay.cer`).
4. From the FPS Deployment Package you now hold **all four**:
   - `fairplay.cer` — the **application certificate** (public; the app needs this).
   - `fairplay_private.pem` — your **private key** (server-side, secret).
   - **ASk** (Application Secret Key, 16 bytes) — server-side, secret.
   - **FPS Server SDK** (the “D function” / KSM reference) — for self-hosting.

> Keep the private key + ASk in a secret manager. They never go in the app.

---

## Step 2 — Choose the license server (KSM) route
The KSM is the service that takes an **SPC** (from the device) and returns a **CKC** (the content key). Pick one:

| Route | Effort | Notes |
|---|---|---|
| **DRM vendor** (EZDRM, PallyCon, Axinom, BuyDRM/KeyOS, Verimatrix) | Low — recommended | They host the KSM. You hand them the cert/key/ASk (or they issue creds). You get a license URL + API key. |
| **AWS** (MediaConvert/MediaPackage + **SPEKE** + a SPEKE key provider) | Medium | Good if already on AWS. |
| **Self-host** with Apple FPS Server SDK | High | You run the D-function with the ASk. Most control, most work. |

**Recommendation:** start with a vendor to ship fast; you can self-host later — the iOS client doesn't change.

---

## Step 3 — Stand up the license server (KSM)
- **Vendor:** create a property/asset config, register your FPS cert, note the **license endpoint URL** + auth.
- **Self-host:** wrap the FPS SDK: `CKC = KSM(SPC, ASk, privateKey)`. Expose it internally; your `/license` endpoint (Step 5) proxies to it after the entitlement check.

Output contract regardless of route: **SPC (binary) in → CKC (binary) out.**

---

## Step 4 — [Media] Encrypt & package the videos with FairPlay (SAMPLE-AES)
Re-package each lesson's HLS so it's FairPlay-encrypted and the manifest points at `skd://`.

**Required key line in the variant playlists:**
```
#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://<contentId>",KEYFORMAT="com.apple.streamingkeydelivery",KEYFORMATVERSIONS="1"
```
`<contentId>` is any stable per-asset id (e.g. the lesson id) — the app extracts it and sends it to `/license`.

Example tooling:
- **AWS MediaConvert** job → DRM → **SPEKE** key provider (set FairPlay). Serve via MediaPackage/CloudFront.
- **shaka-packager** (`--protection_scheme cbcs`, `--protection_systems FairPlay`, FairPlay key + `--hls_key_uri "skd://<contentId>"`).
- **Bento4** `mp4hls` with FairPlay options.

Validate the output manifest actually contains the `#EXT-X-KEY ... skd://` line.

---

## Step 5 — [Backend] Add the two endpoints the app already calls
Base URL = `DROOB_API_BASE_URL`. Paths/headers below match the shipped client (adjustable in `FairPlayConfig` if your vendor differs).

### 5a. `GET /v1/student/drm/fairplay/certificate`
- Auth: `Authorization: Bearer <token>`.
- Returns the **application certificate** bytes (`fairplay.cer`, DER) with `Content-Type: application/octet-stream`.
- *(Alternative: skip this endpoint and bundle `fairplay.cer` in the app — then set `bundledCertificateName` and the client uses it.)*

### 5b. `POST /v1/student/drm/fairplay/license`
- Auth: `Authorization: Bearer <token>`.
- Request: body = **raw SPC bytes** (`Content-Type: application/octet-stream`); header `X-Droob-Content-Id: <contentId>`.
- Logic:
  1. Authenticate the token.
  2. **Entitlement check** — confirm this user is enrolled in the course that owns `<contentId>`. **If not → 403 (no key).** ← this is what actually stops piracy.
  3. Forward the SPC to the KSM (vendor URL or self-hosted).
  4. Return the **CKC** — raw bytes, **or** JSON `{"ckc":"<base64>"}` (the client accepts both).

---

## Step 6 — [Backend] Serve the encrypted manifest
The existing `GET /v1/student/courses/{courseId}/lessons/{lessonId}/playback` must return the **FairPlay-encrypted** `manifest_url` (the one with the `skd://` key line) for protected lessons. No app change needed.

---

## Step 7 — [iOS] Confirm config (already wired)
`FairPlayConfig.default` derives the endpoints from `DROOB_API_BASE_URL`:
- cert  → `{base}/v1/student/drm/fairplay/certificate`
- license → `{base}/v1/student/drm/fairplay/license`

If your vendor needs different paths/headers/CKC format, edit `FairPlayConfig.swift` + `FairPlayContentKeyManager.swift` (one place each). To bundle the cert instead of serving it, drop `fairplay.cer` into the app target.

---

## Step 8 — Test (real device)
1. **Sanity-check the client first** with a known-good sample (e.g. Axinom's public FairPlay test stream + their test license URL): temporarily point `FairPlayConfig` at it, confirm playback. This isolates client vs backend issues.
2. Switch to your own encrypted content + your `/license` endpoint.
3. Verify:
   - ✅ Enrolled user → video plays.
   - ✅ Non-enrolled user → `/license` returns 403 → playback fails (expected).
   - ✅ Screen recording / QuickTime-USB / capture card → **video is black** (audio also paused by our capture guard).
   - ✅ HDMI/AirPlay to a non-HDCP sink → **video is black**.
4. Watch Console for `[FairPlay]` logs on errors (e.g. `-1002` = key not obtained → check SPC/CKC round-trip).

---

## Step 9 — Go-live checklist
- [ ] FPS cert + private key + ASk stored in a secret manager.
- [ ] KSM reachable from the API (not the public internet directly if self-hosted).
- [ ] `/license` enforces enrollment entitlement.
- [ ] All protected lessons re-packaged with FairPlay; `playback` returns the encrypted manifest.
- [ ] Tested on a real device across iOS 26 + at least one older iOS.
- [ ] Decide later (optional): **offline/persistent keys** for downloads, and **HDCP TYPE-1** enforcement (server key policy).

---

### Quick reference — the data flow
```
device ──(skd://id)──> app
  app ──GET /certificate──> backend ── returns DER cert
  app ──makeStreamingContentKeyRequestData(cert,id)──> SPC
  app ──POST /license (SPC + contentId + token)──> backend
        backend ─ entitlement check ─> KSM(SPC) ─> CKC
  app <──CKC── backend
  app ──processContentKeyResponse(CKC)──> AVFoundation decrypts (secure path)
```
