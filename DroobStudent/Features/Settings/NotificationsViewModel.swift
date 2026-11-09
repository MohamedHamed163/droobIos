import Foundation

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var prefs: NotificationPrefs? = nil
    @Published var isLoading = true
    @Published var error: String? = nil

    func load() async {
        isLoading = true
        error = nil
        do {
            let req = APIRequest(path: "/v1/student/settings/notifications")
            prefs = try await AuthInterceptor.shared.execute(req)
        } catch let e where APIClient.isCancellationError(e) {
            isLoading = false
            return
        } catch let e as DroobError {
            if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated() }
            else { error = e.errorDescription }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Optimistically flip `keyPath` and persist via PUT.
    /// Rolls back on failure so the toggle visually reverts.
    func toggle(_ keyPath: WritableKeyPath<NotificationPrefs, Bool>, to newValue: Bool) {
        guard var current = prefs else { return }
        let original = current[keyPath: keyPath]
        current[keyPath: keyPath] = newValue
        prefs = current

        Task {
            let body = updateBody(for: keyPath, value: newValue)
            do {
                let req = APIRequest(path: "/v1/student/settings/notifications", method: .PUT, body: body)
                let updated: NotificationPrefs = try await AuthInterceptor.shared.execute(req)
                prefs = updated
            } catch let e as DroobError {
                // Revert and surface the error.
                if var p = prefs { p[keyPath: keyPath] = original; prefs = p }
                if case .unauthenticated(_, _) = e { AuthSession.shared.handleUnauthenticated() }
                else { error = e.errorDescription }
            } catch {
                if var p = prefs { p[keyPath: keyPath] = original; prefs = p }
                self.error = error.localizedDescription
            }
        }
    }

    private func updateBody(for keyPath: WritableKeyPath<NotificationPrefs, Bool>, value: Bool) -> NotificationPrefsUpdate {
        var body = NotificationPrefsUpdate()
        switch keyPath {
        case \NotificationPrefs.lessonReminders:      body.lessonReminders = value
        case \NotificationPrefs.streakAlerts:         body.streakAlerts = value
        case \NotificationPrefs.quizResults:          body.quizResults = value
        case \NotificationPrefs.courseUpdates:        body.courseUpdates = value
        case \NotificationPrefs.liveSessionReminders: body.liveSessionReminders = value
        case \NotificationPrefs.newMessages:          body.newMessages = value
        case \NotificationPrefs.newCourseAlerts:      body.newCourseAlerts = value
        case \NotificationPrefs.promotionsOffers:     body.promotionsOffers = value
        default: break
        }
        return body
    }
}
