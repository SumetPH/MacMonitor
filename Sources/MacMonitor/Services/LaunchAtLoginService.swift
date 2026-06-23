import Foundation
import ServiceManagement

@MainActor
public final class LaunchAtLoginService: ObservableObject {
    public static let shared = LaunchAtLoginService()
    
    @Published public private(set) var isEnabled: Bool = false
    
    private init() {
        refreshStatus()
    }
    
    public func refreshStatus() {
        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = false
        }
    }
    
    public func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    try service.register()
                    print("[LaunchAtLogin] Successfully registered Launch at Login")
                } else {
                    try service.unregister()
                    print("[LaunchAtLogin] Successfully unregistered Launch at Login")
                }
            } catch {
                print("[LaunchAtLogin] Error changing launch at login status: \(error)")
            }
            refreshStatus()
        } else {
            print("[LaunchAtLogin] Launch at Login is not supported on this macOS version")
        }
    }
}
