import Foundation

public struct CustomResolution: Codable, Hashable, Identifiable {
    public var id: String { "\(width)x\(height)" }
    public let width: Int
    public let height: Int

    public static let widthRange = 320...8192
    public static let heightRange = 200...8192

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static func isValid(width: Int, height: Int) -> Bool {
        widthRange.contains(width) && heightRange.contains(height)
    }

    public var isValid: Bool {
        Self.isValid(width: width, height: height)
    }

    /// Whether the current mode matches a stored resolution, accounting for 90/270 rotation.
    public static func contains(
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

    /// Key suffix used to store per-display custom resolutions.
    public static func storageID(for display: DisplayInfo) -> String {
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
}
