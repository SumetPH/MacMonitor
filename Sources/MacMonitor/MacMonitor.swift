import SwiftUI
import AppKit

@main
struct MacMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Settings scene is defined but empty, we don't show any window on startup.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Hides dock icon, makes the app run strictly as menu bar accessory
        NSApp.setActivationPolicy(.accessory)
        
        // Load configurations
        _ = ConfigManifestStore.shared
        _ = DiagnosticsService.shared
        
        // Instantiate MenuBarController
        menuBarController = MenuBarController()
        
        print("[AppDelegate] Mac Monitor started successfully.")
    }
}
