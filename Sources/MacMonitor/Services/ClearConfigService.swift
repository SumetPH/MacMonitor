import Foundation

@MainActor
public final class ClearConfigService {
    public static let shared = ClearConfigService()
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    public func performClearConfig(confirmBackupsRestore: Bool, completion: @escaping (Result<[String], Error>) -> Void) {
        var removedItems: [String] = []
        let manifest = ConfigManifestStore.shared.getManifest()
        
        // 1. Remove app-created files (e.g. plist overrides, etc.)
        for file in manifest.createdFiles {
            if fileManager.fileExists(atPath: file) {
                do {
                    try fileManager.removeItem(atPath: file)
                    removedItems.append("Removed file: \(file)")
                    DiagnosticsService.shared.log(
                        displayID: 0,
                        operation: "clearConfig",
                        success: true,
                        details: "Removed created file: \(file)"
                    )
                } catch {
                    // Try with privileges
                    if PrivilegedFileManager.shared.removeItem(atPath: file) {
                        removedItems.append("Removed file (with admin privileges): \(file)")
                        DiagnosticsService.shared.log(
                            displayID: 0,
                            operation: "clearConfig",
                            success: true,
                            details: "Removed created file with admin privileges: \(file)"
                        )
                    } else {
                        DiagnosticsService.shared.log(
                            displayID: 0,
                            operation: "clearConfig",
                            success: false,
                            details: "Failed to remove created file: \(file)",
                            errorDescription: error.localizedDescription
                        )
                    }
                }
            }
        }
        
        // 2. Restore backed up files
        if confirmBackupsRestore {
            for (original, backup) in manifest.backups {
                if fileManager.fileExists(atPath: backup) {
                    do {
                        if fileManager.fileExists(atPath: original) {
                            try fileManager.removeItem(atPath: original)
                        }
                        try fileManager.copyItem(atPath: backup, toPath: original)
                        removedItems.append("Restored backup: \(original)")
                        DiagnosticsService.shared.log(
                            displayID: 0,
                            operation: "clearConfig",
                            success: true,
                            details: "Restored backup file to original: \(original)"
                        )
                    } catch {
                        // Try restoring with privileges
                        _ = PrivilegedFileManager.shared.removeItem(atPath: original)
                        if PrivilegedFileManager.shared.copyItem(fromPath: backup, toPath: original) {
                            removedItems.append("Restored backup (with admin privileges): \(original)")
                            DiagnosticsService.shared.log(
                                displayID: 0,
                                operation: "clearConfig",
                                success: true,
                                details: "Restored backup file to original with admin privileges: \(original)"
                            )
                        } else {
                            DiagnosticsService.shared.log(
                                displayID: 0,
                                operation: "clearConfig",
                                success: false,
                                details: "Failed to restore backup to: \(original)",
                                errorDescription: error.localizedDescription
                            )
                        }
                    }
                }
            }
        }
        
        // 3. Clear Presets
        DisplayPresetStore.shared.clearPresets()
        removedItems.append("Cleared all display presets")
        
        // 4. Reset User Preferences
        LaunchAtLoginService.shared.setEnabled(false)
        let domain = Bundle.main.bundleIdentifier ?? "dev.sumetph.MacMonitor"
        UserDefaults.standard.removePersistentDomain(forName: domain)
        removedItems.append("Reset app preferences")
        
        // 5. Reset Experimental Flags
        ConfigManifestStore.shared.clearManifest()
        removedItems.append("Cleared app configuration manifest")
        
        completion(.success(removedItems))
    }
}
