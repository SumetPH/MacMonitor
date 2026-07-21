import Foundation

public struct UninstallReport {
    public let text: String
    public let hasWarnings: Bool
}

@MainActor
public final class UninstallService {
    public static let shared = UninstallService()

    private let fileManager = FileManager.default

    private var appSupportURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMonitor")
    }

    private var cacheURL: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.sumetph.MacMonitor")
    }

    private var logsURL: URL {
        fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MacMonitor")
    }

    private init() {}

    public func performUninstall(completion: @escaping (Result<UninstallReport, Error>) -> Void) {
        ClearConfigService.shared.performClearConfig(confirmBackupsRestore: true) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let cleanedItems):
                var reportLines = [
                    "=== Mac Monitor Data Cleanup Report ===",
                    "Timestamp: \(Date().description)",
                    "",
                    "=== CLEANED CONFIGURATION ITEMS ==="
                ]
                reportLines.append(contentsOf: cleanedItems.map { "- \($0)" })

                var warnings = cleanedItems.filter { $0.hasPrefix("Warning:") }
                let directories = [
                    (self.appSupportURL, "Application Support"),
                    (self.cacheURL, "Caches"),
                    (self.logsURL, "Logs")
                ]

                reportLines.append("")
                reportLines.append("=== REMOVED APP DATA ===")
                for (url, label) in directories {
                    guard self.fileManager.fileExists(atPath: url.path) else { continue }
                    do {
                        try self.fileManager.removeItem(at: url)
                        reportLines.append("- Removed \(label): \(url.path)")
                    } catch {
                        let warning = "Failed to remove \(label): \(error.localizedDescription)"
                        warnings.append(warning)
                        reportLines.append("- Warning: \(warning)")
                    }
                }

                reportLines.append("")
                reportLines.append("The Mac Monitor application file was not deleted. Move Mac Monitor.app to Trash to finish uninstalling.")
                reportLines.append(warnings.isEmpty ? "Data cleanup completed successfully." : "Data cleanup completed with warnings.")

                let desktopURL = self.fileManager.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                let reportURL = desktopURL.appendingPathComponent("MacMonitor_Uninstall_Report.txt")
                reportLines.append("Report location: \(reportURL.path)")

                var reportText = reportLines.joined(separator: "\n")
                do {
                    try reportText.write(to: reportURL, atomically: true, encoding: .utf8)
                } catch {
                    let warning = "Failed to save report: \(error.localizedDescription)"
                    warnings.append(warning)
                    reportText += "\nWarning: \(warning)"
                }

                completion(.success(UninstallReport(text: reportText, hasWarnings: !warnings.isEmpty)))
            }
        }
    }
}
