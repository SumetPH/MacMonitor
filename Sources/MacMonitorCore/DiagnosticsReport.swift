import Foundation
import CoreGraphics

/// Builds the text of the diagnostics report. The app target gathers the inputs
/// (NSScreen, NSApp, Dock defaults) and passes them in.
public enum DiagnosticsReport {
    public struct ScreenWorkArea {
        public let name: String
        public let frame: CGRect
        public let visibleFrame: CGRect

        public init(name: String, frame: CGRect, visibleFrame: CGRect) {
            self.name = name
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    public struct Environment {
        public let generated: Date
        public let osVersion: String
        public let activationPolicy: String
        public let dockAutoHide: String
        public let dockPosition: String
        public let screens: [ScreenWorkArea]

        public init(
            generated: Date,
            osVersion: String,
            activationPolicy: String,
            dockAutoHide: String,
            dockPosition: String,
            screens: [ScreenWorkArea]
        ) {
            self.generated = generated
            self.osVersion = osVersion
            self.activationPolicy = activationPolicy
            self.dockAutoHide = dockAutoHide
            self.dockPosition = dockPosition
            self.screens = screens
        }
    }

    public static func make(
        environment: Environment,
        displays: [DisplayInfo],
        logs: [DisplayOperationResult]
    ) -> String {
        var report = "=== Mac Monitor Diagnostics Report ===\n"
        report += "Generated: \(environment.generated.description)\n"
        report += "macOS Version: \(environment.osVersion)\n\n"
        report += workAreaSection(environment)
        report += displaysSection(displays)
        report += logsSection(logs)
        return report
    }

    private static func workAreaSection(_ environment: Environment) -> String {
        var report = "=== WINDOW WORK AREA ===\n"
        report += "App Activation Policy: \(environment.activationPolicy)\n"
        report += "Dock Auto Hide: \(environment.dockAutoHide)\n"
        report += "Dock Position: \(environment.dockPosition)\n"
        for screen in environment.screens {
            report += "Screen: \(screen.name)\n"
            report += "  Frame: \(screen.frame)\n"
            report += "  Visible Frame: \(screen.visibleFrame)\n"
            report += "  Reserved Bottom: \(screen.visibleFrame.minY - screen.frame.minY) points\n"
        }
        report += "\n"
        return report
    }

    private static func displaysSection(_ displays: [DisplayInfo]) -> String {
        var report = "=== CONNECTED DISPLAYS ===\n"
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
        return report
    }

    private static func logsSection(_ logs: [DisplayOperationResult]) -> String {
        var report = "=== RECENT OPERATION LOGS ===\n"
        if logs.isEmpty {
            report += "No logs recorded yet.\n"
            return report
        }
        for log in logs {
            let status = log.success ? "SUCCESS" : "FAILED"
            report += "[\(log.timestamp.description)] [\(status)] Display \(log.displayID) - \(log.operationType): \(log.details)\n"
            if let err = log.errorDescription {
                report += "  Error: \(err)\n"
            }
        }
        return report
    }
}
