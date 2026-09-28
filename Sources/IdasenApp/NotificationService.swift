import Foundation
import Combine
import UserNotifications

/// Wraps `UNUserNotificationCenter` and falls back to an in-app banner when
/// notifications are unavailable (or the app is running unbundled).
@MainActor
final class NotificationService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    static let reminderCategory = "IDASEN_REMINDER"
    static let standNowAction = "IDASEN_STAND_NOW"
    static let snoozeAction = "IDASEN_SNOOZE"
    static let arrivalCategory = "IDASEN_ARRIVAL"

    private weak var model: AppModel?
    private var isAuthorized = false
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func configure(model: AppModel) {
        self.model = model
        guard let center else { return }
        center.delegate = self
        center.setNotificationCategories(Self.categories)
        refreshAuthorization()
    }

    func updateAuthorization() {
        refreshAuthorization()
    }

    func refreshAuthorization() {
        guard let center else {
            isAuthorized = false
            return
        }
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            let authorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            Task { @MainActor in
                self.authorizationStatus = status
                self.isAuthorized = authorized
            }
        }
    }

    func requestAuthorization() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                self.isAuthorized = granted
                self.refreshAuthorization()
            }
        }
    }

    func postStandingReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Time to stand up"
        content.body = "Ready for a standing break? Move to your standing preset when you’re ready."
        content.categoryIdentifier = Self.reminderCategory
        content.sound = .default
        deliver(content, identifier: "idasen.reminder.\(UUID().uuidString)")
        model?.banner("Time to stand up — use the menu bar to raise the desk", style: .warning)
    }

    func postArrival(heightText: String) {
        let content = UNMutableNotificationContent()
        content.title = "Desk in position"
        content.body = "The desk reached \(heightText)."
        content.categoryIdentifier = Self.arrivalCategory
        deliver(content, identifier: "idasen.arrival.\(UUID().uuidString)")
    }

    private func deliver(_ content: UNMutableNotificationContent, identifier: String) {
        guard let center, isAuthorized else { return }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request)
    }

    private static var categories: Set<UNNotificationCategory> {
        let stand = UNNotificationAction(
            identifier: standNowAction,
            title: "Stand up now",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: snoozeAction,
            title: "Snooze 10 min",
            options: []
        )
        let reminder = UNNotificationCategory(
            identifier: reminderCategory,
            actions: [stand, snooze],
            intentIdentifiers: [],
            options: []
        )
        let arrival = UNNotificationCategory(
            identifier: arrivalCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        return [reminder, arrival]
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case Self.standNowAction:
                self.model?.standUpNow()
            case Self.snoozeAction:
                self.model?.snoozeReminder()
            default:
                break
            }
        }
    }
}
