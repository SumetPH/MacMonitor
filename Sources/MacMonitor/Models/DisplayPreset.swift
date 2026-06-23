import Foundation

public struct DisplayPreset: Codable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    
    // Target display identifiers
    public let displayUUID: String?
    public let displayVendorID: UInt32?
    public let displayProductID: UInt32?
    public let displaySerialNumber: UInt32?
    
    // Resolution and Display Settings
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isHiDPI: Bool
    public let rotation: Int
    public let brightness: Double?
    public let isEnabled: Bool
    
    // Automatic apply option
    public var autoApply: Bool
    
    public init(
        id: UUID = UUID(),
        name: String,
        displayUUID: String?,
        displayVendorID: UInt32?,
        displayProductID: UInt32?,
        displaySerialNumber: UInt32?,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        isHiDPI: Bool,
        rotation: Int,
        brightness: Double? = nil,
        isEnabled: Bool = true,
        autoApply: Bool = false
    ) {
        self.id = id
        self.name = name
        self.displayUUID = displayUUID
        self.displayVendorID = displayVendorID
        self.displayProductID = displayProductID
        self.displaySerialNumber = displaySerialNumber
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.isHiDPI = isHiDPI
        self.rotation = rotation
        self.brightness = brightness
        self.isEnabled = isEnabled
        self.autoApply = autoApply
    }
    
    public func matches(display: DisplayInfo) -> Bool {
        if let uuid = displayUUID, let displayUUID = display.identifier.uuid {
            return uuid == displayUUID
        }
        if displayVendorID == display.identifier.vendorID &&
            displayProductID == display.identifier.productID &&
            displaySerialNumber == display.identifier.serialNumber {
            return true
        }
        return false
    }
}
