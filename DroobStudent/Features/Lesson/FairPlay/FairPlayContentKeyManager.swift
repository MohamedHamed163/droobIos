import AVFoundation
import Foundation

// MARK: - FairPlayContentKeyManager
//
// Client side of Apple FairPlay Streaming (FPS). Handles the content-key
// handshake so AVPlayer can decrypt a FairPlay-encrypted HLS stream:
//
//   1. The HLS manifest carries `#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://<id>"`.
//   2. When AVPlayer hits that, our `AVContentKeySession` delegate fires.
//   3. We fetch the FPS **application certificate** from the backend.
//   4. We ask AVFoundation to build an **SPC** (Server Playback Context) from
//      the certificate + content id.
//   5. We POST the SPC to the backend **license server (KSM)**, which returns
//      a **CKC** (Content Key Context).
//   6. We hand the CKC back to AVFoundation, which decrypts in the secure
//      media path — frames never reach screen capture, and HDCP is enforced
//      on external displays (capture/mirroring of the video → black).
//
// Graceful: if FairPlay isn't configured, or the stream isn't encrypted, no
// key request ever fires and normal playback continues unchanged.

final class FairPlayContentKeyManager: NSObject {
    static let shared = FairPlayContentKeyManager()

    private let config: FairPlayConfig
    private let session: AVContentKeySession
    private let delegateQueue = DispatchQueue(label: "sa.droob.fairplay")
    private var certificateCache: Data?

    init(config: FairPlayConfig = .default) {
        self.config = config
        self.session = AVContentKeySession(keySystem: .fairPlayStreaming)
        super.init()
        session.setDelegate(self, queue: delegateQueue)
    }

    /// Routes the asset's FairPlay key requests through this manager. Safe to
    /// call for non-DRM assets (no key request will fire).
    func prepareToPlay(_ asset: AVURLAsset) {
        guard config.isEnabled else { return }
        session.addContentKeyRecipient(asset)
    }

    // MARK: Certificate

    private func applicationCertificate() async throws -> Data {
        if let cached = certificateCache { return cached }

        // 1) Remote certificate endpoint.
        if let url = config.certificateURL {
            var req = URLRequest(url: url)
            if let token = TokenStore.shared.accessToken {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            if let (data, response) = try? await URLSession.shared.data(for: req),
               (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty {
                certificateCache = data
                return data
            }
        }
        // 2) Bundled certificate fallback.
        if let name = config.bundledCertificateName {
            for ext in ["cer", "der", "crt"] {
                if let url = Bundle.main.url(forResource: name, withExtension: ext),
                   let data = try? Data(contentsOf: url) {
                    certificateCache = data
                    return data
                }
            }
        }
        throw FairPlayError.missingCertificate
    }

    // MARK: License (CKC)

    private func requestContentKey(spcData: Data, contentId: String) async throws -> Data {
        guard let url = config.licenseServerURL else { throw FairPlayError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.setValue(contentId, forHTTPHeaderField: "X-Droob-Content-Id")
        if let token = TokenStore.shared.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Default wire format: raw SPC bytes in the body. (Swap to a base64
        // JSON envelope here if your KSM expects that.)
        req.httpBody = spcData

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            throw FairPlayError.licenseRequestFailed
        }
        // Accept raw CKC, or a JSON envelope {"ckc":"<base64>"}.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let b64 = json["ckc"] as? String, let ckc = Data(base64Encoded: b64) {
            return ckc
        }
        return data
    }

    // MARK: Key-request handling

    private func handleKeyRequest(_ keyRequest: AVContentKeyRequest) {
        // The identifier is the `skd://<contentId>` URI from the manifest.
        guard let idString = keyRequest.identifier as? String,
              let contentId = idString.replacingOccurrences(of: "skd://", with: "")
                .removingPercentEncoding,
              let contentIdData = contentId.data(using: .utf8) else {
            keyRequest.processContentKeyResponseError(FairPlayError.badContentId)
            return
        }

        Task {
            do {
                let cert = try await applicationCertificate()
                let spcData = try await keyRequest.makeStreamingContentKeyRequestData(
                    forApp: cert, contentIdentifier: contentIdData, options: nil)
                let ckc = try await requestContentKey(spcData: spcData, contentId: contentId)
                let response = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckc)
                keyRequest.processContentKeyResponse(response)
            } catch {
                NSLog("[FairPlay] key request failed: \(error.localizedDescription)")
                keyRequest.processContentKeyResponseError(error)
            }
        }
    }

    enum FairPlayError: LocalizedError {
        case notConfigured, missingCertificate, badContentId, licenseRequestFailed
        var errorDescription: String? {
            switch self {
            case .notConfigured:       return "FairPlay is not configured."
            case .missingCertificate:  return L10n.playbackCertificateError
            case .badContentId:        return "Malformed FairPlay content identifier."
            case .licenseRequestFailed:return "FairPlay license request failed."
            }
        }
    }
}

// MARK: - AVContentKeySessionDelegate

extension FairPlayContentKeyManager: AVContentKeySessionDelegate {
    func contentKeySession(_ session: AVContentKeySession,
                           didProvide keyRequest: AVContentKeyRequest) {
        handleKeyRequest(keyRequest)
    }

    func contentKeySession(_ session: AVContentKeySession,
                           didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest) {
        handleKeyRequest(keyRequest)
    }

    func contentKeySession(_ session: AVContentKeySession,
                           contentKeyRequest keyRequest: AVContentKeyRequest,
                           didFailWithError err: Error) {
        NSLog("[FairPlay] content key request error: \(err.localizedDescription)")
    }

    func contentKeySession(_ session: AVContentKeySession,
                           shouldRetry keyRequest: AVContentKeyRequest,
                           reason retryReason: AVContentKeyRequest.RetryReason) -> Bool {
        switch retryReason {
        case .timedOut, .receivedResponseWithExpiredLease, .receivedObsoleteContentKey:
            return true
        default:
            return false
        }
    }
}
