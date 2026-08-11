import SwiftUI
import CoreGraphics

// MARK: - Subcomponents to avoid compiler type-check timeout

struct RotationControlView: View {
    let displayID: CGDirectDisplayID
    let currentRotation: Int
    let canRotate: Bool
    let onRotationChange: (CGDirectDisplayID, Int) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach([0, 90, 180, 270], id: \.self) { angle in
                if currentRotation == angle {
                    Button("\(angle)°") {
                        onRotationChange(displayID, angle)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRotate)
                } else {
                    Button("\(angle)°") {
                        onRotationChange(displayID, angle)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canRotate)
                }
            }
        }
    }
}

public struct SettingsWindowView: View {
    @ObservedObject private var manager = DisplayManager.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginService.shared
    @ObservedObject private var shortcutService = DisplayShortcutService.shared
    
    @State private var activeTab = "diagnostics"
    @State private var hasInitializedTab = false
    
    // Experimental Custom Override state
    @State private var hotReloadHiDPI = false
    
    // Per-display Custom Override State
    @State private var displayOverridesEnabled: [String: Bool] = [:]
    @State private var displayCustomResolutions: [String: [CustomResolution]] = [:]
    @State private var newResolutionWidth = 1920
    @State private var newResolutionHeight = 1080
    
    // Notification & Alert states
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var showingUninstallReport = false
    @State private var uninstallReportText = ""
    @State private var uninstallCompletedWithWarnings = false
    
    public init() {}
    
    // MARK: - Helper Methods (Decouple closures to avoid type-check timeouts)
    
    private func rotationFailureMessage(for displayID: CGDirectDisplayID) -> String {
        let log = DiagnosticsService.shared.getLogs().reversed().first {
            $0.displayID == displayID && $0.operationType == "rotate"
        }
        
        var message = "Cannot rotate this display. The connected screen might not support hardware rotation, or macOS denied private rotation API access."
        if let log {
            message += "\n\nDetails: \(log.details)"
            if let errorDescription = log.errorDescription, !errorDescription.isEmpty {
                message += "\n\(errorDescription)"
            }
        }
        message += "\n\nTry comparing with rotation in macOS System Settings directly to identify if this is a hardware limitation or an API failure."
        return message
    }
    
    private func handleRotationChange(for displayID: CGDirectDisplayID, to angle: Int) {
        let success = RotationService.shared.rotate(displayID: displayID, to: angle)
        if success {
            manager.refreshDisplays()
        } else {
            alertMessage = rotationFailureMessage(for: displayID)
            showingAlert = true
        }
    }
    
    private func toggleDisplayPower(for display: DisplayInfo) {
        DisplayPowerService.shared.toggleDisplay(display)
        manager.refreshDisplays()
    }

    private func setActionShortcut(
        _ shortcut: DisplayKeyboardShortcut?,
        for action: DisplayShortcutAction
    ) -> Bool {
        let didSetShortcut = shortcutService.setShortcut(shortcut, for: action)
        if !didSetShortcut {
            alertMessage = "This shortcut is already assigned to another action or reserved by macOS."
            showingAlert = true
        }
        return didSetShortcut
    }
    
    private func overrideStorageID(for display: DisplayInfo) -> String {
        CustomResolutionStore.storageID(for: display)
    }

    private func saveResolutionsToUserDefaults(for display: DisplayInfo, resolutions: [CustomResolution]) {
        CustomResolutionStore.save(resolutions, for: display)
    }
    
    private func loadResolutionsFromUserDefaults(for display: DisplayInfo) -> [CustomResolution] {
        CustomResolutionStore.load(for: display)
    }
    
    private func loadCustomResolutionsList(for display: DisplayInfo) {
        let storageID = overrideStorageID(for: display)
        if displayCustomResolutions[storageID] == nil {
            displayCustomResolutions[storageID] = loadResolutionsFromUserDefaults(for: display)
        }
    }
    
    private func initializeActiveTabIfNeeded() {
        guard !hasInitializedTab else { return }
        if let first = manager.displays.first {
            activeTab = "display-\(first.displayID)"
            hasInitializedTab = true
        }
    }
    
    private func loadAllOverridesStates() {
        for display in manager.displays {
            let storageID = overrideStorageID(for: display)
            displayOverridesEnabled[storageID] = HiDPIService.shared.isHiDPIOverrideEnabled(for: display)
            UserDefaults.standard.removeObject(forKey: "MacMonitor.CustomOverrideToggle.\(display.identifier.id)")
            loadCustomResolutionsList(for: display)
        }
    }
    
    private func ensureOverrideStateLoaded(for display: DisplayInfo) {
        let storageID = overrideStorageID(for: display)
        if displayOverridesEnabled[storageID] == nil {
            displayOverridesEnabled[storageID] = HiDPIService.shared.isHiDPIOverrideEnabled(for: display)
        }
        loadCustomResolutionsList(for: display)
    }
    
    private func setHiDPIOverride(enabled: Bool, for display: DisplayInfo) {
        let storageID = overrideStorageID(for: display)
        let resolutions = displayCustomResolutions[storageID] ?? []
        let customTupleArray = resolutions.map { (width: $0.width, height: $0.height) }
        
        HiDPIService.shared.setHiDPIOverrideEnabled(
            enabled,
            for: display,
            customResolutions: customTupleArray,
            hotReload: hotReloadHiDPI
        ) { result in
            switch result {
            case .success(let message):
                alertMessage = "\(message)\n\(hotReloadHiDPI ? "Reloaded config. Reconnect display if mode does not appear." : "Stored config. Reconnect or restart to apply.")"
                showingAlert = true
                manager.refreshDisplays()
                loadAllOverridesStates()
            case .failure(let err):
                alertMessage = "Failed to modify HiDPI override: \(err.localizedDescription)"
                showingAlert = true
                loadAllOverridesStates()
            }
        }
    }

    private func confirmOverrideChange(enabled: Bool, for display: DisplayInfo) {
        let storageID = overrideStorageID(for: display)
        let resolutions = displayCustomResolutions[storageID] ?? []

        if enabled && resolutions.isEmpty {
            alertMessage = "Add at least one valid resolution before enabling the override."
            showingAlert = true
            return
        }

        let alert = NSAlert()
        alert.messageText = enabled ? "Apply Custom Display Override?" : "Disable Custom Display Override?"
        let resolutionText = resolutions.map { "\($0.width) × \($0.height)" }.joined(separator: ", ")
        var details = enabled
            ? "This writes a macOS display override for every display with the same vendor and product IDs.\n\nResolutions: \(resolutionText)"
            : "This restores the original override backup, or removes the file created by Mac Monitor. Displays with the same vendor and product IDs are affected together."
        if hotReloadHiDPI {
            details += "\n\nImmediate reload may temporarily disconnect the display."
        } else {
            details += "\n\nReconnect the display or restart macOS for the change to appear."
        }
        alert.informativeText = details
        alert.addButton(withTitle: enabled ? "Apply Override" : "Disable Override")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            setHiDPIOverride(enabled: enabled, for: display)
        }
    }
    
    private func addResolution(width: Int, height: Int, for display: DisplayInfo) {
        guard (320...8192).contains(width), (200...8192).contains(height) else { return }
        let storageID = overrideStorageID(for: display)
        var list = displayCustomResolutions[storageID] ?? []
        if !list.contains(where: { $0.width == width && $0.height == height }) {
            list.append(CustomResolution(width: width, height: height))
            displayCustomResolutions[storageID] = list
            saveResolutionsToUserDefaults(for: display, resolutions: list)
        }
    }
    
    private func removeResolution(at index: Int, for display: DisplayInfo) {
        let storageID = overrideStorageID(for: display)
        var list = displayCustomResolutions[storageID] ?? []
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        displayCustomResolutions[storageID] = list
        saveResolutionsToUserDefaults(for: display, resolutions: list)
    }

    private func resolutionInputError(for display: DisplayInfo) -> String? {
        guard (320...8192).contains(newResolutionWidth),
              (200...8192).contains(newResolutionHeight) else {
            return "Width must be 320–8192 and height must be 200–8192."
        }

        let storageID = overrideStorageID(for: display)
        let resolutions = displayCustomResolutions[storageID] ?? []
        if resolutions.contains(where: { $0.width == newResolutionWidth && $0.height == newResolutionHeight }) {
            return "This resolution is already in the list."
        }
        return nil
    }
    
    private func clearConfigAndRestore() {
        let alert = NSAlert()
        alert.messageText = "Confirm Resetting All Configurations?"
        let preview = ClearConfigService.shared.cleanupPreview()
        alert.informativeText = (["The following actions will be performed:", ""] + preview.map { "• \($0)" } + ["", "If any system file cannot be restored safely, recovery data will be kept and the reset will stop."]).joined(separator: "\n")
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        let res = alert.runModal()
        if res == .alertFirstButtonReturn {
            ClearConfigService.shared.performClearConfig(confirmBackupsRestore: true) { result in
                switch result {
                case .success(let items):
                    displayOverridesEnabled.removeAll()
                    displayCustomResolutions.removeAll()
                    loadAllOverridesStates()
                    alertMessage = (["Mac Monitor settings were reset successfully:"] + items.map { "• \($0)" }).joined(separator: "\n")
                    showingAlert = true
                    manager.refreshDisplays()
                case .failure(let err):
                    alertMessage = "Reset failed: \(err.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
    
    private func uninstallApp() {
        let alert = NSAlert()
        alert.messageText = "Clean Mac Monitor Data and Quit?"
        let preview = ClearConfigService.shared.cleanupPreview()
        alert.informativeText = (["Mac Monitor will:", ""] + preview.map { "• \($0)" } + [
            "• Remove its Application Support, cache, and log folders",
            "• Save a cleanup report to the Desktop",
            "• Quit after you review the report",
            "",
            "The Mac Monitor.app file is not deleted. Move it to Trash afterward to finish uninstalling."
        ]).joined(separator: "\n")
        alert.addButton(withTitle: "Clean Data")
        alert.addButton(withTitle: "Cancel")
        let res = alert.runModal()
        if res == .alertFirstButtonReturn {
            UninstallService.shared.performUninstall { result in
                switch result {
                case .success(let report):
                    uninstallReportText = report.text
                    uninstallCompletedWithWarnings = report.hasWarnings
                    showingUninstallReport = true
                case .failure(let err):
                    alertMessage = "Uninstall failed: \(err.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
    
    // MARK: - View Body
    
    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation
            VStack(alignment: .leading, spacing: 6) {
                Text("DISPLAYS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                
                ForEach(manager.displays) { display in
                    Button(action: { activeTab = "display-\(display.displayID)" }) {
                        HStack(spacing: 8) {
                            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "desktopcomputer")
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(display.name)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(display.isAppDisconnected ? "Disabled" : "\(display.currentWidth)x\(display.currentHeight)")
                                    .font(.system(size: 10))
                                    .foregroundColor(activeTab == "display-\(display.displayID)" ? .white.opacity(0.8) : .secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundColor(activeTab == "display-\(display.displayID)" ? .white : .primary)
                        .background(activeTab == "display-\(display.displayID)" ? Color.accentColor : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.horizontal, 8)
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                Text("SYSTEM")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                
                Button(action: { activeTab = "diagnostics" }) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 20)
                        Text("Settings")
                            .font(.body)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundColor(activeTab == "diagnostics" ? .white : .primary)
                    .background(activeTab == "diagnostics" ? Color.accentColor : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .padding(.horizontal, 8)
                
                Spacer()
            }
            .frame(width: 190)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.15))
            
            Divider()
            
            // Tab Contents
            Group {
                if activeTab == "diagnostics" {
                    diagnosticsAndSystemTab()
                } else if activeTab.hasPrefix("display-"),
                          let displayIDStr = activeTab.split(separator: "-").last,
                          let displayID = CGDirectDisplayID(displayIDStr),
                          let display = manager.displays.first(where: { $0.displayID == displayID }) {
                    displayDetailTab(display: display)
                } else if let firstDisplay = manager.displays.first {
                    // Fallback automatically to first display
                    displayDetailTab(display: firstDisplay)
                } else {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "display.trianglebadge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Connected Displays Detected")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Button("Refresh Displays") {
                            manager.refreshDisplays()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 520)
        .onAppear {
            manager.refreshDisplays()
            initializeActiveTabIfNeeded()
            if !hasInitializedTab {
                activeTab = "diagnostics"
            }
            loadAllOverridesStates()
            launchAtLogin.refreshStatus()
        }
        .onChange(of: manager.displays) { _, _ in
            initializeActiveTabIfNeeded()
            loadAllOverridesStates()
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Mac Monitor"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showingUninstallReport) {
            VStack(spacing: 16) {
                Text(uninstallCompletedWithWarnings ? "Data Cleanup Completed with Warnings" : "Data Cleanup Completed")
                    .font(.headline)
                ScrollView {
                    Text(uninstallReportText)
                        .font(.system(.footnote, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(6)
                }
                .frame(width: 500, height: 300)
                
                Button("Quit Mac Monitor") {
                    showingUninstallReport = false
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .overlay {
            if manager.showConfirmationDialog, manager.activeConfirmationDisplayID != nil {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Text("Confirm Resolution Change?")
                        .font(.headline)
                    Text("The screen settings will revert automatically in 15 seconds if you do not confirm, in order to prevent black screens.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        Button("Revert") {
                            manager.revertMode()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Confirm") {
                            manager.confirmMode()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(width: 380)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
                .shadow(radius: 8)
            }
        }
    }
    
    // MARK: - Display Detail View
    private func displayDetailTab(display: DisplayInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("ID: \(display.displayID) | \(display.isBuiltIn ? "Built-in Screen" : "External Screen")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    Button(action: { manager.refreshDisplays() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh display list")
                }
                .padding(.top, 16)
                
                // 1. Connection / Power Control
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Display Connection Status")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        Spacer()
                        
                        let isDisabled = display.isAppDisconnected || DisplayPowerService.shared.isDisplayDisabled(display.displayID)
                        
                        Button(action: {
                            toggleDisplayPower(for: display)
                        }) {
                            Text(isDisabled ? "Enable" : "Disable")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isDisabled && display.isMain)
                    }
                    
                    if display.isAppDisconnected {
                        Text("This display has been soft-disconnected from the macOS layout. Click Enable to restore.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Power Toggle Shortcut")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(display.isMain
                                 ? "The shortcut cannot disable this display while it is the main display."
                                 : "Works globally. Press Delete while recording to clear it.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        DisplayShortcutRecorder(
                            shortcut: shortcutService.shortcut(for: display.identifier),
                            onChange: { shortcut in
                                let didSetShortcut = shortcutService.setShortcut(shortcut, for: display.identifier)
                                if !didSetShortcut {
                                    alertMessage = "This shortcut is already assigned to another display or reserved by macOS."
                                    showingAlert = true
                                }
                                return didSetShortcut
                            }
                        )
                        .frame(width: 140)

                        if shortcutService.shortcut(for: display.identifier) != nil {
                            Button {
                                shortcutService.setShortcut(nil, for: display.identifier)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .help("Clear keyboard shortcut")
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                
                if !display.isAppDisconnected {
                    // 2. Hardware Control (Rotation & Brightness)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Hardware Controls")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        // Rotation selector using the custom subview to bypass compiler timeouts
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Screen Rotation:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            let canRotate = RotationService.shared.canRotate(displayID: display.displayID)
                            
                            RotationControlView(
                                displayID: display.displayID,
                                currentRotation: display.rotation,
                                canRotate: canRotate,
                                onRotationChange: handleRotationChange
                            )
                            
                            if !canRotate {
                                Text("This display does not support API-based rotation. Please change rotation in macOS System Settings.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Brightness slider (DDC/CI or Native)
                        if DDCService.shared.supportsDDC(displayID: display.displayID) {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Brightness (DDC/CI & Native API):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Image(systemName: "sun.max.fill")
                                    
                                    let currentBr = DDCService.shared.readBrightness(displayID: display.displayID) ?? 0.8
                                    
                                    Slider(value: Binding(
                                        get: { currentBr },
                                        set: { DDCService.shared.writeBrightness(displayID: display.displayID, value: $0) }
                                    ), in: 0.0...1.0)
                                    
                                    Text("\(Int(currentBr * 100))%")
                                        .frame(width: 45, alignment: .trailing)
                                }
                              }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // 3. Resolutions & Modes
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Resolutions & Display Modes")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        let grouped = RefreshRateService.shared.groupModesByResolution(
                            DisplayModeService.shared.getAvailableModes(for: display.displayID)
                        ).filter(\.isHiDPI)
                        let storageID = overrideStorageID(for: display)
                        let customResolutions = displayCustomResolutions[storageID] ?? []
                        
                        VStack(spacing: 8) {
                            ForEach(grouped) { group in
                                HStack {
                                    Text("\(group.width) x \(group.height)")
                                        .fontWeight(.semibold)
                                    if group.isHiDPI {
                                        Text("HiDPI")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.2))
                                            .foregroundColor(.blue)
                                            .cornerRadius(4)
                                    }
                                    if CustomResolutionStore.contains(
                                        width: group.width,
                                        height: group.height,
                                        rotation: display.rotation,
                                        in: customResolutions
                                    ) {
                                        Text("Custom")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.2))
                                            .foregroundColor(.orange)
                                            .cornerRadius(4)
                                    }
                                    Spacer()
                                    
                                    Menu {
                                        ForEach(group.refreshRates, id: \.self) { rate in
                                            Button("\(Int(rate)) Hz") {
                                                manager.changeMode(
                                                    displayID: display.displayID,
                                                    width: group.width,
                                                    height: group.height,
                                                    refreshRate: rate,
                                                    isHiDPI: group.isHiDPI
                                                )
                                            }
                                        }
                                    } label: {
                                        let currentMatch = display.currentWidth == group.width &&
                                                           display.currentHeight == group.height &&
                                                           display.isHiDPI == group.isHiDPI
                                        
                                        Text(currentMatch ? "\(Int(display.refreshRate)) Hz (Active)" : "Select Frame Rate")
                                            .foregroundColor(currentMatch ? .accentColor : .primary)
                                    }
                                    .frame(width: 155)
                                }
                                .padding(.vertical, 4)
                                
                                if group.id != grouped.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // 4. Custom Display Overrides (Per-display custom overrides)
                    VStack(alignment: .leading, spacing: 12) {
                        let storageID = overrideStorageID(for: display)
                        let isOverrideEnabled = displayOverridesEnabled[storageID] ?? false
                        let resolutions = displayCustomResolutions[storageID] ?? []
                        let inputError = resolutionInputError(for: display)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Custom Display Overrides")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                Text("Configure HiDPI resolutions for this display model.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()

                            Label(
                                isOverrideEnabled ? "Active" : "Inactive",
                                systemImage: isOverrideEnabled ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.caption)
                            .foregroundColor(isOverrideEnabled ? .green : .secondary)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Experimental: this writes a macOS system override. Displays with the same vendor and product IDs are affected together. The original file is backed up before the first write.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Configured Resolutions")
                                .font(.caption)
                                .fontWeight(.semibold)

                            if resolutions.isEmpty {
                                Text("No custom resolutions configured. Add at least one before enabling the override.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(Array(resolutions.enumerated()), id: \.offset) { index, resolution in
                                    HStack {
                                        Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 10))
                                        Text("\(resolution.width) × \(resolution.height)")
                                            .font(.system(.body, design: .monospaced))
                                        Text("HiDPI")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Button {
                                            removeResolution(at: index, for: display)
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove \(resolution.width) × \(resolution.height)")
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.black.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                        }

                        Divider()
                            .padding(.vertical, 4)

                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Logical Width")
                                    .font(.caption)
                                TextField("e.g. 1920", value: $newResolutionWidth, formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Logical Height")
                                    .font(.caption)
                                TextField("e.g. 1080", value: $newResolutionHeight, formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                            }

                            Button {
                                addResolution(width: newResolutionWidth, height: newResolutionHeight, for: display)
                            } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(inputError != nil)

                            Spacer()
                        }

                        if let inputError {
                            Text(inputError)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("Editing this list does not change macOS until you confirm Apply Override.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Reload the display immediately after applying (experimental)", isOn: $hotReloadHiDPI)
                            .toggleStyle(.checkbox)

                        HStack {
                            if isOverrideEnabled {
                                Button("Disable Override…") {
                                    confirmOverrideChange(enabled: false, for: display)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }

                            Spacer()

                            Button(isOverrideEnabled ? "Apply Changes…" : "Enable Override…") {
                                confirmOverrideChange(enabled: true, for: display)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(resolutions.isEmpty)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    .onAppear {
                        ensureOverrideStateLoaded(for: display)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Diagnostics & System Tab
    private func diagnosticsAndSystemTab() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // General Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("General Settings")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Launch at Login", isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        ))
                        .toggleStyle(.checkbox)
                        
                        Text("Automatically launch Mac Monitor when you log in to your Mac.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                
                Divider()
                    .padding(.vertical, 8)

                // Multi-display power shortcut
                VStack(alignment: .leading, spacing: 12) {
                    Text("Multi-Display Power Shortcut")
                        .font(.headline)

                    Text("Choose multiple displays to switch together. If every selected display is disabled, the shortcut enables them all; otherwise it disables the selected displays that are still active.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(manager.displays) { display in
                            let isSelected = shortcutService.isIncludedInMultiDisplayShortcut(display.identifier)

                            Toggle(isOn: Binding(
                                get: { isSelected },
                                set: { included in
                                    shortcutService.setIncludedInMultiDisplayShortcut(
                                        included,
                                        displayIdentifier: display.identifier
                                    )
                                }
                            )) {
                                HStack {
                                    Image(systemName: display.isBuiltIn ? "laptopcomputer" : "desktopcomputer")
                                        .frame(width: 20)
                                    Text(display.name)
                                    if display.isMain {
                                        Text("Main display — stays on")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .disabled(display.isMain && !isSelected)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Shortcut:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()

                        DisplayShortcutRecorder(
                            shortcut: shortcutService.shortcut(for: .multiDisplayPower),
                            shortcutName: "Multi-display power",
                            onChange: { shortcut in
                                setActionShortcut(shortcut, for: .multiDisplayPower)
                            }
                        )
                        .frame(width: 140)

                        if shortcutService.shortcut(for: .multiDisplayPower) != nil {
                            Button {
                                shortcutService.setShortcut(nil, for: .multiDisplayPower)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .help("Clear multi-display shortcut")
                        }
                    }

                    if shortcutService.multiDisplayIdentifiers.isEmpty {
                        Text("Select at least one non-main display before using this shortcut.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)

                Divider()
                    .padding(.vertical, 8)
                
                // Display Recovery Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Display Recovery Settings")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reconnect All Displays:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Forces macOS to re-detect and reconnect all disconnected or sleeping displays. Use this if a display is missing or unresponsive.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Button("Reconnect Displays") {
                                _ = DisplayPowerService.shared.resetDisplayConnections()
                                manager.refreshDisplays()
                            }
                            .buttonStyle(.borderedProminent)

                            Spacer()

                            Text("Shortcut:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            DisplayShortcutRecorder(
                                shortcut: shortcutService.shortcut(for: .reconnectAll),
                                shortcutName: "Reconnect all displays",
                                onChange: { shortcut in
                                    setActionShortcut(shortcut, for: .reconnectAll)
                                }
                            )
                            .frame(width: 140)

                            if shortcutService.shortcut(for: .reconnectAll) != nil {
                                Button {
                                    shortcutService.setShortcut(nil, for: .reconnectAll)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                                .help("Clear reconnect shortcut")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                
                Divider()
                    .padding(.vertical, 8)
                
                DiagnosticsView()
                    .frame(minHeight: 400)
                
                Divider()
                    .padding(.vertical, 8)
                
                // Clear Config & Uninstall Options
                VStack(alignment: .leading, spacing: 12) {
                    Text("System Maintenance & Security")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reset & Clear Configuration:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("This will remove dynamic HiDPI override files created by Mac Monitor, reset app preferences, and restore original system backups.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Clear Config & Restore Backups") {
                            clearConfigAndRestore()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Remove Mac Monitor Data:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Restores system files, removes Mac Monitor data, saves a report, and quits. The app file remains and must be moved to Trash manually.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Clean Data & Quit…") {
                            uninstallApp()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.05))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }
}
