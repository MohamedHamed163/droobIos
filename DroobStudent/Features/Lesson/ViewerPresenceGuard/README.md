# ViewerPresenceGuard

On-device anti-sharing / anti-recording guard for the course video player. It
uses the front camera to enforce viewing rules while a protected lesson plays,
without ever making playback stutter.

## What it enforces

| Situation | Result |
|---|---|
| 0 faces (sustained past grace) | Pause + soft black overlay ("Are you still there?") |
| Exactly 1 face | Allowed. Identity re-checked periodically (when a model is bundled) |
| 2+ faces (sustained ~2s) | Pause + "multiple viewers detected" overlay |
| Phone/screen in frame | Live "REC?" indicator + alert banner (optionally a block) |
| Always on | Live face-count HUD + moving, semi-transparent watermark of the user's account label (zero ML cost) |

All pauses are **recoverable** — a soft overlay with "Tap to continue", never a
hard stop.

## Performance principle (non-negotiable)

Detection runs on a **tiered cadence, on a background thread, at low resolution
and low frame rate** — never every frame, never on the render/main thread.
The camera delivers ~30 fps; we process ~2 fps and **drop** every backlogged
frame (`alwaysDiscardsLateVideoFrames = true`, the iOS equivalent of CameraX's
`STRATEGY_KEEP_ONLY_LATEST`). Video playback FPS is unaffected.

## Architecture

```
ViewerPresenceGuard (@MainActor)         ← published state, player obs, lifecycle, block latch
  └─ CapturePipeline (queue-confined)    ← AVCaptureSession (front, 640×480)
       ├─ SampleDelegate                 ← frames on a background queue
       └─ FrameProcessor (videoQueue)    ← throttle + tiered pipeline
            ├─ FaceCounter      (Tier 0) ← Vision face rectangles + brightness
            ├─ FaceEmbedder     (Tier 1) ← MobileFaceNet (optional Core ML)
            ├─ LivenessClassifier (1.5)  ← Silent-Face anti-spoof (optional Core ML)
            └─ PresenceStateMachine      ← debounced rolling-window verdict
```

- **Tier 0 — face counting** (Vision, ~2–3 fps): drives the 0 / 1 / 2+ logic.
  Works out of the box, no model download.
- **Tier 1 — identity** (MobileFaceNet): runs only when exactly 1 face, only
  every `identityMatchIntervalSec` (~15–20s). Compares a cosine distance to the
  enrolled embedding.
- **Tier 1.5 — passive liveness** (Silent-Face / MiniFASNet): runs on the same
  face crop as Tier 1, so it costs almost nothing extra. Catches photo/screen
  spoofs.
- **Tier 2 — phone / recording-device detection**: two options —
  - *Model-free (on by default)*: `PhoneScreenDetector` uses Vision's built-in
    `VNClassifyImageRequest` to spot a phone/screen/monitor in frame. No model
    download. Coarse (no bounding box) and can false-positive, so it's
    **debounced** and surfaced as an **alert**, not a hard block, by default
    (`phoneDetectionBlocks = false`).
  - *YOLO (off by default)*: heavier, more precise; `tier2Enabled`.
- **Watermark**: pure SwiftUI, always on, no camera needed.

### Live feedback (visible to the user)

- **`PresenceHUD`** — a small chip on the video showing the live **face count**
  (gray=searching, green=1, red=2+) and a **REC?** indicator when a recording
  device is suspected. Visible while monitoring.
- **`PresenceAlertBanner`** — a transient top banner for non-blocking heads-ups
  ("2 people in view", "Possible recording device detected"); auto-dismisses.
- The engine publishes `faceCount` and `phoneSuspected` for any other UI.

### Debounce (anti false-positive)

Never reacts to one frame. `PresenceStateMachine` uses a rolling window + grace:
no-face needs zero faces in ≥80% of the last 10 samples sustained ≥4s; multiple
faces needs ~2s sustained; wrong-person needs 2 consecutive failed checks.
Sustained zero-face *in low light* yields a gentle `.lowLight` hint instead of a
punitive black-out. Covered by `PresenceStateMachineTests`.

## Integration

One line on the video view (already wired into `LessonVideoPlayer`):

```swift
.viewerPresenceGuard(
    player: player,
    userId: AuthSession.shared.currentUser?.userId ?? "",
    userLabel: AuthSession.shared.currentUser?.email ?? "Droob"
)
```

Tune behaviour with `PresenceGuardConfig` (defaults are the spec's "smooth"
preset). Biggest lever: `sampleFps`.

## Privacy & store compliance

- An explicit **consent screen** (`CameraConsentView`) gates all camera use.
  Declining still lets the lesson play — the watermark stays on.
- `NSCameraUsageDescription` in `Info.plist` is precise about continuous,
  playback-only, on-device use.
- Only the **face embedding** is stored (`FaceEnrollmentStore`), on-device, with
  complete file protection — never a raw image, never uploaded (KSA PDPL / Egypt
  data-protection). It can be cleared on logout / privacy reset.

## Activating the optional ML tiers

Tier 0 (counting) and the watermark work today. The identity/liveness tiers
stay **inactive until you bundle the models** — the app degrades gracefully
(logs once, keeps enforcing counting + watermark). To activate, add these
compiled Core ML models to the app target:

| File in bundle | Tier | Source |
|---|---|---|
| `MobileFaceNet.mlmodelc` (or `.mlpackage`/`.mlmodel`) | 1 — identity | MobileFaceNet, int8, image-in → embedding-out |
| `SilentFaceAntiSpoofing.mlmodelc` | 1.5 — liveness | Silent-Face / MiniFASNet, image-in → 2-class score |

The adapters in `PresenceDetectors.swift` introspect the model's input image
size and output, so no name hard-coding is needed — but validate the exact I/O
once the real converted model is in hand. Rename via
`PresenceModelFactory.identityModelName` / `livenessModelName` if your files
differ.

The **cloud** liveness option (AWS Rekognition Face Liveness) is left as a
config flag (`cloudLivenessEnabled`, default off) for a periodic high-assurance
re-check; it is active/prompted/paid and should not run continuously.
