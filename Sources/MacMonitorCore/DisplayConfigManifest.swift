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

// MARK: - Mutations used by ConfigManifestStore

extension DisplayConfigManifest {
    /// Every path the manifest manages: created files plus originals that have a backup.
    public var managedPaths: [String] {
        Set(createdFiles).union(backups.keys).sorted()
    }

    public func isHiDPIEnabled(displayIdentifier: DisplayIdentifier) -> Bool {
        hiDPIEnabledDisplayIDs.contains(displayIdentifier.id)
    }

    public mutating func registerCreatedFile(_ path: String) {
        if !createdFiles.contains(path) {
            createdFiles.append(path)
        }
    }

    public mutating func unregisterCreatedFile(_ path: String) {
        createdFiles.removeAll { $0 == path }
    }

    public mutating func registerBackup(originalPath: String, backupPath: String) {
        backups[originalPath] = backupPath
    }

    public mutating func unregisterBackup(originalPath: String) {
        backups.removeValue(forKey: originalPath)
    }

    public mutating func setHiDPIEnabled(_ enabled: Bool, displayIdentifier: DisplayIdentifier) {
        if enabled {
            if !hiDPIEnabledDisplayIDs.contains(displayIdentifier.id) {
                hiDPIEnabledDisplayIDs.append(displayIdentifier.id)
            }
        } else {
            hiDPIEnabledDisplayIDs.removeAll { $0 == displayIdentifier.id }
        }
    }

    /// Human-readable list of what Clear Config will do with this manifest.
    public func cleanupPreview() -> [String] {
        var items = managedPaths.map { path in
            guard DisplayOverride.isManagedOverridePath(path) else {
                return "Blocked unsafe manifest path: \(path)"
            }
            if backups[path] != nil {
                return "Restore original file: \(path)"
            }
            return "Remove Mac Monitor file: \(path)"
        }
        items.append("Reset launch-at-login, shortcuts, and app preferences")
        items.append("Clear Mac Monitor recovery manifest and temporary files")
        return items
    }
}
