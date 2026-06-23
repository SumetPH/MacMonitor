import Foundation
import CoreGraphics

@MainActor
public final class DisplayConnectionService {
    public static let shared = DisplayConnectionService()
    
    private typealias CGSConfigureDisplayEnabledType = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Int32) -> CGError
    
    private let configureDisplayEnabled: CGSConfigureDisplayEnabledType?
    
    private init() {
        let handle = dlopen(nil, RTLD_LAZY)
        guard let symbol = dlsym(handle, "CGSConfigureDisplayEnabled") else {
            configureDisplayEnabled = nil
            return
        }
        
        configureDisplayEnabled = unsafeBitCast(symbol, to: CGSConfigureDisplayEnabledType.self)
    }
    
    public var isAvailable: Bool {
        configureDisplayEnabled != nil
    }
    
    @discardableResult
    public func setEnabled(displayID: CGDirectDisplayID, enabled: Bool) -> Bool {
        guard let configureDisplayEnabled else {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: enabled ? "softConnectDisplay" : "softDisconnectDisplay",
                success: false,
                details: "Private CGSConfigureDisplayEnabled symbol is unavailable."
            )
            return false
        }
        
        var configRef: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&configRef)
        guard error == .success, let config = configRef else {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: enabled ? "softConnectDisplay" : "softDisconnectDisplay",
                success: false,
                details: "Failed to begin display configuration.",
                errorDescription: "Error code: \(error.rawValue)"
            )
            return false
        }
        
        error = configureDisplayEnabled(config, displayID, enabled ? 1 : 0)
        guard error == .success else {
            CGCancelDisplayConfiguration(config)
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: enabled ? "softConnectDisplay" : "softDisconnectDisplay",
                success: false,
                details: "Failed to configure display enabled state.",
                errorDescription: "Error code: \(error.rawValue)"
            )
            return false
        }
        
        error = CGCompleteDisplayConfiguration(config, .permanently)
        guard error == .success else {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: enabled ? "softConnectDisplay" : "softDisconnectDisplay",
                success: false,
                details: "Failed to complete display configuration.",
                errorDescription: "Error code: \(error.rawValue)"
            )
            return false
        }
        
        DiagnosticsService.shared.log(
            displayID: displayID,
            operation: enabled ? "softConnectDisplay" : "softDisconnectDisplay",
            success: true,
            details: "Set display enabled state to \(enabled ? "enabled" : "disabled") via CGSConfigureDisplayEnabled."
        )
        return true
    }
}
