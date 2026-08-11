import AppKit
import SwiftUI
import CoreGraphics

@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    
    public override init() {
        super.init()
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        
        // Premium system icon for display controller
        button.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "Mac Monitor")
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        var displays = DisplayManager.shared.displays
        if displays.isEmpty {
            // Force synchronous refresh if displays list is empty on menu open
            DisplayManager.shared.refreshDisplays(forceSync: true)
            displays = DisplayManager.shared.displays
        }
        
        if displays.isEmpty {
            menu.addItem(NSMenuItem(title: "No connected displays found", action: nil, keyEquivalent: ""))
        } else {
            for display in displays {
                let isDisabled = display.isAppDisconnected || DisplayPowerService.shared.isDisplayDisabled(display.displayID)
                let displayTitle = "\(display.name) (\(display.currentWidth)x\(display.currentHeight)\(display.isHiDPI ? " [HiDPI]" : "") @ \(Int(display.refreshRate))Hz)"
                
                let displayItem = NSMenuItem(title: displayTitle, action: nil, keyEquivalent: "")
                if isDisabled {
                    displayItem.attributedTitle = NSAttributedString(
                        string: "\(display.name) [Disabled]",
                        attributes: [.foregroundColor: NSColor.disabledControlTextColor]
                    )
                }
                
                // Add submenu for this display
                let displaySubmenu = NSMenu()
                populateDisplaySubmenu(displaySubmenu, for: display)
                displayItem.submenu = displaySubmenu
                
                menu.addItem(displayItem)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Menu utilities
        let reconnectItem = NSMenuItem(title: "Reconnect Displays", action: #selector(resetDisplayConnectionsAction), keyEquivalent: "")
        reconnectItem.target = self
        menu.addItem(reconnectItem)
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let diagnosticsItem = NSMenuItem(title: "Export Diagnostics...", action: #selector(exportDiagnosticsAction), keyEquivalent: "")
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Mac Monitor", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    private func populateDisplaySubmenu(_ menu: NSMenu, for display: DisplayInfo) {
        let isDisabled = display.isAppDisconnected || DisplayPowerService.shared.isDisplayDisabled(display.displayID)
        
        // 1. Power Toggle
        let powerItem = NSMenuItem(
            title: isDisabled ? "Enable Display" : "Disable Display",
            action: #selector(toggleDisplayPowerAction(_:)),
            keyEquivalent: ""
        )
        powerItem.target = self
        powerItem.representedObject = display
        powerItem.isEnabled = isDisabled || !display.isMain // Cannot disable the primary display
        menu.addItem(powerItem)
        
        if isDisabled {
            return // Show no further options if display is powered off/disabled
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Quick Resolutions
        let resItem = NSMenuItem(title: "Resolutions", action: nil, keyEquivalent: "")
        let resSubmenu = NSMenu()
        
        let grouped = RefreshRateService.shared.groupModesByResolution(
            DisplayModeService.shared.getAvailableModes(for: display.displayID)
        ).filter(\.isHiDPI)
        let customResolutions = CustomResolutionStore.load(for: display)
        
        // Limit to top 10 resolutions for brevity in menu bar
        for group in grouped.prefix(12) {
            let isCurrent = display.currentWidth == group.width && display.currentHeight == group.height && display.isHiDPI == group.isHiDPI
            
            let rateSuffix = group.refreshRates.contains(display.refreshRate) ? "" : " @ \(Int(group.refreshRates.first ?? 60.0))Hz"
            let isCustom = CustomResolutionStore.contains(
                width: group.width,
                height: group.height,
                rotation: display.rotation,
                in: customResolutions
            )
            let title = "\(group.width) x \(group.height) (HiDPI)\(isCustom ? " [Custom]" : "")\(rateSuffix)"
            
            let item = NSMenuItem(title: title, action: #selector(changeResolutionAction(_:)), keyEquivalent: "")
            item.target = self
            // Package information as a dictionary
            item.representedObject = [
                "displayID": display.displayID,
                "width": group.width,
                "height": group.height,
                "refreshRate": group.refreshRates.first ?? 60.0,
                "isHiDPI": group.isHiDPI
            ] as [String : Any]
            
            if isCurrent {
                item.state = .on
            }
            resSubmenu.addItem(item)
        }
        resItem.submenu = resSubmenu
        menu.addItem(resItem)
        
        // 3. Refresh Rate Selector
        let refreshItem = NSMenuItem(title: "Refresh Rates", action: nil, keyEquivalent: "")
        let refreshSubmenu = NSMenu()
        
        // Get rates for current resolution
        let modes = DisplayModeService.shared.getAvailableModes(for: display.displayID)
        let currentGroup = RefreshRateService.shared.groupModesByResolution(modes).first {
            $0.width == display.currentWidth && $0.height == display.currentHeight && $0.isHiDPI == display.isHiDPI
        }
        
        if let group = currentGroup {
            for rate in group.refreshRates {
                let item = NSMenuItem(title: "\(Int(rate)) Hz", action: #selector(changeRefreshRateAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = [
                    "displayID": display.displayID,
                    "width": display.currentWidth,
                    "height": display.currentHeight,
                    "refreshRate": rate,
                    "isHiDPI": display.isHiDPI
                ] as [String : Any]
                
                if abs(display.refreshRate - rate) < 0.1 {
                    item.state = .on
                }
                refreshSubmenu.addItem(item)
            }
        } else {
            refreshSubmenu.addItem(NSMenuItem(title: "N/A (Not adjustable independently)", action: nil, keyEquivalent: ""))
        }
        refreshItem.submenu = refreshSubmenu
        menu.addItem(refreshItem)
        
        // 4. Rotation Selector
        let rotationItem = NSMenuItem(title: "Rotation", action: nil, keyEquivalent: "")
        let rotationSubmenu = NSMenu()
        for angle in [0, 90, 180, 270] {
            let item = NSMenuItem(title: "\(angle)°", action: #selector(changeRotationAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["displayID": display.displayID, "angle": angle] as [String : Any]
            if display.rotation == angle {
                item.state = .on
            }
            rotationSubmenu.addItem(item)
        }
        rotationItem.submenu = rotationSubmenu
        menu.addItem(rotationItem)
    }
    
    // MARK: - Action Selectors
    
    @objc private func openSettingsWindow() {
        if settingsWindow == nil {
            let contentView = SettingsWindowView()
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Mac Monitor Settings"
            window.contentView = NSHostingView(rootView: contentView)
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.settingsWindow = window
        }
        
        // Elevate activation policy so it supports Cmd+Tab and Dock
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func changeResolutionAction(_ sender: NSMenuItem) {
        guard let dict = sender.representedObject as? [String: Any],
              let displayID = dict["displayID"] as? CGDirectDisplayID,
              let width = dict["width"] as? Int,
              let height = dict["height"] as? Int,
              let refreshRate = dict["refreshRate"] as? Double,
              let isHiDPI = dict["isHiDPI"] as? Bool else { return }
        
        DisplayManager.shared.changeMode(
            displayID: displayID,
            width: width,
            height: height,
            refreshRate: refreshRate,
            isHiDPI: isHiDPI
        )
        // Bring confirmation UI to front by showing settings window
        openSettingsWindow()
    }
    
    @objc private func changeRefreshRateAction(_ sender: NSMenuItem) {
        changeResolutionAction(sender)
    }
    
    @objc private func changeRotationAction(_ sender: NSMenuItem) {
        guard let dict = sender.representedObject as? [String: Any],
              let displayID = dict["displayID"] as? CGDirectDisplayID,
              let angle = dict["angle"] as? Int else { return }
        
        let success = RotationService.shared.rotate(displayID: displayID, to: angle)
        if success {
            DisplayManager.shared.refreshDisplays()
        }
    }
    
    @objc private func toggleDisplayPowerAction(_ sender: NSMenuItem) {
        guard let display = sender.representedObject as? DisplayInfo else { return }

        _ = DisplayPowerService.shared.toggleDisplay(display)
        DisplayManager.shared.refreshDisplays()
    }
    
    @objc private func exportDiagnosticsAction() {
        let report = DiagnosticsService.shared.generateReport(displays: DisplayManager.shared.displays)
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let fileURL = desktop.appendingPathComponent("MacMonitor_Diagnostics_Report.txt")
        
        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            let alert = NSAlert()
            alert.messageText = "Diagnostics Exported Successfully"
            alert.informativeText = "Saved diagnostics report file at:\n\(fileURL.path)"
            alert.runModal()
        } catch {
            print("[MenuBarController] Failed to export report: \(error.localizedDescription)")
        }
    }
    
    @objc private func resetDisplayConnectionsAction() {
        _ = DisplayPowerService.shared.resetDisplayConnections()
        DisplayManager.shared.refreshDisplays()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - NSWindowDelegate
    
    public func windowWillClose(_ notification: Notification) {
        // Revert activation policy back to accessory when settings window is closed
        NSApp.setActivationPolicy(.accessory)
    }
}
