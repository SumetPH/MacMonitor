import Foundation
import CoreGraphics

public struct DisplayOperationResult: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID {
        return uuid
    }
    
    public let uuid: UUID
    public let timestamp: Date
    public let displayID: CGDirectDisplayID
    public let operationType: String
    public let success: Bool
    public let details: String
    public let errorDescription: String?
    
    public init(displayID: CGDirectDisplayID, operationType: String, success: Bool, details: String, errorDescription: String? = nil) {
        self.uuid = UUID()
        self.timestamp = Date()
        self.displayID = displayID
        self.operationType = operationType
        self.success = success
        self.details = details
        self.errorDescription = errorDescription
    }
}
