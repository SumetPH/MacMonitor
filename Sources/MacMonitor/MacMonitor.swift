import AppKit

@main
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?
    private var menuBarController: MenuBarController?

    public static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        application.run()
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Hides dock icon, makes the app run strictly as menu bar accessory
        NSApp.setActivationPolicy(.accessory)
        
        // Load configurations
        _ = ConfigManifestStore.shared
        _ = DiagnosticsService.shared
        _ = DisplayManager.shared
        _ = DisplayShortcutService.shared
        DisplayNotificationService.shared.requestAuthorization()
        
        // Instantiate MenuBarController
        menuBarController = MenuBarController()
        menuBarController?.showMenuTemporarilyIfNeeded()
        
        print("[AppDelegate] Mac Monitor started successfully.")
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarController?.openSettingsWindow()
        return true
    }
}
