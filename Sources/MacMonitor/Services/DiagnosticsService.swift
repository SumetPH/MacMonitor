import Foundation
import CoreGraphics
import AppKit
import MacMonitorCore
import os

private let logger = Logger(category: "DiagnosticsService")

public final class DiagnosticsService: @unchecked Sendable {
    public static let shared = DiagnosticsService()
    
    private var logs: [DisplayOperationResult] = []
    private let queue = DispatchQueue(label: "com.macmonitor.DiagnosticsService", attributes: .concurrent)
    
    private init() {}
    
    public func log(displayID: CGDirectDisplayID, operation: String, success: Bool, details: String, errorDescription: String? = nil) {
        let result = DisplayOperationResult(
            displayID: displayID,
            operationType: operation,
            success: success,
            details: details,
            errorDescription: errorDescription
        )
        
        queue.async(flags: .barrier) {
            self.logs.append(result)
            // Limit to last 200 logs
            if self.logs.count > 200 {
                self.logs.removeFirst()
            }
            
            let message = "Display \(displayID) - \(operation): \(details) \(errorDescription ?? "")"
            if success {
                logger.info("[SUCCESS] \(message, privacy: .public)")
            } else {
                logger.error("[FAILED] \(message, privacy: .public)")
            }
        }
    }
    
    public func getLogs() -> [DisplayOperationResult] {
        var result: [DisplayOperationResult] = []
        queue.sync {
            result = self.logs
        }
        return result
    }
    
    public func clearLogs() {
        queue.async(flags: .barrier) {
            self.logs.removeAll()
        }
    }
    
    @MainActor
    public func generateReport(displays: [DisplayInfo]) -> String {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        let environment = DiagnosticsReport.Environment(
            generated: Date(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            activationPolicy: NSApp?.activationPolicy().rawValue.description ?? "Unavailable",
            dockAutoHide: dockDefaults?.object(forKey: "autohide").map { String(describing: $0) } ?? "Unknown",
            dockPosition: dockDefaults?.string(forKey: "orientation") ?? "Unknown",
            screens: NSScreen.screens.map {
                DiagnosticsReport.ScreenWorkArea(name: $0.localizedName, frame: $0.frame, visibleFrame: $0.visibleFrame)
            }
        )
        return DiagnosticsReport.make(environment: environment, displays: displays, logs: getLogs())
    }
}
