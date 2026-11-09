import Foundation

@MainActor
final class NotificationsInboxViewModel: ObservableObject {
    /// Rows for the active tab, paginated newest-first. The server applies the
    /// category/unread filter; we append pages as the user scrolls.
    @Published private(set) var notifications: [StudentNotification] = []
    @Published var selectedTab: NotificationCategoryUI = .all {
        didSet { if oldValue != selectedTab { Task { await load() } } }
    }
    @Published var isLoading = true
    @Published var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var unreadCount = 0
    @Published var error: String? = nil

    private let socket = NotificationsSocket()
    private let pageSize = 8
    private var offset = 0
    /// Guards against stale fetches when the tab changes mid-flight.
    private var loadToken = 0

    /// On the Unread tab, hide rows that get marked read locally so they drop
    /// out immediately; every other tab is already narrowed server-side.
    var visible: [StudentNotification] {
        selectedTab == .unread ? notifications.filter(\.isUnread) : notifications
    }

    // MARK: - Load

    /// Fresh load of the first page for the active tab (also used by pull-to-refresh).
    func load() async {
        loadToken += 1
        let token = loadToken
        isLoading = true
        error = nil
        offset = 0
        do {
            let page: NotificationPage = try await fetchPage(offset: 0)
            guard token == loadToken else { return }
            notifications = page.items
            offset = page.nextOffset
            hasMore = page.hasMore
            await refreshUnreadCount()
        } catch let e where APIClient.isCancellationError(e) {
            if token == loadToken { isLoading = false }
            return
        } catch let e as DroobError {
            guard token == loadToken else { return }
            if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated() }
            else { self.error = e.errorDescription }
        } catch let e {
            guard token == loadToken else { return }
            self.error = e.localizedDescription
        }
        if token == loadToken { isLoading = false }
    }

    /// Appends the next page when the user reaches the end of the list.
    func loadMore() async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        let token = loadToken
        isLoadingMore = true
        do {
            let page: NotificationPage = try await fetchPage(offset: offset)
            guard token == loadToken else { isLoadingMore = false; return }
            let existing = Set(notifications.map(\.id))
            notifications.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            offset = page.nextOffset
            hasMore = page.hasMore
        } catch {
            // Load-more failures are non-fatal; the user can scroll again to retry.
        }
        if token == loadToken { isLoadingMore = false }
    }

    private func fetchPage(offset: Int) async throws -> NotificationPage {
        var query = [
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let wire = selectedTab.wire { query.append(URLQueryItem(name: "category", value: wire)) }
        if selectedTab == .unread { query.append(URLQueryItem(name: "unread", value: "true")) }
        let req = APIRequest(path: "/v1/student/notifications", queryItems: query)
        return try await AuthInterceptor.shared.execute(req)
    }

    private func refreshUnreadCount() async {
        do {
            let req = APIRequest(path: "/v1/student/notifications/unread-count")
            let body: [String: Int] = try await AuthInterceptor.shared.execute(req)
            unreadCount = body["unread"] ?? unreadCount
        } catch {
            // Badge is best-effort; leave the last known count on failure.
        }
    }

    // MARK: - Realtime

    func startRealtime() {
        Task {
            try? await socket.connect { [weak self] incoming in
                self?.insert(incoming)
            }
        }
    }

    func stopRealtime() { socket.disconnect() }

    /// Merge a pushed notification: dedupe by id, respect the active filter,
    /// keep newest-first ordering, and bump the unread badge.
    private func insert(_ n: StudentNotification) {
        guard !notifications.contains(where: { $0.id == n.id }) else { return }
        if let wire = selectedTab.wire, n.category != wire { return }
        if selectedTab == .unread && !n.isUnread { return }
        notifications.insert(n, at: 0)
        notifications.sort { $0.createdAt > $1.createdAt }
        if n.isUnread { unreadCount += 1 }
    }

    // MARK: - Mark read

    func markRead(id: String) {
        guard let idx = notifications.firstIndex(where: { $0.id == id }),
              notifications[idx].isUnread else { return }
        let original = notifications[idx].readAt
        notifications[idx].readAt = Date()
        unreadCount = max(0, unreadCount - 1)
        Task {
            do {
                let req = APIRequest(path: "/v1/student/notifications/\(id)/read", method: .POST)
                _ = try await AuthInterceptor.shared.execute(req) as [String: Bool]
            } catch {
                if let i = self.notifications.firstIndex(where: { $0.id == id }) {
                    self.notifications[i].readAt = original
                    self.unreadCount += 1
                }
            }
        }
    }

    func markAllRead() {
        let snapshot = notifications
        let previousUnread = unreadCount
        let now = Date()
        for i in notifications.indices where notifications[i].readAt == nil {
            notifications[i].readAt = now
        }
        unreadCount = 0
        Task {
            do {
                let req = APIRequest(path: "/v1/student/notifications/read-all", method: .POST)
                _ = try await AuthInterceptor.shared.execute(req) as [String: Int]
            } catch {
                self.notifications = snapshot
                self.unreadCount = previousUnread
            }
        }
    }

    // MARK: - Delete

    func delete(id: String) {
        guard let idx = notifications.firstIndex(where: { $0.id == id }) else { return }
        let removed = notifications.remove(at: idx)
        if removed.isUnread { unreadCount = max(0, unreadCount - 1) }
        Task {
            do {
                let req = APIRequest(path: "/v1/student/notifications/\(id)", method: .DELETE)
                _ = try await AuthInterceptor.shared.execute(req) as [String: Bool]
            } catch {
                self.notifications.insert(removed, at: min(idx, self.notifications.count))
                self.notifications.sort { $0.createdAt > $1.createdAt }
                if removed.isUnread { self.unreadCount += 1 }
            }
        }
    }

    func clearAll() {
        let snapshot = notifications
        let previousUnread = unreadCount
        notifications = []
        unreadCount = 0
        hasMore = false
        Task {
            do {
                let req = APIRequest(path: "/v1/student/notifications", method: .DELETE)
                _ = try await AuthInterceptor.shared.execute(req) as [String: Int]
            } catch {
                self.notifications = snapshot
                self.unreadCount = previousUnread
            }
        }
    }

    // MARK: - Inline actions

    /// Runs a card's inline action, then marks the row read locally (every
    /// action endpoint marks-read server-side). Returns the decoded body so
    /// the caller can act on it (e.g. open a join URL).
    @discardableResult
    func perform(_ action: InboxAction, on id: String) async -> [String: AnyJSONValue]? {
        do {
            let req = APIRequest(
                path: "/v1/student/notifications/\(id)/actions/\(action.kind.rawValue)",
                method: .POST)
            let body: AnyJSON = try await AuthInterceptor.shared.execute(req)
            if let i = notifications.firstIndex(where: { $0.id == id }), notifications[i].isUnread {
                notifications[i].readAt = Date()
                unreadCount = max(0, unreadCount - 1)
            }
            return body.value
        } catch {
            self.error = (error as? DroobError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}
