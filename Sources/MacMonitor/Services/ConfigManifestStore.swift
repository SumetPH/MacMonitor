import Foundation

@MainActor
public final class ConfigManifestStore {
    public static let shared = ConfigManifestStore()
    
    private let fileManager = FileManager.default
    private var manifest = DisplayConfigManifest()
    
    private var appSupportURL: URL {
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = urls[0].appendingPathComponent("MacMonitor")
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true, attributes: nil)
        return appSupport
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
    
    public func registerCreatedFile(_ path: String) {
        if !manifest.createdFiles.contains(path) {
            manifest.createdFiles.append(path)
            saveManifest()
        }
    }
    
    public func unregisterCreatedFile(_ path: String) {
        manifest.createdFiles.removeAll { $0 == path }
        saveManifest()
    }
    
    public func registerBackup(originalPath: String, backupPath: String) {
        manifest.backups[originalPath] = backupPath
        saveManifest()
    }
    
    public func unregisterBackup(originalPath: String) {
        manifest.backups.removeValue(forKey: originalPath)
        saveManifest()
    }
    
    public func setExperimentalFlagsEnabled(_ enabled: Bool) {
        manifest.experimentalFlagsEnabled = enabled
        saveManifest()
    }
    
    public func isHiDPIEnabled(displayIdentifier: DisplayIdentifier) -> Bool {
        manifest.hiDPIEnabledDisplayIDs.contains(displayIdentifier.id)
    }
    
    public func setHiDPIEnabled(_ enabled: Bool, displayIdentifier: DisplayIdentifier) {
        if enabled {
            if !manifest.hiDPIEnabledDisplayIDs.contains(displayIdentifier.id) {
                manifest.hiDPIEnabledDisplayIDs.append(displayIdentifier.id)
            }
        } else {
            manifest.hiDPIEnabledDisplayIDs.removeAll { $0 == displayIdentifier.id }
        }
        saveManifest()
    }
    
    public func clearManifest() {
        manifest = DisplayConfigManifest()
        saveManifest()
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
    
    private func saveManifest() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            print("[ConfigManifestStore] Failed to save manifest: \(error.localizedDescription)")
        }
    }
}
