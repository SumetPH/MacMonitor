import Foundation

public struct DisplayConfigManifest: Codable, Hashable {
    public var createdFiles: [String] // Paths of files created by the app (e.g. override configs, launch agents)
    public var backups: [String: String] // Original file path -> Backup file path
    public var experimentalFlagsEnabled: Bool
    public var hiDPIEnabledDisplayIDs: [String]
    
    public init(
        createdFiles: [String] = [],
        backups: [String : String] = [:],
        experimentalFlagsEnabled: Bool = false,
        hiDPIEnabledDisplayIDs: [String] = []
    ) {
        self.createdFiles = createdFiles
        self.backups = backups
        self.experimentalFlagsEnabled = experimentalFlagsEnabled
        self.hiDPIEnabledDisplayIDs = hiDPIEnabledDisplayIDs
    }
    
    private enum CodingKeys: String, CodingKey {
        case createdFiles
        case backups
        case experimentalFlagsEnabled
        case hiDPIEnabledDisplayIDs
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.createdFiles = try container.decodeIfPresent([String].self, forKey: .createdFiles) ?? []
        self.backups = try container.decodeIfPresent([String: String].self, forKey: .backups) ?? [:]
        self.experimentalFlagsEnabled = try container.decodeIfPresent(Bool.self, forKey: .experimentalFlagsEnabled) ?? false
        self.hiDPIEnabledDisplayIDs = try container.decodeIfPresent([String].self, forKey: .hiDPIEnabledDisplayIDs) ?? []
    }
}
