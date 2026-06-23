import Foundation

@MainActor
public final class UninstallService {
    public static let shared = UninstallService()
    
    private let fileManager = FileManager.default
    
    private var appSupportURL: URL {
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("MacMonitor")
    }
    
    private var cacheURL: URL {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("dev.sumetph.MacMonitor")
    }
    
    private var logsURL: URL {
        let urls = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("Logs/MacMonitor")
    }
    
    private init() {}
    
    public func performUninstall(completion: @escaping (Result<String, Error>) -> Void) {
        var report = "=== Mac Monitor Uninstall Report ===\n"
        report += "Timestamp: \(Date().description)\n\n"
        
        // 1. Perform Clear Config (with backup restore)
        ClearConfigService.shared.performClearConfig(confirmBackupsRestore: true) { result in
            switch result {
            case .success(let items):
                report += "=== CLEANED CONFIGURATION ITEMS ===\n"
                for item in items {
                    report += "- \(item)\n"
                }
                report += "\n"
            case .failure(let error):
                report += "Warning: Clear Config encountered error: \(error.localizedDescription)\n\n"
            }
            
            // 2. Remove Application Support Directory
            if self.fileManager.fileExists(atPath: self.appSupportURL.path) {
                do {
                    try self.fileManager.removeItem(at: self.appSupportURL)
                    report += "- Removed App Support folder: \(self.appSupportURL.path)\n"
                } catch {
                    report += "- Failed to remove App Support folder: \(error.localizedDescription)\n"
                }
            }
            
            // 3. Remove Cache Directory
            if self.fileManager.fileExists(atPath: self.cacheURL.path) {
                do {
                    try self.fileManager.removeItem(at: self.cacheURL)
                    report += "- Removed Caches folder: \(self.cacheURL.path)\n"
                } catch {
                    report += "- Failed to remove Caches folder: \(error.localizedDescription)\n"
                }
            }
            
            // 4. Remove Logs Directory
            if self.fileManager.fileExists(atPath: self.logsURL.path) {
                do {
                    try self.fileManager.removeItem(at: self.logsURL)
                    report += "- Removed Logs folder: \(self.logsURL.path)\n"
                } catch {
                    report += "- Failed to remove Logs folder: \(error.localizedDescription)\n"
                }
            }
            
            // Write report file to Desktop
            let desktopURL = self.fileManager.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let reportURL = desktopURL.appendingPathComponent("MacMonitor_Uninstall_Report.txt")
            
            do {
                try report.write(to: reportURL, atomically: true, encoding: .utf8)
                report += "\nUninstall completed successfully. A copy of this report has been saved to: \(reportURL.path)\n"
                completion(.success(report))
            } catch {
                report += "\nUninstall completed with warnings. Failed to save report file: \(error.localizedDescription)\n"
                completion(.success(report))
            }
        }
    }
}
