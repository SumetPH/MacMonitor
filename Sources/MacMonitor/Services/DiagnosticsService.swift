import Foundation
import CoreGraphics
import AppKit

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
            
            // Console log
            let status = success ? "SUCCESS" : "FAILED"
            print("[\(status)] Display \(displayID) - \(operation): \(details) \(errorDescription ?? "")")
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
        var report = "=== Mac Monitor Diagnostics Report ===\n"
        report += "Generated: \(Date().description)\n"
        report += "macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n\n"

        report += "=== WINDOW WORK AREA ===\n"
        report += "App Activation Policy: \(NSApp?.activationPolicy().rawValue.description ?? "Unavailable")\n"
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        report += "Dock Auto Hide: \(dockDefaults?.object(forKey: "autohide").map { String(describing: $0) } ?? "Unknown")\n"
        report += "Dock Position: \(dockDefaults?.string(forKey: "orientation") ?? "Unknown")\n"
        for screen in NSScreen.screens {
            report += "Screen: \(screen.localizedName)\n"
            report += "  Frame: \(screen.frame)\n"
            report += "  Visible Frame: \(screen.visibleFrame)\n"
            report += "  Reserved Bottom: \(screen.visibleFrame.minY - screen.frame.minY) points\n"
        }
        report += "\n"
        
        report += "=== CONNECTED DISPLAYS ===\n"
        for display in displays {
            report += "Display ID: \(display.displayID)\n"
            report += "  Name: \(display.name)\n"
            report += "  UUID: \(display.identifier.uuid ?? "Unknown")\n"
            report += "  Vendor ID: \(display.identifier.vendorID ?? 0) (0x\(String(display.identifier.vendorID ?? 0, radix: 16)))\n"
            report += "  Product ID: \(display.identifier.productID ?? 0) (0x\(String(display.identifier.productID ?? 0, radix: 16)))\n"
            report += "  Serial Number: \(display.identifier.serialNumber ?? 0)\n"
            report += "  Built-in: \(display.isBuiltIn)\n"
            report += "  Active: \(display.isActive)\n"
            report += "  Online: \(display.isOnline)\n"
            report += "  Asleep: \(display.isAsleep)\n"
            report += "  Main Display: \(display.isMain)\n"
            report += "  Mirrored: \(display.isMirrored)\n"
            report += "  Logical Resolution: \(display.currentWidth)x\(display.currentHeight)\n"
            report += "  Pixel Resolution: \(display.currentPixelWidth)x\(display.currentPixelHeight)\n"
            report += "  Refresh Rate: \(display.refreshRate) Hz\n"
            report += "  Scale Factor: \(display.scaleFactor)x\n"
            report += "  HiDPI: \(display.isHiDPI)\n"
            report += "  Rotation: \(display.rotation) degrees\n"
            report += "  Available Modes: \(display.modes.count)\n"
            for mode in display.modes {
                report += "    - \(mode.width)x\(mode.height) (Pixel: \(mode.pixelWidth)x\(mode.pixelHeight)) @ \(mode.refreshRate)Hz \(mode.isHiDPI ? "[HiDPI]" : "")\n"
            }
            report += "\n"
        }
        
        report += "=== RECENT OPERATION LOGS ===\n"
        let currentLogs = getLogs()
        if currentLogs.isEmpty {
            report += "No logs recorded yet.\n"
        } else {
            for log in currentLogs {
                let status = log.success ? "SUCCESS" : "FAILED"
                report += "[\(log.timestamp.description)] [\(status)] Display \(log.displayID) - \(log.operationType): \(log.details)\n"
                if let err = log.errorDescription {
                    report += "  Error: \(err)\n"
                }
            }
        }
        
        return report
    }
}
