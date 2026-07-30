import Foundation
import UserNotifications

@MainActor
public final class DisplayNotificationService: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = DisplayNotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        notificationCenter.delegate = self
    }

    public func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("[DisplayNotificationService] Notification authorization failed: \(error.localizedDescription)")
            } else if !granted {
                print("[DisplayNotificationService] Notification permission was not granted.")
            }
        }
    }

    public func notifyPowerChanged(for displayName: String, isEnabled: Bool) {
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
