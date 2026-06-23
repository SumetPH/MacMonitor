import SwiftUI
import CoreGraphics

struct CustomResolution: Codable, Hashable, Identifiable {
    var id: String { "\(width)x\(height)" }
    let width: Int
    let height: Int
}

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
    @ObservedObject private var presetStore = DisplayPresetStore.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginService.shared
    
    @State private var activeTab = "diagnostics"
    @State private var hasInitializedTab = false
    
    // Preset Creation State
    @State private var newPresetName = ""
    
    // Experimental Custom Override state
    @State private var hotReloadHiDPI = true
    
    // Per-display Custom Override State
    @State private var displayOverridesEnabled: [CGDirectDisplayID: Bool] = [:]
    @State private var displayCustomResolutions: [CGDirectDisplayID: [CustomResolution]] = [:]
    @State private var newResolutionWidth = 1920
    @State private var newResolutionHeight = 1080
    
    // Notification & Alert states
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var showingUninstallReport = false
    @State private var uninstallReportText = ""
    
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
    
    private func toggleDisplayPower(for display: DisplayInfo, isDisabled: Bool) {
        if isDisabled {
            DisplayPowerService.shared.enableDisplay(displayID: display.displayID)
            manager.refreshDisplays()
        } else {
            let alert = NSAlert()
            alert.messageText = "Disable Display Warning"
            alert.informativeText = "Are you sure you want to disable this display? Your screen layout may flash and windows may rearrange."
            alert.addButton(withTitle: "Disable")
            alert.addButton(withTitle: "Cancel")
            let res = alert.runModal()
            if res == .alertFirstButtonReturn {
                DisplayPowerService.shared.disableDisplay(displayID: display.displayID)
                manager.refreshDisplays()
            }
        }
    }
    
    private func savePreset(for display: DisplayInfo) {
        guard !newPresetName.isEmpty else { return }
        let currentBr = DDCService.shared.readBrightness(displayID: display.displayID)
        let preset = DisplayPreset(
            name: newPresetName,
            displayUUID: display.identifier.uuid,
            displayVendorID: display.identifier.vendorID,
            displayProductID: display.identifier.productID,
            displaySerialNumber: display.identifier.serialNumber,
            width: display.currentWidth,
            height: display.currentHeight,
            pixelWidth: display.currentPixelWidth,
            pixelHeight: display.currentPixelHeight,
            refreshRate: display.refreshRate,
            isHiDPI: display.isHiDPI,
            rotation: display.rotation,
            brightness: currentBr
        )
        presetStore.savePreset(preset)
        newPresetName = ""
    }
    
    private func saveResolutionsToUserDefaults(for display: DisplayInfo, resolutions: [CustomResolution]) {
        let key = "MacMonitor.CustomResolutions.\(display.identifier.id)"
        if let data = try? JSONEncoder().encode(resolutions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func loadResolutionsFromUserDefaults(for display: DisplayInfo) -> [CustomResolution] {
        let key = "MacMonitor.CustomResolutions.\(display.identifier.id)"
        if let data = UserDefaults.standard.data(forKey: key),
           let resolutions = try? JSONDecoder().decode([CustomResolution].self, from: data) {
            return resolutions
        }
        
        // Migrate from old single key if available
        let keyWidth = "MacMonitor.CustomWidth.\(display.identifier.id)"
        let keyHeight = "MacMonitor.CustomHeight.\(display.identifier.id)"
        let savedWidth = UserDefaults.standard.integer(forKey: keyWidth)
        let savedHeight = UserDefaults.standard.integer(forKey: keyHeight)
        
        if savedWidth > 0 && savedHeight > 0 {
            return [CustomResolution(width: savedWidth, height: savedHeight)]
        }
        
        // Default list
        return [CustomResolution(width: 1920, height: 1080)]
    }
    
    private func loadCustomResolutionsList(for display: DisplayInfo) {
        if displayCustomResolutions[display.displayID] == nil {
            displayCustomResolutions[display.displayID] = loadResolutionsFromUserDefaults(for: display)
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
            let keyToggle = "MacMonitor.CustomOverrideToggle.\(display.identifier.id)"
            if UserDefaults.standard.object(forKey: keyToggle) != nil {
                displayOverridesEnabled[display.displayID] = UserDefaults.standard.bool(forKey: keyToggle)
            } else {
                displayOverridesEnabled[display.displayID] = HiDPIService.shared.isHiDPIOverrideEnabled(for: display)
            }
            loadCustomResolutionsList(for: display)
        }
    }
    
    private func ensureOverrideStateLoaded(for display: DisplayInfo) {
        if displayOverridesEnabled[display.displayID] == nil {
            let keyToggle = "MacMonitor.CustomOverrideToggle.\(display.identifier.id)"
            if UserDefaults.standard.object(forKey: keyToggle) != nil {
                displayOverridesEnabled[display.displayID] = UserDefaults.standard.bool(forKey: keyToggle)
            } else {
                displayOverridesEnabled[display.displayID] = HiDPIService.shared.isHiDPIOverrideEnabled(for: display)
            }
        }
        loadCustomResolutionsList(for: display)
    }
    
    private func handleToggleOverride(for display: DisplayInfo, enabled: Bool) {
        displayOverridesEnabled[display.displayID] = enabled
        let keyToggle = "MacMonitor.CustomOverrideToggle.\(display.identifier.id)"
        UserDefaults.standard.set(enabled, forKey: keyToggle)
        
        if enabled {
            setHiDPIOverride(enabled: true, for: display)
        } else {
            setHiDPIOverride(enabled: false, for: display)
        }
    }
    
    private func setHiDPIOverride(enabled: Bool, for display: DisplayInfo) {
        let resolutions = displayCustomResolutions[display.displayID] ?? [CustomResolution(width: 1920, height: 1080)]
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
                displayOverridesEnabled[display.displayID] = enabled
            case .failure(let err):
                alertMessage = "Failed to modify HiDPI override: \(err.localizedDescription)"
                showingAlert = true
                displayOverridesEnabled[display.displayID] = !enabled
            }
        }
    }
    
    private func addResolution(width: Int, height: Int, for display: DisplayInfo) {
        guard width > 0, height > 0 else { return }
        var list = displayCustomResolutions[display.displayID] ?? []
        if !list.contains(where: { $0.width == width && $0.height == height }) {
            list.append(CustomResolution(width: width, height: height))
            displayCustomResolutions[display.displayID] = list
            saveResolutionsToUserDefaults(for: display, resolutions: list)
            
            if displayOverridesEnabled[display.displayID] == true {
                setHiDPIOverride(enabled: true, for: display)
            }
        }
    }
    
    private func removeResolution(at index: Int, for display: DisplayInfo) {
        var list = displayCustomResolutions[display.displayID] ?? []
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        displayCustomResolutions[display.displayID] = list
        saveResolutionsToUserDefaults(for: display, resolutions: list)
        
        if displayOverridesEnabled[display.displayID] == true {
            if list.isEmpty {
                handleToggleOverride(for: display, enabled: false)
            } else {
                setHiDPIOverride(enabled: true, for: display)
            }
        }
    }
    
    private func clearConfigAndRestore() {
        let alert = NSAlert()
        alert.messageText = "Confirm Resetting All Configurations?"
        alert.informativeText = "This action will restore original backup files and reset all user preferences. This cannot be undone."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        let res = alert.runModal()
        if res == .alertFirstButtonReturn {
            ClearConfigService.shared.performClearConfig(confirmBackupsRestore: true) { result in
                switch result {
                case .success:
                    alertMessage = "All Mac Monitor settings reset successfully."
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
        alert.messageText = "Confirm Complete Uninstallation?"
        alert.informativeText = "The application will clean all configurations and terminate. A summary report will be presented in the final step."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        let res = alert.runModal()
        if res == .alertFirstButtonReturn {
            UninstallService.shared.performUninstall { result in
                switch result {
                case .success(let report):
                    uninstallReportText = report
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
                Text("Uninstall Completed Successfully")
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
                
                Button("Close") {
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
                            toggleDisplayPower(for: display, isDisabled: isDisabled)
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
                        )
                        
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
                    
                    // 4. Presets
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Display Presets")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Save current display settings as preset:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TextField("e.g. Coding Mode, Sunset, Gaming...", text: $newPresetName)
                                    .textFieldStyle(.roundedBorder)
                                
                                Button("Save Preset") {
                                    savePreset(for: display)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newPresetName.isEmpty)
                            }
                        }
                        
                        let displayPresets = presetStore.presets.filter {
                            $0.displayUUID == display.identifier.uuid ||
                            ($0.displayVendorID == display.identifier.vendorID && $0.displayProductID == display.identifier.productID)
                        }
                        
                        if displayPresets.isEmpty {
                            Text("No presets saved for this display yet.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(displayPresets) { preset in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(preset.name)
                                                .fontWeight(.bold)
                                            Text("\(preset.width)x\(preset.height) @ \(Int(preset.refreshRate))Hz | Rotation: \(preset.rotation)° \(preset.isHiDPI ? "(HiDPI)" : "")")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        
                                        Toggle("Auto Apply", isOn: Binding(
                                            get: { preset.autoApply },
                                            set: { val in
                                                var updated = preset
                                                updated.autoApply = val
                                                presetStore.savePreset(updated)
                                            }
                                        ))
                                        .font(.caption)
                                        .toggleStyle(.checkbox)
                                        .padding(.trailing, 8)
                                        
                                        Button("Apply") {
                                            _ = presetStore.applyPreset(preset, availableDisplays: manager.displays)
                                            manager.refreshDisplays()
                                        }
                                        .buttonStyle(.bordered)
                                        
                                        Button(action: {
                                            presetStore.deletePreset(id: preset.id)
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.leading, 4)
                                    }
                                    .padding(8)
                                    .background(Color.black.opacity(0.1))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // 5. Custom Display Overrides (Per-display custom overrides)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Custom Display Overrides")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                Text("Add custom HiDPI scaling resolutions for this display.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            
                            let isOverrideEnabled = displayOverridesEnabled[display.displayID] ?? false
                            Toggle("Enable Custom Override", isOn: Binding(
                                get: { isOverrideEnabled },
                                set: { val in handleToggleOverride(for: display, enabled: val) }
                            ))
                            .toggleStyle(.switch)
                        }
                        
                        let isOverrideEnabled = displayOverridesEnabled[display.displayID] ?? false
                        if isOverrideEnabled {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Warning: Modifies macOS configuration plists. Backups are saved.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                
                                Text("HiDPI override state for this display: \(HiDPIService.shared.isHiDPIOverrideEnabled(for: display) ? "Enabled" : "Disabled")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                // List of added custom resolutions
                                let resolutions = displayCustomResolutions[display.displayID] ?? []
                                if !resolutions.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Configured Resolutions:")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        
                                        ForEach(Array(resolutions.enumerated()), id: \.offset) { index, res in
                                            HStack {
                                                Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                                                    .foregroundColor(.secondary)
                                                    .font(.system(size: 10))
                                                Text("\(res.width) x \(res.height)")
                                                    .font(.system(.body, design: .monospaced))
                                                Text("(HiDPI Scaling)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                Button(action: {
                                                    removeResolution(at: index, for: display)
                                                }) {
                                                    Image(systemName: "trash")
                                                        .foregroundColor(.red)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 8)
                                            .background(Color.black.opacity(0.1))
                                            .cornerRadius(4)
                                        }
                                    }
                                } else {
                                    Text("No custom resolutions configured. Add one below.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                                
                                Divider()
                                    .padding(.vertical, 4)
                                
                                // Form to add new resolution
                                HStack(alignment: .bottom) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Logical Width:")
                                            .font(.caption)
                                        TextField("e.g. 1920", value: $newResolutionWidth, formatter: NumberFormatter())
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Logical Height:")
                                            .font(.caption)
                                        TextField("e.g. 1080", value: $newResolutionHeight, formatter: NumberFormatter())
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                    
                                    Button(action: {
                                        addResolution(width: newResolutionWidth, height: newResolutionHeight, for: display)
                                    }) {
                                        HStack {
                                            Image(systemName: "plus")
                                            Text("Add")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Spacer()
                                }
                                
                                Toggle("Hot reload on changes (Skip system reboot)", isOn: $hotReloadHiDPI)
                                    .toggleStyle(.checkbox)
                                    .padding(.top, 4)
                                
                                HStack {
                                    Spacer()
                                    Button("Apply Changes & Reload") {
                                        setHiDPIOverride(enabled: true, for: display)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                .padding(.top, 4)
                            }
                            .padding(.top, 8)
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
                        
                        Button("Reconnect Displays") {
                            _ = DisplayPowerService.shared.resetDisplayConnections()
                            manager.refreshDisplays()
                        }
                        .buttonStyle(.borderedProminent)
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
                        Text("This will remove all saved presets, dynamic HiDPI override files created by Mac Monitor, and restore original system backups.")
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
                        Text("Complete Application Uninstallation:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Cleans configurations, restores default plists, and deletes all Application Support, logs, caches, and preferences files associated with Mac Monitor.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Uninstall Mac Monitor") {
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
