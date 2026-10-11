import Foundation

/// Displays the app has disabled, keyed by stable identifier because macOS can
/// re-enumerate display IDs after a topology change. Pure state; persistence and
/// the actual disconnect live in `DisplayPowerService`.
public struct DisabledDisplayTracker {
    private var disabledDisplays: Set<DisplayIdentifier> = []
    private var snapshotsByID: [String: DisplayInfo] = [:]

    public init() {}

    /// Restore from persisted disconnected snapshots.
    public init(snapshots: [DisplayInfo]) {
        self.snapshotsByID = Dictionary(snapshots.map { ($0.identifier.id, $0) }, uniquingKeysWith: { _, last in last })
        self.disabledDisplays = Set(snapshots.map(\.identifier))
    }

    /// Disconnected snapshots to persist.
    public var snapshotList: [DisplayInfo] {
        Array(snapshotsByID.values)
    }

    public func isDisabled(_ identifier: DisplayIdentifier) -> Bool {
        disabledDisplays.contains(identifier)
    }

    public mutating func markDisabled(_ identifier: DisplayIdentifier) {
        disabledDisplays.insert(identifier)
    }

    /// Mark disabled and keep a disconnected snapshot so the display stays visible for reconnect.
    public mutating func remember(_ display: DisplayInfo) {
        disabledDisplays.insert(display.identifier)
        snapshotsByID[display.identifier.id] = display.disconnectedSnapshot()
    }

    public mutating func clear(_ identifier: DisplayIdentifier) {
        disabledDisplays.remove(identifier)
        snapshotsByID.removeValue(forKey: identifier.id)
    }

    public mutating func removeAll() {
        disabledDisplays.removeAll()
        snapshotsByID.removeAll()
    }

    /// Drop state for displays that are active again. Returns true when anything changed.
    @discardableResult
    public mutating func sync(withActive activeDisplays: [DisplayInfo]) -> Bool {
        let activeIDs = Set(activeDisplays.map(\.identifier.id))
        let initialCount = disabledDisplays.count
        disabledDisplays = disabledDisplays.filter { !activeIDs.contains($0.id) }
        var changed = disabledDisplays.count != initialCount

        for activeID in activeIDs {
            if snapshotsByID.removeValue(forKey: activeID) != nil {
                changed = true
            }
        }
        return changed
    }

    public func snapshots(excluding activeDisplays: [DisplayInfo]) -> [DisplayInfo] {
        let activeIDs = Set(activeDisplays.map(\.identifier.id))
        return snapshotsByID.values
            .filter { !activeIDs.contains($0.identifier.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
