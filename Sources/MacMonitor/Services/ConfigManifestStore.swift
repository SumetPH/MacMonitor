import Foundation
import MacMonitorCore
import os

private let logger = Logger(category: "ConfigManifestStore")

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
        updateManifest { $0.registerCreatedFile(path) }
    }
    
    @discardableResult
    public func unregisterCreatedFile(_ path: String) -> Bool {
        updateManifest { $0.unregisterCreatedFile(path) }
    }
    
    @discardableResult
    public func registerBackup(originalPath: String, backupPath: String) -> Bool {
        updateManifest { $0.registerBackup(originalPath: originalPath, backupPath: backupPath) }
    }
    
    @discardableResult
    public func unregisterBackup(originalPath: String) -> Bool {
        updateManifest { $0.unregisterBackup(originalPath: originalPath) }
    }
    
    @discardableResult
    public func setExperimentalFlagsEnabled(_ enabled: Bool) -> Bool {
        updateManifest { $0.experimentalFlagsEnabled = enabled }
    }
    
    public func isHiDPIEnabled(displayIdentifier: DisplayIdentifier) -> Bool {
        manifest.isHiDPIEnabled(displayIdentifier: displayIdentifier)
    }
    
    @discardableResult
    public func setHiDPIEnabled(_ enabled: Bool, displayIdentifier: DisplayIdentifier) -> Bool {
        updateManifest { $0.setHiDPIEnabled(enabled, displayIdentifier: displayIdentifier) }
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
            logger.error("Failed to load manifest: \(error.localizedDescription, privacy: .public)")
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
            logger.error("Failed to save manifest: \(error.localizedDescription, privacy: .public)")
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
