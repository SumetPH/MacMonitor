import Foundation
import CoreGraphics

/// Groups and selects `CGDisplayMode`s by logical resolution. Pure: no display changes.
public enum DisplayModeGrouping {
    public struct GroupedResolution: Identifiable, Hashable {
        public var id: String {
            return "\(width)x\(height)-\(isHiDPI ? "hidpi" : "normal")"
        }
        public let width: Int
        public let height: Int
        public let isHiDPI: Bool
        public var modes: [CGDisplayMode]

        public init(width: Int, height: Int, isHiDPI: Bool, modes: [CGDisplayMode]) {
            self.width = width
            self.height = height
            self.isHiDPI = isHiDPI
            self.modes = modes
        }

        public var refreshRates: [Double] {
            let rates = modes.map { $0.refreshRate == 0 ? 60.0 : $0.refreshRate }
            return Array(Set(rates)).sorted()
        }
    }

    public static func isModeHiDPI(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int) -> Bool {
        return pixelWidth > width || pixelHeight > height
    }

    public static func groupModesByResolution(_ modes: [CGDisplayMode]) -> [GroupedResolution] {
        var groups: [String: GroupedResolution] = [:]

        for mode in modes {
            let isHiDPI = isModeHiDPI(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight)
            let key = "\(mode.width)x\(mode.height)-\(isHiDPI ? "hidpi" : "normal")"

            if var group = groups[key] {
                // To avoid duplicate refresh rates in the modes list, we can check
                if !group.modes.contains(where: { $0.refreshRate == mode.refreshRate }) {
                    group.modes.append(mode)
                    groups[key] = group
                }
            } else {
                groups[key] = GroupedResolution(
                    width: mode.width,
                    height: mode.height,
                    isHiDPI: isHiDPI,
                    modes: [mode]
                )
            }
        }

        // Sort by width (descending), then height (descending)
        return groups.values.sorted {
            if $0.width != $1.width {
                return $0.width > $1.width
            }
            if $0.height != $1.height {
                return $0.height > $1.height
            }
            return $0.isHiDPI && !$1.isHiDPI
        }
    }

    public static func findMode(in modes: [CGDisplayMode], width: Int, height: Int, refreshRate: Double, isHiDPI: Bool) -> CGDisplayMode? {
        let matchingModes = modes.filter {
            let modeHiDPI = isModeHiDPI(width: $0.width, height: $0.height, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight)
            let rate = $0.refreshRate == 0 ? 60.0 : $0.refreshRate
            return $0.width == width && $0.height == height && modeHiDPI == isHiDPI && abs(rate - refreshRate) < 0.1
        }
        return matchingModes.first ?? modes.filter { $0.width == width && $0.height == height }.first
    }
}
