import Foundation
import CoreGraphics

@MainActor
public final class RefreshRateService {
    public static let shared = RefreshRateService()
    
    private init() {}
    
    public struct GroupedResolution: Identifiable, Hashable {
        public var id: String {
            return "\(width)x\(height)-\(isHiDPI ? "hidpi" : "normal")"
        }
        public let width: Int
        public let height: Int
        public let isHiDPI: Bool
        public var modes: [CGDisplayMode]
        
        public var refreshRates: [Double] {
            let rates = modes.map { $0.refreshRate == 0 ? 60.0 : $0.refreshRate }
            return Array(Set(rates)).sorted()
        }
    }
    
    public func groupModesByResolution(_ modes: [CGDisplayMode]) -> [GroupedResolution] {
        var groups: [String: GroupedResolution] = [:]
        
        for mode in modes {
            let isHiDPI = mode.pixelWidth > mode.width || mode.pixelHeight > mode.height
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
    
    public func findMode(in modes: [CGDisplayMode], width: Int, height: Int, refreshRate: Double, isHiDPI: Bool) -> CGDisplayMode? {
        let matchingModes = modes.filter {
            let modeHiDPI = $0.pixelWidth > $0.width || $0.pixelHeight > $0.height
            let rate = $0.refreshRate == 0 ? 60.0 : $0.refreshRate
            return $0.width == width && $0.height == height && modeHiDPI == isHiDPI && abs(rate - refreshRate) < 0.1
        }
        return matchingModes.first ?? modes.filter { $0.width == width && $0.height == height }.first
    }
}
