import Foundation
import CoreGraphics

public struct DisplayModeInfo: Codable, Hashable, Identifiable {
    public var id: String {
        return "\(width)x\(height)@\(String(format: "%.2f", refreshRate))-\(pixelWidth)x\(pixelHeight)-\(ioFlags)"
    }
    
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isHiDPI: Bool
    public let ioFlags: UInt32
    
    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double, ioFlags: UInt32) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.ioFlags = ioFlags
        // HiDPI is defined when pixel dimensions are larger than logical dimensions (typically 2x or scaled)
        self.isHiDPI = pixelWidth > width || pixelHeight > height
    }
    
    public init(cgMode: CGDisplayMode) {
        self.width = cgMode.width
        self.height = cgMode.height
        self.pixelWidth = cgMode.pixelWidth
        self.pixelHeight = cgMode.pixelHeight
        
        let rate = cgMode.refreshRate
        // Fallback for ProMotion or zero refresh rate from Apple Silicon
        self.refreshRate = rate == 0 ? 60.0 : rate
        self.ioFlags = cgMode.ioFlags
        self.isHiDPI = self.pixelWidth > self.width || self.pixelHeight > self.height
    }
}
