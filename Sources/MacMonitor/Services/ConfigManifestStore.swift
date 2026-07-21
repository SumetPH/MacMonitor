import Foundation

@MainActor
public final class ConfigManifestStore {
    public static let shared = ConfigManifestStore()
    
    private let fileManager = FileManager.default
    private var manifest = DisplayConfigManifest()
    
    private var appSupportURL: URL {
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("MacMonitor")
    }
    
    private var manifestURL: URL {
        return appSupportURL.appendingPathComponent("manifest.json")
    }
    
    private init() {
        loadManifest()
    }
    
    public func getManifest() -> DisplayConfigManifest {
        return manifest
    }
    
    @discardableResult
    public func registerCreatedFile(_ path: String) -> Bool {
        updateManifest { manifest in
            if !manifest.createdFiles.contains(path) {
                manifest.createdFiles.append(path)
            }
        }
    }
    
    @discardableResult
    public func unregisterCreatedFile(_ path: String) -> Bool {
        updateManifest { manifest in
            manifest.createdFiles.removeAll { $0 == path }
        }
    }
    
    @discardableResult
    public func registerBackup(originalPath: String, backupPath: String) -> Bool {
        updateManifest { manifest in
            manifest.backups[originalPath] = backupPath
        }
    }
    
    @discardableResult
    public func unregisterBackup(originalPath: String) -> Bool {
        updateManifest { manifest in
            manifest.backups.removeValue(forKey: originalPath)
        }
    }
    
    @discardableResult
    public func setExperimentalFlagsEnabled(_ enabled: Bool) -> Bool {
        updateManifest { manifest in
            manifest.experimentalFlagsEnabled = enabled
        }
    }
    
    public func isHiDPIEnabled(displayIdentifier: DisplayIdentifier) -> Bool {
        manifest.hiDPIEnabledDisplayIDs.contains(displayIdentifier.id)
    }
    
    @discardableResult
    public func setHiDPIEnabled(_ enabled: Bool, displayIdentifier: DisplayIdentifier) -> Bool {
        updateManifest { manifest in
            if enabled {
                if !manifest.hiDPIEnabledDisplayIDs.contains(displayIdentifier.id) {
                    manifest.hiDPIEnabledDisplayIDs.append(displayIdentifier.id)
                }
            } else {
                manifest.hiDPIEnabledDisplayIDs.removeAll { $0 == displayIdentifier.id }
            }
        }
    }
    
    @discardableResult
    public func clearManifest() -> Bool {
        updateManifest { manifest in
            manifest = DisplayConfigManifest()
        }
    }
    
    private func loadManifest() {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            self.manifest = try decoder.decode(DisplayConfigManifest.self, from: data)
        } catch {
            print("[ConfigManifestStore] Failed to load manifest: \(error.localizedDescription)")
        }
    }
    
    private func updateManifest(_ update: (inout DisplayConfigManifest) -> Void) -> Bool {
        var updatedManifest = manifest
        update(&updatedManifest)

        guard updatedManifest != manifest else { return true }

        do {
            try saveManifest(updatedManifest)
            manifest = updatedManifest
            return true
        } catch {
            print("[ConfigManifestStore] Failed to save manifest: \(error.localizedDescription)")
            return false
        }
    }

    private func saveManifest(_ manifest: DisplayConfigManifest) throws {
        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }
}
