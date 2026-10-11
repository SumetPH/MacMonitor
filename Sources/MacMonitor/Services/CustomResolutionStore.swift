import Foundation
import MacMonitorCore

enum CustomResolutionStore {
    static func save(_ resolutions: [CustomResolution], for display: DisplayInfo) {
        let key = "MacMonitor.CustomResolutions.\(CustomResolution.storageID(for: display))"
        if let data = try? JSONEncoder().encode(resolutions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load(for display: DisplayInfo) -> [CustomResolution] {
        let key = "MacMonitor.CustomResolutions.\(CustomResolution.storageID(for: display))"
        if let data = UserDefaults.standard.data(forKey: key),
           let resolutions = try? JSONDecoder().decode([CustomResolution].self, from: data) {
            return resolutions
        }

        // Migrate from old single key if available.
        let keyWidth = "MacMonitor.CustomWidth.\(display.identifier.id)"
        let keyHeight = "MacMonitor.CustomHeight.\(display.identifier.id)"
        let savedWidth = UserDefaults.standard.integer(forKey: keyWidth)
        let savedHeight = UserDefaults.standard.integer(forKey: keyHeight)

        if savedWidth > 0 && savedHeight > 0 {
            return [CustomResolution(width: savedWidth, height: savedHeight)]
        }

        return []
    }
}
