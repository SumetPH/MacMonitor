import Foundation
import UserNotifications

@MainActor
public final class DisplayNotificationService: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = DisplayNotificationService()

    private var notificationCenter: UNUserNotificationCenter?

    private override init() {
        super.init()

        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.bundleIdentifier != nil else {
            print("[DisplayNotificationService] Notifications are unavailable when running outside an app bundle.")
            return
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        notificationCenter = center
    }

    public func requestAuthorization() {
        guard let notificationCenter else { return }

        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("[DisplayNotificationService] Notification authorization failed: \(error.localizedDescription)")
            } else if !granted {
                print("[DisplayNotificationService] Notification permission was not granted.")
            }
        }
    }

    public func notifyPowerChanged(for displayName: String, isEnabled: Bool) {
        guard let notificationCenter else { return }

        let content = UNMutableNotificationContent()
        content.title = isEnabled ? "Display Enabled" : "Display Disabled"
        content.body = "\(displayName) has been \(isEnabled ? "enabled" : "disabled")."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        notificationCenter.add(request) { error in
            if let error {
                print("[DisplayNotificationService] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
