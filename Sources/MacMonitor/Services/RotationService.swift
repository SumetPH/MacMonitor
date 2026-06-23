import Foundation
import CoreGraphics

@MainActor
public final class RotationService {
    public static let shared = RotationService()
    
    private typealias CGConfigureDisplayRotationType = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Int32) -> CGError
    private typealias SLSSetDisplayRotationType = @convention(c) (CGDirectDisplayID, Int32) -> CGError
    
    private let configureDisplayRotation: CGConfigureDisplayRotationType?
    private let setDisplayRotation: SLSSetDisplayRotationType?
    private var lastSkyLightErrorDescription: String?
    
    private init() {
        let processHandle = dlopen(nil, RTLD_LAZY)
        let skyLightHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        
        if let sym = dlsym(processHandle, "CGConfigureDisplayRotation") {
            configureDisplayRotation = unsafeBitCast(sym, to: CGConfigureDisplayRotationType.self)
        } else {
            configureDisplayRotation = nil
        }
        
        if let sym = RotationService.resolveSymbol("SLSSetDisplayRotation", handles: [skyLightHandle, processHandle]) {
            setDisplayRotation = unsafeBitCast(sym, to: SLSSetDisplayRotationType.self)
        } else {
            setDisplayRotation = nil
        }
    }
    
    private static func resolveSymbol(_ name: String, handles: [UnsafeMutableRawPointer?]) -> UnsafeMutableRawPointer? {
        for handle in handles {
            if let symbol = dlsym(handle, name) {
                return symbol
            }
        }
        return nil
    }
    
    public func getCurrentRotation(for displayID: CGDirectDisplayID) -> Int {
        // CGDisplayRotation returns Double: 0.0, 90.0, 180.0, 270.0
        let rotation = CGDisplayRotation(displayID)
        return Int(rotation)
    }
    
    public func canRotate(displayID: CGDirectDisplayID) -> Bool {
        setDisplayRotation != nil || configureDisplayRotation != nil
    }

    
    @discardableResult
    public func rotate(displayID: CGDirectDisplayID, to angle: Int) -> Bool {
        guard [0, 90, 180, 270].contains(angle) else {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "rotate",
                success: false,
                details: "Invalid rotation angle: \(angle). Supported angles are 0, 90, 180, 270."
            )
            return false
        }
        
        let currentRotation = getCurrentRotation(for: displayID)
        if currentRotation == angle {
            return true // Already in the target rotation
        }
        
        if rotateWithSkyLight(displayID: displayID, angle: angle) {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "rotate",
                success: true,
                details: "Rotated display from \(currentRotation) to \(angle) degrees via SLSSetDisplayRotation."
            )
            return true
        }
        
        return rotateWithCoreGraphics(displayID: displayID, angle: angle, currentRotation: currentRotation)
    }
    
    private func rotateWithSkyLight(displayID: CGDirectDisplayID, angle: Int) -> Bool {
        lastSkyLightErrorDescription = nil
        
        guard let setDisplayRotation else {
            lastSkyLightErrorDescription = "SLSSetDisplayRotation symbol is unavailable."
            return false
        }
        
        let error = setDisplayRotation(displayID, Int32(angle))
        if error == .success {
            return true
        }
        
        lastSkyLightErrorDescription = "SLSSetDisplayRotation returned error code: \(error.rawValue)."
        return false
    }
    
    private func rotateWithCoreGraphics(displayID: CGDirectDisplayID, angle: Int, currentRotation: Int) -> Bool {
        guard let configureDisplayRotation else {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "rotate",
                success: false,
                details: "Rotation APIs failed or are unavailable. SkyLight loaded: \(setDisplayRotation != nil), CoreGraphics loaded: false.",
                errorDescription: lastSkyLightErrorDescription
            )
            return false
        }
        
        var configRef: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&configRef)
        
        guard error == .success, let config = configRef else {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "rotate",
                success: false,
                details: "Failed to begin display configuration for rotation.",
                errorDescription: "Error code: \(error.rawValue)"
            )
            return false
        }
        
        error = configureDisplayRotation(config, displayID, Int32(angle))
        if error != .success {
            CGCancelDisplayConfiguration(config)
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "rotate",
                success: false,
                details: "Failed to configure display rotation. Display might not support rotation.",
                errorDescription: [lastSkyLightErrorDescription, "CGConfigureDisplayRotation error code: \(error.rawValue)."]
                    .compactMap { $0 }
                    .joined(separator: " ")
            )
            return false
        }
        
        error = CGCompleteDisplayConfiguration(config, .permanently)
        if error != .success {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "rotate",
                success: false,
                details: "Failed to complete display configuration for rotation.",
                errorDescription: "Error code: \(error.rawValue)"
            )
            return false
        }
        
        DiagnosticsService.shared.log(
            displayID: displayID,
            operation: "rotate",
            success: true,
            details: "Rotated display from \(currentRotation) to \(angle) degrees via CGConfigureDisplayRotation."
        )
        return true
    }
}
