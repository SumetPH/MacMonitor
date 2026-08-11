import Foundation

struct CustomResolution: Codable, Hashable, Identifiable {
    var id: String { "\(width)x\(height)" }
    let width: Int
    let height: Int
}

enum CustomResolutionStore {
    static func contains(
        width: Int,
        height: Int,
        rotation: Int,
        in resolutions: [CustomResolution]
    ) -> Bool {
        let isQuarterTurn = rotation == 90 || rotation == 270

        return resolutions.contains { resolution in
            if isQuarterTurn {
                return resolution.width == height && resolution.height == width
            }
            return resolution.width == width && resolution.height == height
        }
    }

    static func storageID(for display: DisplayInfo) -> String {
        if let uuid = display.identifier.uuid, !uuid.isEmpty {
            return uuid
        }

        if let serialNumber = display.identifier.serialNumber, serialNumber != 0 {
            return display.identifier.id
        }

        // Some displays do not expose a stable UUID or serial number. Keep their
        // draft settings isolated for the current connection instead of sharing
        // them through a potentially-colliding vendor/product key.
        return "display-\(display.displayID)"
    }

    static func save(_ resolutions: [CustomResolution], for display: DisplayInfo) {
        let key = "MacMonitor.CustomResolutions.\(storageID(for: display))"
        if let data = try? JSONEncoder().encode(resolutions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load(for display: DisplayInfo) -> [CustomResolution] {
        let key = "MacMonitor.CustomResolutions.\(storageID(for: display))"
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
