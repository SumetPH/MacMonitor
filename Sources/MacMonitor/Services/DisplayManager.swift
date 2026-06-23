import Foundation
import CoreGraphics
import AppKit
import IOKit

@MainActor
public final class DisplayManager: ObservableObject {
    public static let shared = DisplayManager()
    
    @Published var displays: [DisplayInfo] = []
    @Published var activeConfirmationDisplayID: CGDirectDisplayID? = nil
    @Published var showConfirmationDialog: Bool = false
    
    private init() {
        // Start observer
        DisplayReconfigurationObserver.shared.startListening()
        
        // Listen to notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleReconfiguration),
            name: .displayReconfiguration,
            object: nil
        )
        
        refreshDisplays()
    }
    
    @objc private func handleReconfiguration() {
        print("[DisplayManager] Received display reconfiguration notification. Refreshing...")
        refreshDisplays()
    }
    
    private static func getDisplayNameViaIOKit(displayID: CGDirectDisplayID) -> String? {
        typealias CGDisplayIOServicePortType = @convention(c) (CGDirectDisplayID) -> io_service_t
        let handle = dlopen(nil, RTLD_LAZY)
        guard let sym = dlsym(handle, "CGDisplayIOServicePort") else { return nil }
        let CGDisplayIOServicePort = unsafeBitCast(sym, to: CGDisplayIOServicePortType.self)
        let service = CGDisplayIOServicePort(displayID)
        
        guard service != io_service_t(MACH_PORT_NULL) else { return nil }
        
        guard let info = IODisplayCreateInfoDictionary(service, IOOptionBits(1))?.takeRetainedValue() as? [String: AnyObject] else {
            return nil
        }
        
        guard let productNames = info["DisplayProductName"] as? [String: String] else {
            return nil
        }
        
        return productNames.values.first
    }
    
    public func refreshDisplays() {
        var onlineCount: UInt32 = 0
        var status = CGGetOnlineDisplayList(0, nil, &onlineCount)
        guard status == .success, onlineCount > 0 else {
            DispatchQueue.main.async {
                self.displays = []
            }
            return
        }
        
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(onlineCount))
        status = CGGetOnlineDisplayList(onlineCount, &displayIDs, &onlineCount)
        guard status == .success else { return }
        
        var tempDisplays: [DisplayInfo] = []
        
        for id in displayIDs {
            let identifier = DisplayIdentifier(displayID: id)
            
            // Determine name
            var name = "Unknown Display"
            if CGDisplayIsBuiltin(id) != 0 {
                name = "Built-in Retina Display"
            } else {
                if let iokitName = DisplayManager.getDisplayNameViaIOKit(displayID: id) {
                    name = iokitName
                } else {
                    // Try matching via NSScreen as fallback
                    for screen in NSScreen.screens {
                        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID, screenNumber == id {
                            name = screen.localizedName
                            break
                        }
                    }
                }
            }
            
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let isActive = CGDisplayIsActive(id) != 0
            let isOnline = CGDisplayIsOnline(id) != 0
            let isAsleep = CGDisplayIsAsleep(id) != 0
            let isMain = CGMainDisplayID() == id
            let isMirrored = CGDisplayIsInMirrorSet(id) != 0
            
            // Mode info
            guard let currentMode = CGDisplayCopyDisplayMode(id) else { continue }
            
            // Rotation
            let rotation = RotationService.shared.getCurrentRotation(for: id)
            
            // Backing scale factor
            var scaleFactor: Double = 1.0
            for screen in NSScreen.screens {
                if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID, screenNumber == id {
                    scaleFactor = Double(screen.backingScaleFactor)
                    break
                }
            }
            
            // Available modes
            let modes = DisplayModeService.shared.getAvailableModes(for: id).map { DisplayModeInfo(cgMode: $0) }
            
            let displayInfo = DisplayInfo(
                displayID: id,
                identifier: identifier,
                name: name,
                isBuiltIn: isBuiltIn,
                isActive: isActive,
                isOnline: isOnline,
                isAsleep: isAsleep,
                isMain: isMain,
                isMirrored: isMirrored,
                currentWidth: currentMode.width,
                currentHeight: currentMode.height,
                currentPixelWidth: currentMode.pixelWidth,
                currentPixelHeight: currentMode.pixelHeight,
                refreshRate: currentMode.refreshRate == 0 ? 60.0 : currentMode.refreshRate,
                scaleFactor: scaleFactor,
                isHiDPI: currentMode.pixelWidth > currentMode.width || currentMode.pixelHeight > currentMode.height,
                rotation: rotation,
                modes: modes
            )
            
            tempDisplays.append(displayInfo)
        }
        
        tempDisplays.append(contentsOf: DisplayPowerService.shared.disabledDisplaySnapshots(excluding: tempDisplays))
        
        DispatchQueue.main.async {
            self.displays = tempDisplays
            // Preset Store auto-apply on connection
            DisplayPresetStore.shared.objectWillChange.send()
            DisplayPresetStore.shared.checkAndAutoApply(displays: tempDisplays)
        }
    }
    
    public func changeMode(displayID: CGDirectDisplayID, width: Int, height: Int, refreshRate: Double, isHiDPI: Bool) {
        let modes = DisplayModeService.shared.getAvailableModes(for: displayID)
        guard let mode = RefreshRateService.shared.findMode(
            in: modes,
            width: width,
            height: height,
            refreshRate: refreshRate,
            isHiDPI: isHiDPI
        ) else {
            print("[DisplayManager] Failed to find matching mode.")
            return
        }
        
        let success = DisplayModeService.shared.switchMode(
            displayID: displayID,
            targetMode: mode,
            autoRollback: true,
            onRollback: { [weak self] in
                DispatchQueue.main.async {
                    self?.refreshDisplays()
                    self?.showConfirmationDialog = false
                    self?.activeConfirmationDisplayID = nil
                }
            }
        )
        
        if success {
            refreshDisplays()
            DispatchQueue.main.async {
                self.activeConfirmationDisplayID = displayID
                self.showConfirmationDialog = true
            }
        }
    }
    
    public func confirmMode() {
        DisplayModeService.shared.confirmModeChange()
        DispatchQueue.main.async {
            self.showConfirmationDialog = false
            self.activeConfirmationDisplayID = nil
        }
    }
    
    public func revertMode() {
        DisplayModeService.shared.revertModeChange()
        refreshDisplays()
        DispatchQueue.main.async {
            self.showConfirmationDialog = false
            self.activeConfirmationDisplayID = nil
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
