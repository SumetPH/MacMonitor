import Foundation
import CoreGraphics
import AppKit

public struct DisplayInfo: Codable, Identifiable, Hashable {
    public var id: String {
        return identifier.id
    }
    
    public let displayID: CGDirectDisplayID
    public let identifier: DisplayIdentifier
    public let name: String
    public let isBuiltIn: Bool
    public let isActive: Bool
    public let isOnline: Bool
    public let isAsleep: Bool
    public let isMain: Bool
    public let isMirrored: Bool
    public let isAppDisconnected: Bool
    
    public let currentWidth: Int
    public let currentHeight: Int
    public let currentPixelWidth: Int
    public let currentPixelHeight: Int
    public let refreshRate: Double
    public let scaleFactor: Double
    public let isHiDPI: Bool
    public let rotation: Int // 0, 90, 180, 270
    
    public let modes: [DisplayModeInfo]
    
    public init(
        displayID: CGDirectDisplayID,
        identifier: DisplayIdentifier,
        name: String,
        isBuiltIn: Bool,
        isActive: Bool,
        isOnline: Bool,
        isAsleep: Bool,
        isMain: Bool,
        isMirrored: Bool,
        isAppDisconnected: Bool = false,
        currentWidth: Int,
        currentHeight: Int,
        currentPixelWidth: Int,
        currentPixelHeight: Int,
        refreshRate: Double,
        scaleFactor: Double,
        isHiDPI: Bool,
        rotation: Int,
        modes: [DisplayModeInfo]
    ) {
        self.displayID = displayID
        self.identifier = identifier
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isActive = isActive
        self.isOnline = isOnline
        self.isAsleep = isAsleep
        self.isMain = isMain
        self.isMirrored = isMirrored
        self.isAppDisconnected = isAppDisconnected
        self.currentWidth = currentWidth
        self.currentHeight = currentHeight
        self.currentPixelWidth = currentPixelWidth
        self.currentPixelHeight = currentPixelHeight
        self.refreshRate = refreshRate
        self.scaleFactor = scaleFactor
        self.isHiDPI = isHiDPI
        self.rotation = rotation
        self.modes = modes
    }
    
    public func disconnectedSnapshot() -> DisplayInfo {
        DisplayInfo(
            displayID: displayID,
            identifier: identifier,
            name: name,
            isBuiltIn: isBuiltIn,
            isActive: false,
            isOnline: false,
            isAsleep: true,
            isMain: false,
            isMirrored: false,
            isAppDisconnected: true,
            currentWidth: currentWidth,
            currentHeight: currentHeight,
            currentPixelWidth: currentPixelWidth,
            currentPixelHeight: currentPixelHeight,
            refreshRate: refreshRate,
            scaleFactor: scaleFactor,
            isHiDPI: isHiDPI,
            rotation: rotation,
            modes: modes
        )
    }
}
