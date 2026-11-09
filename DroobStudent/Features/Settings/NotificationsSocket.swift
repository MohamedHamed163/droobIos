import Foundation

/// STOMP client for the realtime notifications feed. Mirrors
/// `StudyRoomsSocket` but subscribes to the Spring <i>user destination</i>
/// `/user/queue/notifications`, which the broker routes only to the
/// authenticated principal's own session(s) — so a client only ever sees
/// its own notifications.
///
/// Each `MESSAGE` body is the same snake-cased shape as a REST inbox item
/// (`NotificationFanOut.wire`), decoded into `StudentNotification` and handed
/// to the listener on the main actor for an optimistic insert.
@MainActor
final class NotificationsSocket {

    typealias Listener = (StudentNotification) -> Void

    enum SocketError: Error { case notConnected, authMissing }

    init() {}

    /// Open the connection if needed and subscribe to the user queue.
    func connect(listener: @escaping Listener) async throws {
        self.listener = listener
        self.wantsConnection = true
        try await ensureConnected()
        sendSubscribe()
    }

    func disconnect() {
        listener = nil
        wantsConnection = false
        sendDisconnect()
        cancelTask()
        reconnectAttempts = 0
    }

    // MARK: - State

    private var task: URLSessionWebSocketTask?
    private var listener: Listener?
    private var wantsConnection = false
    private let subscriptionId = "notif-sub-1"
    private var reconnectAttempts = 0
    private var reconnectWorkItem: DispatchWorkItem?

    // MARK: - Connect / reconnect

    private func ensureConnected() async throws {
        if task?.state == .running { return }
        cancelTask()

        guard let token = TokenStore.shared.accessToken else {
            throw SocketError.authMissing
        }
        let url = Self.wsURL()
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        let connectFrame = buildFrame(
            command: "CONNECT",
            headers: [
                "accept-version": "1.2",
                "host": url.host ?? "droob",
                "Authorization": "Bearer \(token)",
                "heart-beat": "10000,10000"
            ],
            body: "")
        try await sendRaw(connectFrame)
        startReceiveLoop()
        reconnectAttempts = 0
    }

    private func startReceiveLoop() {
        guard let task else { return }
        Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let s): await self?.handleFrame(s)
                    case .data(let d):
                        if let s = String(data: d, encoding: .utf8) { await self?.handleFrame(s) }
                    @unknown default: break
                    }
                } catch {
                    await self?.scheduleReconnect()
                    return
                }
            }
        }
    }

    private func scheduleReconnect() async {
        guard wantsConnection else { return }
        cancelTask()
        reconnectAttempts += 1
        let delay = min(30.0, pow(2.0, Double(reconnectAttempts - 1)))
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.wantsConnection, let listener = self.listener else { return }
                try? await self.connect(listener: listener)
            }
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelTask() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // MARK: - Framing

    private func sendSubscribe() {
        let frame = buildFrame(
            command: "SUBSCRIBE",
            headers: ["id": subscriptionId, "destination": "/user/queue/notifications"],
            body: "")
        Task { try? await sendRaw(frame) }
    }

    private func sendDisconnect() {
        Task { try? await sendRaw(buildFrame(command: "DISCONNECT", headers: [:], body: "")) }
    }

    private func sendRaw(_ frame: String) async throws {
        guard let task else { throw SocketError.notConnected }
        try await task.send(.string(frame))
    }

    private func buildFrame(command: String, headers: [String: String], body: String) -> String {
        var s = command + "\n"
        for (k, v) in headers { s += "\(k):\(v)\n" }
        s += "\n" + body + "\u{0}"
        return s
    }

    // MARK: - Frame handling

    private func handleFrame(_ raw: String) async {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        let trimmed = raw.replacingOccurrences(of: "\u{0}", with: "")
        let parts = trimmed.components(separatedBy: "\n\n")
        guard let head = parts.first else { return }
        let body = parts.count > 1 ? parts.dropFirst().joined(separator: "\n\n") : ""
        let lines = head.components(separatedBy: "\n")
        guard let command = lines.first else { return }

        switch command {
        case "MESSAGE": await dispatchMessage(body: body)
        case "ERROR":
            let reason = lines.first(where: { $0.hasPrefix("message:") }) ?? "ERROR"
            print("[NotificationsSocket] STOMP ERROR — \(reason)")
        default: break
        }
    }

    private func dispatchMessage(body: String) async {
        guard let listener, let data = body.data(using: .utf8) else { return }
        do {
            let decoder = JSONDecoder()
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            decoder.dateDecodingStrategy = .custom { d in
                let c = try d.singleValueContainer()
                let s = try c.decode(String.self)
                if let date = iso.date(from: s) { return date }
                let plain = ISO8601DateFormatter()
                plain.formatOptions = [.withInternetDateTime]
                if let date = plain.date(from: s) { return date }
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad date \(s)")
            }
            let n = try decoder.decode(StudentNotification.self, from: data)
            listener(n)
        } catch {
            print("[NotificationsSocket] decode error \(error) — body=\(body)")
        }
    }

    // MARK: - URL

    private static func wsURL() -> URL {
        let base = APIClient.publicBaseURL
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/ws"
        components?.scheme = base.scheme == "https" ? "wss" : "ws"
        return components?.url ?? base.appendingPathComponent("/ws")
    }
}
