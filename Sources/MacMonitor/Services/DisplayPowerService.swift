import Foundation
import CoreGraphics

@MainActor
public final class DisplayPowerService {
    public static let shared = DisplayPowerService()
    
    private let disabledDisplaySnapshotsKey = "MacMonitor.disabledDisplaySnapshots"
    
    // Track displays by stable identifier because macOS can re-enumerate
    // display IDs after a topology change.
    private var disabledDisplays: Set<DisplayIdentifier> = []
    private var disabledDisplaySnapshots: [String: DisplayInfo] = [:]
    
    private init() {
        loadDisabledDisplaySnapshots()
    }
    
    private func identifier(for displayID: CGDirectDisplayID) -> DisplayIdentifier {
        DisplayIdentifier(displayID: displayID)
    }
    
    public func isDisplayDisabled(_ displayID: CGDirectDisplayID) -> Bool {
        isDisplayDisabled(identifier(for: displayID))
    }
    
    func isDisplayDisabled(_ identifier: DisplayIdentifier) -> Bool {
        return disabledDisplays.contains(identifier)
    }
    
    func resetTrackedStateForTesting() {
        disabledDisplays.removeAll()
        disabledDisplaySnapshots.removeAll()
        persistDisabledDisplaySnapshots()
    }
    
    func markDisabledForTesting(_ identifier: DisplayIdentifier) {
        disabledDisplays.insert(identifier)
    }
    
    func clearDisabledForTesting(_ identifier: DisplayIdentifier) {
        disabledDisplays.remove(identifier)
        disabledDisplaySnapshots.removeValue(forKey: identifier.id)
        persistDisabledDisplaySnapshots()
    }
    
    public func syncWithActiveDisplays(_ activeDisplays: [DisplayInfo]) {
        let activeIDs = Set(activeDisplays.map(\.identifier.id))
        var changed = false
        
        let initialCount = disabledDisplays.count
        disabledDisplays = disabledDisplays.filter { !activeIDs.contains($0.id) }
        if disabledDisplays.count != initialCount {
            changed = true
        }
        
        for activeID in activeIDs {
            if disabledDisplaySnapshots.removeValue(forKey: activeID) != nil {
                changed = true
            }
        }
        
        if changed {
            persistDisabledDisplaySnapshots()
        }
    }
    
    public func disabledDisplaySnapshots(excluding activeDisplays: [DisplayInfo]) -> [DisplayInfo] {
        let activeIDs = Set(activeDisplays.map(\.identifier.id))
        return disabledDisplaySnapshots.values
            .filter { !activeIDs.contains($0.identifier.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    public func rememberDisplaySnapshot(_ display: DisplayInfo) {
        disabledDisplays.insert(display.identifier)
        disabledDisplaySnapshots[display.identifier.id] = display.disconnectedSnapshot()
        persistDisabledDisplaySnapshots()
    }
    
    @discardableResult
    public func resetDisplayConnections() -> Bool {
        let snapshotDisplayIDs = disabledDisplaySnapshots.values.map(\.displayID)
        let currentDisplayIDs = DisplayManager.shared.displays.map(\.displayID)
        let fallbackDisplayIDs = Array(CGDirectDisplayID(1)...CGDirectDisplayID(32))
        let displayIDs = Array(Set(snapshotDisplayIDs + currentDisplayIDs + fallbackDisplayIDs)).sorted()
        
        var didReconnect = false
        for displayID in displayIDs {
            if DisplayConnectionService.shared.setEnabled(displayID: displayID, enabled: true) {
                didReconnect = true
            }
        }
        
        if didReconnect {
            disabledDisplays.removeAll()
            disabledDisplaySnapshots.removeAll()
            persistDisabledDisplaySnapshots()
        }
        
        DiagnosticsService.shared.log(
            displayID: 0,
            operation: "resetDisplayConnections",
            success: didReconnect,
            details: "Attempted to reconnect display IDs: \(displayIDs.map(String.init).joined(separator: ", "))"
        )
        return didReconnect
    }
    
    @discardableResult
    public func disableDisplay(displayID: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsActive(displayID) != 0 else {
            return false
        }
        
        var activeCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &activeCount)
        if activeCount <= 1 {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "disableDisplay",
                success: false,
                details: "Cannot disable display: it is the only active display on the system."
            )
            return false
        }
        
        let displayIdentifier = identifier(for: displayID)
        if let display = DisplayManager.shared.displays.first(where: { $0.displayID == displayID }) {
            rememberDisplaySnapshot(display)
        }
        
        let softDisconnectSuccess = DisplayConnectionService.shared.setEnabled(displayID: displayID, enabled: false)
        let ddcPowerSuccess = softDisconnectSuccess ? false : DDCService.shared.setPower(displayID: displayID, on: false)
        
        guard softDisconnectSuccess || ddcPowerSuccess else {
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "disableDisplay",
                success: false,
                details: "Failed to soft-disconnect display and DDC standby is unsupported."
            )
            return false
        }
        
        disabledDisplays.insert(displayIdentifier)
        
        let details = "Soft Disconnect: \(softDisconnectSuccess ? "Success" : "Failed"), DDC Power: \(ddcPowerSuccess ? "Success" : "Skipped/Failed"), Brightness: Skipped, Mirroring: Skipped"
        
        DiagnosticsService.shared.log(
            displayID: displayID,
            operation: "disableDisplay",
            success: true,
            details: "Display disabled. Details: \(details)"
        )
        return true
    }
    
    @discardableResult
    public func enableDisplay(displayID: CGDirectDisplayID) -> Bool {
        let displayIdentifier = identifier(for: displayID)
        let softConnectSuccess = DisplayConnectionService.shared.setEnabled(displayID: displayID, enabled: true)
        let ddcPowerSuccess = softConnectSuccess ? false : DDCService.shared.setPower(displayID: displayID, on: true)
        
        if softConnectSuccess || ddcPowerSuccess {
            disabledDisplays.remove(displayIdentifier)
            disabledDisplaySnapshots.removeValue(forKey: displayIdentifier.id)
            persistDisabledDisplaySnapshots()
            
            let details = "Soft Connect: \(softConnectSuccess ? "Success" : "Failed"), DDC Power: \(ddcPowerSuccess ? "Success" : "Skipped/Failed"), Brightness: Skipped, Mirroring Removed: Skipped"
            
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "enableDisplay",
                success: true,
                details: "Display enabled. Details: \(details)"
            )
            return true
        }
        
        // Fallback: Sweep all possible display IDs to reconnect.
        // This is necessary if the transient display ID has changed after a topology update or app restart.
        print("[DisplayPowerService] Direct enable failed for DisplayID \(displayID). Attempting fallback sweep...")
        let sweepSuccess = resetDisplayConnections()
        if sweepSuccess {
            disabledDisplays.remove(displayIdentifier)
            disabledDisplaySnapshots.removeValue(forKey: displayIdentifier.id)
            persistDisabledDisplaySnapshots()
            
            DiagnosticsService.shared.log(
                displayID: displayID,
                operation: "enableDisplay",
                success: true,
                details: "Display enabled via fallback sweep. Stored displayID was likely outdated."
            )
            return true
        }
        
        DiagnosticsService.shared.log(
            displayID: displayID,
            operation: "enableDisplay",
            success: false,
            details: "Failed to soft-connect display and DDC wake is unsupported (fallback sweep also failed)."
        )
        return false
    }
    
    private func loadDisabledDisplaySnapshots() {
        guard let data = UserDefaults.standard.data(forKey: disabledDisplaySnapshotsKey),
              let snapshots = try? JSONDecoder().decode([DisplayInfo].self, from: data) else {
            return
        }
        
        disabledDisplaySnapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.identifier.id, $0) })
        disabledDisplays = Set(snapshots.map(\.identifier))
    }
    
    private func persistDisabledDisplaySnapshots() {
        let snapshots = Array(disabledDisplaySnapshots.values)
        if snapshots.isEmpty {
            UserDefaults.standard.removeObject(forKey: disabledDisplaySnapshotsKey)
            return
        }
        
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: disabledDisplaySnapshotsKey)
        }
    }
}
