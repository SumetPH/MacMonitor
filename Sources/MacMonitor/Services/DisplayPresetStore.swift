import Foundation
import CoreGraphics

@MainActor
public final class DisplayPresetStore: ObservableObject {
    public static let shared = DisplayPresetStore()
    
    @Published public private(set) var presets: [DisplayPreset] = []
    
    private let defaultsKey = "com.macmonitor.DisplayPresets"
    private let defaults = UserDefaults.standard
    
    private init() {
        loadPresets()
    }
    
    public func savePreset(_ preset: DisplayPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        saveToDefaults()
        
        DiagnosticsService.shared.log(
            displayID: 0,
            operation: "savePreset",
            success: true,
            details: "Saved preset: '\(preset.name)'"
        )
    }
    
    public func deletePreset(id: UUID) {
        if let index = presets.firstIndex(where: { $0.id == id }) {
            let name = presets[index].name
            presets.remove(at: index)
            saveToDefaults()
            DiagnosticsService.shared.log(
                displayID: 0,
                operation: "deletePreset",
                success: true,
                details: "Deleted preset: '\(name)'"
            )
        }
    }
    
    public func applyPreset(_ preset: DisplayPreset, availableDisplays: [DisplayInfo]) -> Bool {
        // Find matching display
        guard let matchingDisplay = availableDisplays.first(where: { preset.matches(display: $0) }) else {
            DiagnosticsService.shared.log(
                displayID: 0,
                operation: "applyPreset",
                success: false,
                details: "No matching connected display found for preset '\(preset.name)'"
            )
            return false
        }
        
        let displayID = matchingDisplay.displayID
        var success = true
        
        // 1. Apply Rotation
        if RotationService.shared.getCurrentRotation(for: displayID) != preset.rotation {
            let rotationSuccess = RotationService.shared.rotate(displayID: displayID, to: preset.rotation)
            success = success && rotationSuccess
        }
        
        // 2. Apply Resolution / Mode
        let modes = DisplayModeService.shared.getAvailableModes(for: displayID)
        if let targetMode = RefreshRateService.shared.findMode(
            in: modes,
            width: preset.width,
            height: preset.height,
            refreshRate: preset.refreshRate,
            isHiDPI: preset.isHiDPI
        ) {
            let current = DisplayModeService.shared.getCurrentMode(for: displayID)
            if current?.width != targetMode.width ||
                current?.height != targetMode.height ||
                current?.refreshRate != targetMode.refreshRate {
                let modeSuccess = DisplayModeService.shared.switchMode(
                    displayID: displayID,
                    targetMode: targetMode,
                    autoRollback: false // Preset applying doesn't require verification rollback
                )
                success = success && modeSuccess
            }
        }
        
        // 3. Apply Brightness if available
        if let brightness = preset.brightness {
            let brightnessSuccess = DDCService.shared.writeBrightness(displayID: displayID, value: brightness)
            success = success && brightnessSuccess
        }
        
        DiagnosticsService.shared.log(
            displayID: displayID,
            operation: "applyPreset",
            success: success,
            details: "Applied preset '\(preset.name)'"
        )
        
        return success
    }
    
    public func checkAndAutoApply(displays: [DisplayInfo]) {
        for display in displays {
            // Find presets matching this display that have autoApply enabled
            let autoPresets = presets.filter { $0.autoApply && $0.matches(display: display) }
            for preset in autoPresets {
                // If it doesn't match current settings, apply it
                let currentRotation = RotationService.shared.getCurrentRotation(for: display.displayID)
                let isResolutionMatch = display.currentWidth == preset.width &&
                                        display.currentHeight == preset.height &&
                                        abs(display.refreshRate - preset.refreshRate) < 0.1 &&
                                        display.isHiDPI == preset.isHiDPI
                
                if currentRotation != preset.rotation || !isResolutionMatch {
                    print("[DisplayPresetStore] Auto-applying preset '\(preset.name)' for display \(display.name)")
                    _ = applyPreset(preset, availableDisplays: [display])
                }
            }
        }
    }
    
    public func clearPresets() {
        presets.removeAll()
        saveToDefaults()
    }
    
    private func loadPresets() {
        guard let data = defaults.data(forKey: defaultsKey) else { return }
        do {
            let decoder = JSONDecoder()
            self.presets = try decoder.decode([DisplayPreset].self, from: data)
        } catch {
            print("[DisplayPresetStore] Failed to decode presets: \(error.localizedDescription)")
        }
    }
    
    private func saveToDefaults() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(presets)
            defaults.set(data, forKey: defaultsKey)
            objectWillChange.send()
        } catch {
            print("[DisplayPresetStore] Failed to encode presets: \(error.localizedDescription)")
        }
    }
}
