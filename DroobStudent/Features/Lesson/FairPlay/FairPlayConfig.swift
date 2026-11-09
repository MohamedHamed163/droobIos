import Foundation

// MARK: - FairPlayConfig
//
// Endpoints + certificate source for Apple FairPlay Streaming (FPS) DRM.
// Derived from the app's API base URL by default. FairPlay only engages when
// the HLS manifest is actually encrypted (carries an `#EXT-X-KEY` with an
// `skd://` URI); for today's non-DRM streams the content-key session simply
// never receives a key request, so attaching it is harmless.
//
// Backend must provide (see FairPlayContentKeyManager docs):
//   • GET  {base}/v1/student/drm/fairplay/certificate  → the FPS application
//          certificate (DER/.cer bytes).
//   • POST {base}/v1/student/drm/fairplay/license      → takes the SPC,
//          returns the CKC (the per-asset content key).

struct FairPlayConfig {
    /// License (KSM) endpoint: SPC in, CKC out. Nil disables FairPlay.
    var licenseServerURL: URL?
    /// Application-certificate endpoint (DER). Optional if bundling the cert.
    var certificateURL: URL?
    /// Fallback: an FPS certificate bundled in the app (resource name, no ext).
    var bundledCertificateName: String?

    /// FairPlay is considered configured when we have somewhere to fetch the
    /// license from.
    var isEnabled: Bool { licenseServerURL != nil }

    static let `default`: FairPlayConfig = {
        var cfg = FairPlayConfig()
        if let base = Bundle.main.object(forInfoDictionaryKey: "DROOB_API_BASE_URL") as? String,
           let baseURL = URL(string: base) {
            cfg.licenseServerURL = baseURL.appendingPathComponent("v1/student/drm/fairplay/license")
            cfg.certificateURL = baseURL.appendingPathComponent("v1/student/drm/fairplay/certificate")
        }
        // If you ship the cert in the bundle instead, drop `fairplay.cer` in
        // and this picks it up when the network cert fetch fails.
        cfg.bundledCertificateName = "fairplay"
        return cfg
    }()
}
