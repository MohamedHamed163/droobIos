import UIKit
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

/// Owns the device-side push lifecycle: notification-permission prompt, APNs
/// registration, syncing the push token to the backend
/// (`/v1/student/devices/push-token`), and unregistering on logout.
///
/// Firebase is integrated <i>optionally</i> via `canImport`: when the
/// FirebaseMessaging SPM package is present, the FCM registration token is
/// synced (and the backend's `FcmPushSender` can reach the device through
/// FCM → APNs). Without the package the app still compiles and registers for
/// APNs directly — enough to receive `xcrun simctl push` payloads in the
/// Simulator and exercise the foreground-banner / tap-routing handlers.
@MainActor
final class PushService: NSObject {
    static let shared = PushService()
    private var lastSyncedToken: String?

    private override init() { super.init() }

    /// Configure Firebase (if linked) and the FCM delegate. The UN delegate is
    /// set by `AppDelegate` itself (to its own adaptor-owned instance).
    /// Called once from `AppDelegate.didFinishLaunching`.
    func configure() {
        #if canImport(FirebaseCore)
        if FirebaseApp.app() == nil,
           Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
        }
        #endif
        #if canImport(FirebaseMessaging)
        Messaging.messaging().delegate = self
        #endif
    }

    /// Prompt for permission once authenticated; register for remote
    /// notifications on grant. Safe to call repeatedly.
    func requestAuthorizationIfAuthenticated() {
        guard AuthSession.shared.currentUser != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                UIApplication.shared.registerForRemoteNotifications()
                // Proactively (re)sync the FCM token. The MessagingDelegate only
                // fires when the token is *generated or rotated*; on an account
                // switch the device's FCM token is unchanged, so without an
                // explicit fetch the newly-signed-in user would never get the
                // token (re)registered and the backend row stays revoked and
                // pointed at the previous account — so this device receives no
                // pushes for the new user.
                self.refreshPushToken()
            }
        }
    }

    /// Pull the current push token and sync it to the backend, independent of
    /// any registration-token delegate callback. Called on (re)authorization so
    /// an account switch re-points the device's token to the user actually
    /// signed in. In the Firebase build this fetches the cached FCM token; the
    /// non-Firebase build relies on the APNs callback and is a no-op here.
    func refreshPushToken() {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().token { [weak self] token, error in
            guard let token, error == nil else {
                if let error { print("[Push] FCM token fetch failed: \(error)") }
                return
            }
            Task { @MainActor in await self?.sync(token: token) }
        }
        #endif
    }

    func didRegisterAPNs(_ deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        // Hand the APNs token to FCM; the FCM registration token then arrives
        // via `messaging(_:didReceiveRegistrationToken:)` and is what we sync.
        Messaging.messaging().apnsToken = deviceToken
        #else
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await sync(token: hex) }
        #endif
    }

    func sync(token: String) async {
        guard token != lastSyncedToken else { return }
        let body = RegisterPushTokenBody(
            token: token,
            platform: "IOS",
            appVersion: Self.appVersion,
            locale: L10n.currentLanguageCode)
        do {
            let req = APIRequest(path: "/v1/student/devices/push-token", method: .POST, body: body)
            _ = try await AuthInterceptor.shared.execute(req) as [String: Bool]
            lastSyncedToken = token
            print("[Push] token synced")
        } catch {
            print("[Push] token sync failed: \(error)")
        }
    }

    /// Drop the token server-side on logout / push-disable.
    func unregister() async {
        guard let token = lastSyncedToken else { return }
        let req = APIRequest(
            path: "/v1/student/devices/push-token", method: .DELETE,
            body: UnregisterPushTokenBody(token: token))
        _ = try? await AuthInterceptor.shared.execute(req) as [String: Bool]
        lastSyncedToken = nil
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Active conversation (WhatsApp-style foreground suppression)

    /// The conversation currently on screen — a study-room id or a direct-thread
    /// id. `willPresent` reads this to suppress the banner for a push that
    /// belongs to the chat the user is already looking at.
    private(set) var activeConversationId: String?

    /// Mark a conversation as on-screen and clear any of its notifications that
    /// are already sitting in the tray (open-chat parity with WhatsApp).
    func enterConversation(_ id: String) {
        activeConversationId = id
        clearDeliveredNotifications(forConversationId: id)
    }

    /// Clear the on-screen conversation when leaving the chat. Guarded so a
    /// late `onDisappear` from a previous chat can't wipe a newer one.
    func leaveConversation(_ id: String) {
        if activeConversationId == id { activeConversationId = nil }
    }

    /// Remove already-delivered notifications whose deep-link route targets
    /// `id` from the Notification Center tray.
    func clearDeliveredNotifications(forConversationId id: String) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notes in
            let ids = notes
                .filter { PushService.routeConversationId($0.request.content.userInfo) == id }
                .map { $0.request.identifier }
            guard !ids.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    // MARK: - Notification routing

    /// Extract the conversation id (last path component) from a push payload's
    /// `route` — e.g. `droob://study-rooms/<roomId>` → `<roomId>` and
    /// `droob://messages/<threadId>` → `<threadId>`. Nil for non-chat routes.
    nonisolated static func routeConversationId(_ userInfo: [AnyHashable: Any]) -> String? {
        guard let route = userInfo["route"] as? String,
              let url = URL(string: route),
              url.host == "study-rooms" || url.host == "messages",
              let id = url.pathComponents.dropFirst().first, !id.isEmpty else { return nil }
        return id
    }

    /// Route a tapped notification. Chat routes are stashed on `AuthSession`
    /// for `RootView` to present — this works from background, the lock screen,
    /// a cold launch, and from any in-app screen. Everything else falls back to
    /// the URL deep-link path (`onOpenURL`).
    func handleNotificationTap(_ userInfo: [AnyHashable: Any]) {
        guard let route = userInfo["route"] as? String, let url = URL(string: route) else { return }
        switch url.host {
        case "study-rooms":
            if let id = url.pathComponents.dropFirst().first, !id.isEmpty {
                AuthSession.shared.pendingChatTarget = .studyRoom(id)
                return
            }
        case "messages":
            if let id = url.pathComponents.dropFirst().first, !id.isEmpty {
                AuthSession.shared.pendingChatTarget = .directThread(id)
                return
            }
        default:
            break
        }
        UIApplication.shared.open(url)
    }
}

#if canImport(FirebaseMessaging)
extension PushService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in await PushService.shared.sync(token: fcmToken) }
    }
}
#endif

// MARK: - Request bodies

private struct RegisterPushTokenBody: Encodable {
    let token: String
    let platform: String
    let appVersion: String
    let locale: String
}

private struct UnregisterPushTokenBody: Encodable {
    let token: String
}

// MARK: - AppDelegate

/// UIKit app delegate bridged into SwiftUI via `@UIApplicationDelegateAdaptor`.
/// Handles APNs token callbacks plus foreground presentation and tap routing
/// (a tapped push opens its `route` deep link, which re-enters the app's
/// `onOpenURL` handler).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        PushService.shared.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushService.shared.didRegisterAPNs(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Push] APNs registration failed: \(error.localizedDescription)")
    }

    // Foreground presentation. WhatsApp-style: if the push belongs to the chat
    // the user is already viewing, suppress the banner / tray / badge and play
    // only a soft sound. Any other conversation (or non-chat push) shows a full
    // banner as usual.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        let activeId = await MainActor.run { PushService.shared.activeConversationId }
        if let convId = PushService.routeConversationId(userInfo), convId == activeId {
            return [.sound]
        }
        return [.banner, .list, .sound, .badge]
    }

    // Route a tapped notification — chat pushes open the relevant chat screen
    // (study-room or direct thread); other routes fall back to the deep-link
    // handler. Works from background, lock screen, and cold launch.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run { PushService.shared.handleNotificationTap(userInfo) }
    }
}
