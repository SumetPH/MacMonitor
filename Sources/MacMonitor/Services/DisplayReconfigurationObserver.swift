import Foundation
import CoreGraphics

extension Notification.Name {
    public static let displayReconfiguration = Notification.Name("MacMonitorDisplayReconfigurationNotification")
}

private func reconfigurationCallback(
    displayID: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    // Only trigger update when the change is complete (i.e. not in-progress/before)
    // Flags that indicate completion usually don't have kCGDisplayBeginConfigurationFlag
    let isBegin = flags.contains(.beginConfigurationFlag)
    if !isBegin {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .displayReconfiguration,
                object: nil,
                userInfo: [
                    "displayID": displayID,
                    "flags": flags.rawValue
                ]
            )
        }
    }
}

@MainActor
public final class DisplayReconfigurationObserver {
    private var isListening = false
    
    public static let shared = DisplayReconfigurationObserver()
    
    private init() {}
    
    public func startListening() {
        guard !isListening else { return }
        
        let result = CGDisplayRegisterReconfigurationCallback(reconfigurationCallback, nil)
        if result == .success {
            isListening = true
            print("[DisplayReconfigurationObserver] Registered display reconfiguration callback successfully.")
        } else {
            print("[DisplayReconfigurationObserver] Failed to register display reconfiguration callback: \(result)")
        }
    }
    
    public func stopListening() {
        guard isListening else { return }
        
        let result = CGDisplayRemoveReconfigurationCallback(reconfigurationCallback, nil)
        if result == .success {
            isListening = false
            print("[DisplayReconfigurationObserver] Removed display reconfiguration callback successfully.")
        } else {
            print("[DisplayReconfigurationObserver] Failed to remove display reconfiguration callback: \(result)")
        }
    }
}
