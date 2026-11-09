import Foundation

/// Tiny STOMP 1.2 client over `URLSessionWebSocketTask`.
///
/// We intentionally avoid pulling in a STOMP library — the protocol is
/// frame-text and Spring's `enableSimpleBroker` only needs:
///
///   • CONNECT with `Authorization: Bearer <jwt>` + heart-beat
///   • SUBSCRIBE to `/topic/study-rooms/{roomId}`
///   • Receive MESSAGE frames; parse the JSON body as a `StudyRoomEvent`
///   • DISCONNECT on leave
///
/// Reconnect strategy: capped exponential back-off (1, 2, 4, … up to
/// 30 s). Re-subscribes the same topic on every successful CONNECT so
/// the consumer doesn't have to.
///
/// Public API:
///   `let socket = StudyRoomsSocket()`
///   `try await socket.subscribe(roomId: ...) { event in ... }`
///   `socket.disconnect()`
@MainActor
final class StudyRoomsSocket {

    // MARK: - Public

    typealias Listener = (StudyRoomEvent) -> Void

    enum SocketError: Error {
        case notConnected
        case authMissing
        case server(String)
    }

    init() {}

    /// Open the connection if needed and subscribe to the room topic.
    /// The handler is invoked on the main actor for every event.
    func subscribe(roomId: String, listener: @escaping Listener) async throws {
        self.subscribedRoomId = roomId
        self.listener = listener
        try await ensureConnected()
        sendSubscribe(roomId: roomId)
    }

    /// Tear everything down. Safe to call multiple times.
    func disconnect() {
        listener = nil
        subscribedRoomId = nil
        sendDisconnect()
        cancelTask()
        reconnectAttempts = 0
    }

    // MARK: - Private state

    private var task: URLSessionWebSocketTask?
    private var listener: Listener?
    private var subscribedRoomId: String?
    private var subscriptionId: String = "sub-1"
    private var reconnectAttempts: Int = 0
    private var reconnectWorkItem: DispatchWorkItem?

    // MARK: - Connect / reconnect

    private func ensureConnected() async throws {
        if task?.state == .running { return }
        cancelTask()

        guard let token = TokenStore.shared.accessToken else {
            throw SocketError.authMissing
        }
        let url = Self.wsURL()

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        // Send STOMP CONNECT frame.
        let connectFrame = buildFrame(
            command: "CONNECT",
            headers: [
                "accept-version": "1.2",
                "host": url.host ?? "droob",
                "Authorization": "Bearer \(token)",
                // 10s server heart-beat → catches dead connections.
                "heart-beat": "10000,10000"
            ],
            body: "")
        try await sendRaw(connectFrame)
        // Start the receive loop. We don't block on CONNECTED — the
        // SimpleBroker emits it but our subscribe is idempotent enough
        // that racing is fine; if the CONNECT fails the server closes
        // the socket and we hit the reconnect path.
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
                    case .string(let s):
                        await self?.handleFrame(s)
                    case .data(let d):
                        if let s = String(data: d, encoding: .utf8) {
                            await self?.handleFrame(s)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    await self?.scheduleReconnect()
                    return
                }
            }
        }
    }

    private func scheduleReconnect() async {
        guard subscribedRoomId != nil else { return } // user left
        cancelTask()
        reconnectAttempts += 1
        let delay = min(30.0, pow(2.0, Double(reconnectAttempts - 1)))
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      let roomId = self.subscribedRoomId,
                      let listener = self.listener else { return }
                try? await self.subscribe(roomId: roomId, listener: listener)
            }
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay,
                                      execute: item)
    }

    private func cancelTask() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // MARK: - STOMP framing

    private func sendSubscribe(roomId: String) {
        let frame = buildFrame(
            command: "SUBSCRIBE",
            headers: [
                "id": subscriptionId,
                "destination": "/topic/study-rooms/\(roomId)"
            ],
            body: "")
        Task { try? await sendRaw(frame) }
    }

    private func sendDisconnect() {
        let frame = buildFrame(
            command: "DISCONNECT",
            headers: [:],
            body: "")
        Task { try? await sendRaw(frame) }
    }

    private func sendRaw(_ frame: String) async throws {
        guard let task else { throw SocketError.notConnected }
        try await task.send(.string(frame))
    }

    private func buildFrame(
        command: String,
        headers: [String: String],
        body: String
    ) -> String {
        var s = command + "\n"
        for (k, v) in headers {
            s += "\(k):\(v)\n"
        }
        s += "\n"
        s += body
        s += "\u{0}"
        return s
    }

    // MARK: - Frame handling

    private func handleFrame(_ raw: String) async {
        // Heart-beat frames are bare newlines.
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        // Split command + headers + body.
        // STOMP frames terminate with NUL; strip it.
        let trimmed = raw.replacingOccurrences(of: "\u{0}", with: "")
        let parts = trimmed.components(separatedBy: "\n\n")
        guard let head = parts.first else { return }
        let body = parts.count > 1
            ? parts.dropFirst().joined(separator: "\n\n")
            : ""
        let lines = head.components(separatedBy: "\n")
        guard let command = lines.first else { return }

        switch command {
        case "MESSAGE":
            await dispatchMessage(body: body)
        case "ERROR":
            // Surface the server's reason to the console; keep socket
            // open so the reconnect loop has a chance to recover.
            let reason = lines.first(where: { $0.hasPrefix("message:") })
                ?? "ERROR"
            print("[StudyRoomsSocket] STOMP ERROR — \(reason)")
        default:
            // CONNECTED, RECEIPT, etc — ignore in v1.
            break
        }
    }

    private func dispatchMessage(body: String) async {
        guard let listener,
              let data = body.data(using: .utf8) else { return }
        do {
            let decoder = JSONDecoder()
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            decoder.dateDecodingStrategy = .custom { d in
                let c = try d.singleValueContainer()
                let s = try c.decode(String.self)
                if let date = iso.date(from: s) { return date }
                let isoPlain = ISO8601DateFormatter()
                isoPlain.formatOptions = [.withInternetDateTime]
                if let date = isoPlain.date(from: s) { return date }
                throw DecodingError.dataCorruptedError(
                    in: c, debugDescription: "bad date \(s)")
            }
            let event = try decoder.decode(StudyRoomEvent.self, from: data)
            listener(event)
        } catch {
            print("[StudyRoomsSocket] decode error \(error) — body=\(body)")
        }
    }

    // MARK: - URL builder

    /// Builds `ws(s)://host/ws` from the configured REST base URL so we
    /// inherit the same hostname + scheme without a second config knob.
    private static func wsURL() -> URL {
        let base = APIClient.publicBaseURL
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/ws"
        if base.scheme == "https" {
            components?.scheme = "wss"
        } else {
            components?.scheme = "ws"
        }
        return components?.url ?? base.appendingPathComponent("/ws")
    }
}

