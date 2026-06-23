import Foundation
import CoreGraphics

@_silgen_name("CGDisplayCreateUUIDFromDisplayID")
private func CGDisplayCreateUUIDFromDisplayID(_ display: CGDirectDisplayID) -> CFUUID?

public struct DisplayIdentifier: Codable, Hashable, Identifiable {
    public var id: String {
        if let uuid = uuid {
            return uuid
        }
        return "\(vendorID ?? 0)-\(productID ?? 0)-\(serialNumber ?? 0)"
    }
    
    public let displayID: CGDirectDisplayID
    public let uuid: String?
    public let vendorID: UInt32?
    public let productID: UInt32?
    public let serialNumber: UInt32?
    
    // Custom Equatable and Hashable to ignore transient displayID
    public static func == (lhs: DisplayIdentifier, rhs: DisplayIdentifier) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        
        if let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID) {
            let uuidObj = CFUUIDCreateString(nil, uuidRef)
            self.uuid = (uuidObj as String?)
        } else {
            self.uuid = nil
        }
        
        self.vendorID = CGDisplayVendorNumber(displayID)
        self.productID = CGDisplayModelNumber(displayID)
        self.serialNumber = CGDisplaySerialNumber(displayID)
    }
    
    public init(displayID: CGDirectDisplayID = kCGNullDirectDisplay, uuid: String?, vendorID: UInt32?, productID: UInt32?, serialNumber: UInt32?) {
        self.displayID = displayID
        self.uuid = uuid
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
    }
    
    public func matches(otherID: CGDirectDisplayID) -> Bool {
        let other = DisplayIdentifier(displayID: otherID)
        if let selfUUID = uuid, let otherUUID = other.uuid {
            return selfUUID == otherUUID
        }
        if vendorID == other.vendorID && productID == other.productID && serialNumber == other.serialNumber {
            return true
        }
        return false
    }
}
