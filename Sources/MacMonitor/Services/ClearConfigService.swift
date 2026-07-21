import Foundation

public struct ClearConfigError: LocalizedError {
    public let issues: [String]

    public var errorDescription: String? {
        (["Reset could not be completed safely:"] + issues.map { "• \($0)" }).joined(separator: "\n")
    }
}

@MainActor
public final class ClearConfigService {
    public static let shared = ClearConfigService()

    private let fileManager = FileManager.default
    private let overridesPath = "/Library/Displays/Contents/Resources/Overrides"

    private var tempDirectoryURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMonitor/temp")
    }

    private init() {}

    public func cleanupPreview() -> [String] {
        let manifest = ConfigManifestStore.shared.getManifest()
        let managedPaths = Set(manifest.createdFiles).union(manifest.backups.keys).sorted()
        var items = managedPaths.map { path in
            guard isAllowedManagedPath(path) else {
                return "Blocked unsafe manifest path: \(path)"
            }
            if manifest.backups[path] != nil {
                return "Restore original file: \(path)"
            }
            return "Remove Mac Monitor file: \(path)"
        }
        items.append("Reset launch-at-login, shortcuts, and app preferences")
        items.append("Clear Mac Monitor recovery manifest and temporary files")
        return items
    }

    public func performClearConfig(
        confirmBackupsRestore: Bool,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let manifest = ConfigManifestStore.shared.getManifest()
        let managedPaths = Set(manifest.createdFiles).union(manifest.backups.keys).sorted()
        var completedItems: [String] = []
        var issues: [String] = []

        for path in managedPaths {
            guard isAllowedManagedPath(path) else {
                issues.append("Blocked unsafe manifest path: \(path)")
                continue
            }

            if let backupPath = manifest.backups[path] {
                guard confirmBackupsRestore else {
                    issues.append("Backup restore was not confirmed for \(path)")
                    continue
                }
                guard isAllowedBackupPath(backupPath),
                      fileManager.fileExists(atPath: backupPath) else {
                    issues.append("Backup is missing for \(path); the current file was left untouched")
                    continue
                }

                if restoreBackup(from: backupPath, to: path) {
                    completedItems.append("Restored original file: \(path)")
                    cleanupEmptyOverrideDirectory(containing: path)
                } else {
                    issues.append("Failed to restore backup for \(path)")
                }
            } else if removeManagedItem(atPath: path) {
                completedItems.append("Removed Mac Monitor file: \(path)")
                cleanupEmptyOverrideDirectory(containing: path)
            } else {
                issues.append("Failed to remove Mac Monitor file: \(path)")
            }
        }

        guard issues.isEmpty else {
            logIssues(issues)
            completion(.failure(ClearConfigError(issues: issues)))
            return
        }

        LaunchAtLoginService.shared.setEnabled(false)
        DisplayShortcutService.shared.clearShortcuts()
        let domain = Bundle.main.bundleIdentifier ?? "dev.sumetph.MacMonitor"
        UserDefaults.standard.removePersistentDomain(forName: domain)
        completedItems.append("Reset app preferences")

        guard ConfigManifestStore.shared.clearManifest() else {
            let manifestIssue = "System files were cleaned, but the recovery manifest could not be reset"
            logIssues([manifestIssue])
            completion(.failure(ClearConfigError(issues: [manifestIssue])))
            return
        }
        completedItems.append("Cleared app configuration manifest")

        if fileManager.fileExists(atPath: tempDirectoryURL.path) {
            do {
                try fileManager.removeItem(at: tempDirectoryURL)
                completedItems.append("Removed temporary override and backup files")
            } catch {
                completedItems.append("Warning: temporary files could not be removed: \(error.localizedDescription)")
            }
        }

        DiagnosticsService.shared.log(
            displayID: 0,
            operation: "clearConfig",
            success: true,
            details: completedItems.joined(separator: "; ")
        )
        completion(.success(completedItems))
    }

    private func restoreBackup(from backupPath: String, to originalPath: String) -> Bool {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: backupPath))
            do {
                try data.write(to: URL(fileURLWithPath: originalPath), options: .atomic)
                return true
            } catch {
                try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
                let stagedRestoreURL = tempDirectoryURL.appendingPathComponent("restore-\(UUID().uuidString).plist")
                try data.write(to: stagedRestoreURL, options: .atomic)
                defer { try? fileManager.removeItem(at: stagedRestoreURL) }
                return PrivilegedFileManager.shared.copyItem(fromPath: stagedRestoreURL.path, toPath: originalPath)
            }
        } catch {
            return false
        }
    }

    private func removeManagedItem(atPath path: String) -> Bool {
        guard fileManager.fileExists(atPath: path) else { return true }

        do {
            try fileManager.removeItem(atPath: path)
            return true
        } catch {
            return PrivilegedFileManager.shared.removeItem(atPath: path)
        }
    }

    private func cleanupEmptyOverrideDirectory(containing path: String) {
        let fileURL = URL(fileURLWithPath: path)
        let directoryURL = fileURL.deletingLastPathComponent()
        guard directoryURL.path.hasPrefix(overridesPath + "/"),
              directoryURL.lastPathComponent.hasPrefix("DisplayVendorID-") else {
            return
        }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: directoryURL.path),
              contents.isEmpty else {
            return
        }

        do {
            try fileManager.removeItem(at: directoryURL)
        } catch {
            _ = PrivilegedFileManager.shared.removeDirectoryIfEmpty(atPath: directoryURL.path)
        }
    }

    private func isAllowedManagedPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let directoryURL = url.deletingLastPathComponent()
        return directoryURL.deletingLastPathComponent().path == overridesPath &&
               directoryURL.lastPathComponent.hasPrefix("DisplayVendorID-") &&
               url.lastPathComponent.hasPrefix("DisplayProductID-")
    }

    private func isAllowedBackupPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let allowedDirectory = tempDirectoryURL.standardizedFileURL.path + "/"
        guard url.path.hasPrefix(allowedDirectory) else { return false }

        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType != .typeSymbolicLink
    }

    private func logIssues(_ issues: [String]) {
        DiagnosticsService.shared.log(
            displayID: 0,
            operation: "clearConfig",
            success: false,
            details: issues.joined(separator: "; ")
        )
    }
}
