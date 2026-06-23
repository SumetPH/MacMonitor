import Foundation
import CoreGraphics

@MainActor
public final class DisplayModeService {
    public static let shared = DisplayModeService()
    
    // Store original mode before switching for rollback
    private var originalModes: [CGDirectDisplayID: CGDisplayMode] = [:]
    private var rollbackTimer: Timer?
    private var rollbackDisplayID: CGDirectDisplayID?
    
    private init() {}
    
    public func getAvailableModes(for displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [
            kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue
        ] as CFDictionary
        
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "getAvailableModes",
                success: false,
                details: "Failed to copy all display modes."
            )
            return []
        }
        return modes
    }
    
    public func getCurrentMode(for displayID: CGDirectDisplayID) -> CGDisplayMode? {
        return CGDisplayCopyDisplayMode(displayID)
    }
    
    @discardableResult
    public func switchMode(displayID: CGDirectDisplayID, targetMode: CGDisplayMode, autoRollback: Bool = true, onRollback: (@Sendable () -> Void)? = nil) -> Bool {
        // Save current mode before making changes
        guard let currentMode = getCurrentMode(for: displayID) else {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "switchMode",
                success: false,
                details: "Failed to get current display mode for backup."
            )
            return false
        }
        
        originalModes[displayID] = currentMode
        
        var configRef: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&configRef)
        
        guard error == .success, let config = configRef else {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "switchMode",
                success: false,
                details: "Failed to begin display configuration.",
                errorDescription: "Error code: \(error.rawValue)"
            )
            return false
        }
        
        error = CGConfigureDisplayWithDisplayMode(config, displayID, targetMode, nil)
        if error != .success {
            CGCancelDisplayConfiguration(config)
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "switchMode",
                success: false,
                details: "Failed to configure display mode.",
                errorDescription: "Error code: \(error.rawValue)"
            )
            return false
        }
        
        error = CGCompleteDisplayConfiguration(config, .permanently)
        if error != .success {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "switchMode",
                success: false,
                details: "Failed to complete display configuration.",
                errorDescription: "Error code: \(error.rawValue)"
            )
            return false
        }
        
        DiagnosticsService.shared.log(
            displayID: displayID,
            operation: "switchMode",
            success: true,
            details: "Switched resolution to \(targetMode.width)x\(targetMode.height) @ \(String(format: "%.1f", targetMode.refreshRate))Hz"
        )
        
        if autoRollback {
            startRollbackTimer(displayID: displayID, onRollback: onRollback)
        }
        
        return true
    }
    
    public func confirmModeChange() {
        // Cancel the rollback timer, user has confirmed the mode works
        rollbackTimer?.invalidate()
        rollbackTimer = nil
        rollbackDisplayID = nil
        print("[DisplayModeService] User confirmed resolution change. Rollback cancelled.")
    }
    
    public func revertModeChange() {
        guard let displayID = rollbackDisplayID else { return }
        rollbackTimer?.invalidate()
        rollbackTimer = nil
        performRollback(for: displayID)
    }
    
    private func startRollbackTimer(displayID: CGDirectDisplayID, onRollback: (@Sendable () -> Void)?) {
        rollbackTimer?.invalidate()
        rollbackDisplayID = displayID
        
        // 15 seconds confirmation window
        rollbackTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                print("[DisplayModeService] Rollback timer expired without confirmation. Reverting resolution...")
                self.performRollback(for: displayID)
                onRollback?()
            }
        }
    }
    
    private func performRollback(for displayID: CGDirectDisplayID) {
        guard let originalMode = originalModes[displayID] else {
            print("[DisplayModeService] Error: No backup mode found to rollback for display \(displayID).")
            return
        }
        
        var configRef: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&configRef)
        
        if error == .success, let config = configRef {
            error = CGConfigureDisplayWithDisplayMode(config, displayID, originalMode, nil)
            if error == .success {
                error = CGCompleteDisplayConfiguration(config, .permanently)
                if error == .success {
                    DiagnosticsService.shared.log(
                        displayID: displayID,
                        operation: "rollbackMode",
                        success: true,
                        details: "Successfully rolled back to resolution \(originalMode.width)x\(originalMode.height) @ \(String(format: "%.1f", originalMode.refreshRate))Hz"
                    )
                } else {
                    DiagnosticsService.shared.log(
                        displayID: displayID,
                        operation: "rollbackMode",
                        success: false,
                        details: "Failed to complete rollback configuration.",
                        errorDescription: "Error code: \(error.rawValue)"
                    )
                }
            } else {
                CGCancelDisplayConfiguration(config)
                DiagnosticsService.shared.log(
                    displayID: displayID,
                    operation: "rollbackMode",
                    success: false,
                    details: "Failed to configure rollback display mode.",
                    errorDescription: "Error code: \(error.rawValue)"
                )
            }
        } else {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "rollbackMode",
                success: false,
                details: "Failed to begin display configuration for rollback.",
                errorDescription: "Error code: \(error.rawValue)"
            )
        }
        
        originalModes.removeValue(forKey: displayID)
        rollbackDisplayID = nil
    }
}
