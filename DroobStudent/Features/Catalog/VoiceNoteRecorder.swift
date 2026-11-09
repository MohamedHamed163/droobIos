import AVFoundation
import Foundation

// MARK: - VoiceNoteRecorder
//
// Thin wrapper around AVAudioRecorder for chat voice notes. Records AAC
// inside an MP4 container — that's what the backend's allow-list
// matches (audio/mp4 / audio/m4a) and what AVFoundation produces by
// default with the constants below.
//
// State machine:
//   .idle   — no recording in progress, file not yet written
//   .recording — currently writing samples to `recordingURL`
//   .finished(data, durationSeconds) — recording closed; bytes ready
//
// The recorder takes care of permission prompting; the host view shows
// a permission-denied alert when `start()` returns `false`.

@MainActor
final class VoiceNoteRecorder: NSObject, ObservableObject {
    /// Elapsed seconds since `start()` — drives the live timer label
    /// on the composer's recording bar. Reset on each new recording.
    @Published var elapsed: TimeInterval = 0
    @Published var isRecording: Bool = false
    /// Last completed recording — populated by `stop()`. Cleared on the
    /// next `start()` or by the host after upload.
    @Published var finished: VoiceNoteRecording?
    @Published var permissionDenied: Bool = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var tickerTask: Task<Void, Never>?
    /// Resumed by `audioRecorderDidFinishRecording` so `stop()` only reads
    /// the file *after* AVAudioRecorder has finished writing the MP4
    /// container's trailing `moov` atom. Reading before that finalization
    /// completes yields a truncated, undecodable clip — the root cause of
    /// voice notes that upload "successfully" but never play back.
    private var finishContinuation: CheckedContinuation<Void, Never>?

    /// Filename for the audio part. Backend uses this for the chip
    /// label / S3 key suffix — sender-supplied filename is sanitised
    /// server-side so the format here doesn't need to be defensive.
    private static func newRecordingURL() -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let stamp = Int(Date().timeIntervalSince1970)
        return tmpDir.appendingPathComponent("voice-\(stamp).m4a")
    }

    /// Async entry — requests microphone permission if needed, then
    /// opens AVAudioSession and starts the recorder. Returns `false`
    /// when the user denied mic access so the host can show a settings
    /// link.
    func start() async -> Bool {
        let granted = await requestPermission()
        if !granted {
            permissionDenied = true
            return false
        }
        permissionDenied = false
        // Tear down any previous recording state — handles the case
        // where the user records, dismisses, then records again
        // without uploading.
        cleanupRecorder()
        finished = nil
        elapsed = 0

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true, options: [])
        } catch {
            return false
        }

        let url = Self.newRecordingURL()
        recordingURL = url

        // 44.1 kHz mono AAC — voice-note quality, ~32 kbps. A 60s clip
        // lands at roughly 250 KB which clears the backend's 25 MB cap
        // by orders of magnitude.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            if !recorder.record() {
                return false
            }
            audioRecorder = recorder
            isRecording = true
            startTicker()
            return true
        } catch {
            return false
        }
    }

    /// Stops the active recording and surfaces the captured data + the
    /// final whole-second duration through `finished`. Returns the
    /// `VoiceNoteRecording` directly too so the caller can choose
    /// whether to consume it inline.
    @discardableResult
    func stop() async -> VoiceNoteRecording? {
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else {
            return nil
        }
        stopTicker()
        // currentTime drops to 0 on stop; use the accumulated ticker
        // instead since it ticks on the main actor and is more
        // reliable than re-reading the recorder.
        let seconds = max(0, Int(elapsed.rounded()))

        // `stop()` kicks off the container finalization but returns before
        // it completes. Block on the delegate's completion callback so the
        // bytes we read below are the fully-written file — not a clip
        // missing its `moov` atom (which decodes to a dead, un-playable
        // upload). A short timeout guards against a delegate that never
        // fires so the composer can't hang forever.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            finishContinuation = cont
            recorder.stop()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.resumeFinishIfPending()
            }
        }

        cleanupRecorder()
        isRecording = false

        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let recording = VoiceNoteRecording(
            data: data,
            durationSeconds: seconds,
            filename: url.lastPathComponent)
        finished = recording
        return recording
    }

    /// Resume the pending `stop()` continuation exactly once — called both
    /// by the success delegate and the safety timeout.
    private func resumeFinishIfPending() {
        guard let cont = finishContinuation else { return }
        finishContinuation = nil
        cont.resume()
    }

    /// Discards the in-flight recording without uploading. Wires up
    /// the "X" cancel button on the composer's recording bar.
    func cancel() {
        if let recorder = audioRecorder {
            recorder.stop()
            if let url = recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        cleanupRecorder()
        stopTicker()
        isRecording = false
        finished = nil
        elapsed = 0
    }

    // MARK: Internal

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isRecording {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.elapsed += 0.2
                }
            }
        }
    }

    private func stopTicker() {
        tickerTask?.cancel()
        tickerTask = nil
    }

    private func cleanupRecorder() {
        audioRecorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

extension VoiceNoteRecorder: AVAudioRecorderDelegate {
    /// Fires once AVAudioRecorder has flushed and finalized the file. This
    /// is the signal `stop()` waits for before reading the bytes — without
    /// it we'd race the container finalization and sometimes upload a
    /// truncated, un-decodable clip.
    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder, successfully flag: Bool
    ) {
        Task { @MainActor in
            self.resumeFinishIfPending()
        }
    }
}

/// A completed recording ready for upload. Held as value type so the
/// composer can keep it in `@State` until the user taps send.
struct VoiceNoteRecording: Equatable {
    let data: Data
    let durationSeconds: Int
    let filename: String

    /// MIME the backend expects for AAC-in-MP4 recordings — matches
    /// {@code ALLOWED_AUDIO_CONTENT_TYPES} on the service side.
    var contentType: String { "audio/m4a" }
}
