import Testing
import Foundation
import CoreGraphics
@testable import MacMonitorCore

@Suite("MacMonitor Core Logic Tests")
struct MacMonitorCoreTests {

    @Test("Diagnostics include current screen work areas")
    func testDiagnosticsWindowWorkArea() {
        let screens = [
            DiagnosticsReport.ScreenWorkArea(
                name: "Built-in",
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                visibleFrame: CGRect(x: 0, y: 70, width: 1512, height: 879)
            ),
            DiagnosticsReport.ScreenWorkArea(
                name: "External",
                frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
                visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415)
            ),
        ]
        let environment = DiagnosticsReport.Environment(
            generated: Date(),
            osVersion: "Test",
            activationPolicy: "1",
            dockAutoHide: "0",
            dockPosition: "bottom",
            screens: screens
        )
        let report = DiagnosticsReport.make(environment: environment, displays: [], logs: [])
        #expect(report.contains("=== WINDOW WORK AREA ==="))
        #expect(report.contains("Dock Auto Hide:"))
        #expect(report.contains("Dock Position:"))
        for screen in screens {
            #expect(report.contains("  Frame: \(screen.frame)\n"))
            #expect(report.contains("  Visible Frame: \(screen.visibleFrame)\n"))
            #expect(report.contains("  Reserved Bottom: \(screen.visibleFrame.minY - screen.frame.minY) points\n"))
        }
        #expect(report.contains("  Reserved Bottom: 70.0 points\n"))
        #expect(report.contains("No logs recorded yet."))
    }

    @Test("Reveal the menu bar icon only when it is hidden")
    func testTemporaryMenuBarIconReveal() {
        #expect(MenuBarIconVisibility.shouldTemporarilyReveal(hideMenuBarIcon: false) == false)
        #expect(MenuBarIconVisibility.shouldTemporarilyReveal(hideMenuBarIcon: true) == true)
        #expect(MenuBarIconVisibility.isVisible(isPresentingTemporaryMenu: false, hideMenuBarIcon: true) == false)
        #expect(MenuBarIconVisibility.isVisible(isPresentingTemporaryMenu: true, hideMenuBarIcon: true) == true)
        #expect(MenuBarIconVisibility.isVisible(isPresentingTemporaryMenu: false, hideMenuBarIcon: false) == true)
    }
    
    // MARK: - 1. HiDPI Detection Tests
    @Test("Test HiDPI detection with various resolutions")
    func testHiDPIDetection() {
        // Standard Retina screen (2x scaling)
        #expect(DisplayModeGrouping.isModeHiDPI(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160) == true)
        
        // Scaled Retina screen
        #expect(DisplayModeGrouping.isModeHiDPI(width: 2560, height: 1440, pixelWidth: 3840, pixelHeight: 2160) == true)
        
        // Non-HiDPI standard screen (1x scaling)
        #expect(DisplayModeGrouping.isModeHiDPI(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080) == false)
    }
    
    // MARK: - 2. Display Mode Classification Tests
    @Test("Test DisplayModeInfo classification logic")
    func testDisplayModeClassification() throws {
        // Verify that custom initializer properly classifies HiDPI
        let normalMode = DisplayModeInfo(
            width: 1920,
            height: 1080,
            pixelWidth: 1920,
            pixelHeight: 1080,
            refreshRate: 60.0,
            ioFlags: 0
        )
        #expect(normalMode.isHiDPI == false)
        #expect(normalMode.refreshRate == 60.0)
        
        let retinaMode = DisplayModeInfo(
            width: 1920,
            height: 1080,
            pixelWidth: 3840,
            pixelHeight: 2160,
            refreshRate: 120.0,
            ioFlags: 1
        )
        #expect(retinaMode.isHiDPI == true)
        #expect(retinaMode.refreshRate == 120.0)
    }
    
    // MARK: - 3. Refresh Rate Grouping Tests
    @Test("Test DisplayModeGrouping GroupedResolution helper structures")
    func testRefreshRateGrouping() {
        let group = DisplayModeGrouping.GroupedResolution(
            width: 1920,
            height: 1080,
            isHiDPI: true,
            modes: []
        )
        #expect(group.width == 1920)
        #expect(group.height == 1080)
        #expect(group.isHiDPI == true)
        #expect(group.refreshRates.isEmpty)
        #expect(DisplayModeGrouping.groupModesByResolution([]).isEmpty)
        #expect(DisplayModeGrouping.findMode(in: [], width: 1920, height: 1080, refreshRate: 60, isHiDPI: true) == nil)
    }
    
    // MARK: - 4. Config Manifest Cleanup Logic Tests
    // Exercises the manifest mutations ConfigManifestStore applies, without touching
    // the real ~/Library/Application Support/MacMonitor/manifest.json.
    @Test("Test DisplayConfigManifest tracking manifest and registrations")
    func testConfigManifestTracking() {
        var manifest = DisplayConfigManifest()
        #expect(manifest.createdFiles.isEmpty)
        #expect(manifest.backups.isEmpty)
        #expect(manifest.experimentalFlagsEnabled == false)
        
        // Register a file (twice: no duplicates)
        let overridePath = "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-410c/DisplayProductID-1234"
        manifest.registerCreatedFile(overridePath)
        manifest.registerCreatedFile(overridePath)
        #expect(manifest.createdFiles.count == 1)
        #expect(manifest.createdFiles.first == overridePath)
        
        // Register a backup
        manifest.registerBackup(originalPath: "/path/to/orig", backupPath: "/path/to/backup")
        #expect(manifest.backups["/path/to/orig"] == "/path/to/backup")
        #expect(manifest.managedPaths == ["/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-410c/DisplayProductID-1234", "/path/to/orig"])
        
        // Toggle experimental flag
        manifest.experimentalFlagsEnabled = true
        #expect(manifest.experimentalFlagsEnabled == true)
        
        let displayIdentifier = DisplayIdentifier(
            uuid: "HIDPI-DISPLAY-UUID",
            vendorID: 111,
            productID: 222,
            serialNumber: 333
        )
        manifest.setHiDPIEnabled(true, displayIdentifier: displayIdentifier)
        #expect(manifest.isHiDPIEnabled(displayIdentifier: displayIdentifier) == true)
        manifest.setHiDPIEnabled(false, displayIdentifier: displayIdentifier)
        #expect(manifest.isHiDPIEnabled(displayIdentifier: displayIdentifier) == false)
        
        manifest.unregisterBackup(originalPath: "/path/to/orig")
        manifest.unregisterCreatedFile(overridePath)
        #expect(manifest.createdFiles.isEmpty)
        #expect(manifest.backups.isEmpty)
        
        // Clear all (what ConfigManifestStore.clearManifest stores)
        manifest = DisplayConfigManifest()
        #expect(manifest.createdFiles.isEmpty)
        #expect(manifest.backups.isEmpty)
        #expect(manifest.experimentalFlagsEnabled == false)
        #expect(manifest.hiDPIEnabledDisplayIDs.isEmpty)
    }
    
    @Test("Decode older manifest without per-display HiDPI state")
    func testDisplayConfigManifestDecodesLegacyJSON() throws {
        let legacyJSON = """
        {
          "createdFiles": ["/tmp/display-override"],
          "backups": {},
          "experimentalFlagsEnabled": true
        }
        """.data(using: .utf8)!
        
        let manifest = try JSONDecoder().decode(DisplayConfigManifest.self, from: legacyJSON)
        
        #expect(manifest.createdFiles == ["/tmp/display-override"])
        #expect(manifest.experimentalFlagsEnabled == true)
        #expect(manifest.hiDPIEnabledDisplayIDs.isEmpty)
    }
    
    // MARK: - 7. Disabled Display Tracking Tests
    @Test("Track disabled displays by stable identifier instead of transient display ID")
    func testDisabledDisplayTrackingUsesStableIdentifier() {
        var tracker = DisabledDisplayTracker()
        
        let originalIdentifier = DisplayIdentifier(
            uuid: "TEST-DISPLAY-UUID",
            vendorID: 111,
            productID: 222,
            serialNumber: 333
        )
        let reenumeratedIdentifier = DisplayIdentifier(
            uuid: "TEST-DISPLAY-UUID",
            vendorID: 111,
            productID: 222,
            serialNumber: 333
        )
        
        tracker.markDisabled(originalIdentifier)
        
        #expect(tracker.isDisabled(originalIdentifier) == true)
        #expect(tracker.isDisabled(reenumeratedIdentifier) == true)
        tracker.clear(reenumeratedIdentifier)
        #expect(tracker.isDisabled(originalIdentifier) == false)
    }
    
    @Test("Keep a disconnected display snapshot available for reconnect")
    func testDisconnectedDisplaySnapshotStaysVisible() {
        var tracker = DisabledDisplayTracker()
        
        let identifier = DisplayIdentifier(
            uuid: "DISCONNECTED-DISPLAY-UUID",
            vendorID: 111,
            productID: 222,
            serialNumber: 333
        )
        let displayInfo = DisplayInfo(
            displayID: 42,
            identifier: identifier,
            name: "External Test Display",
            isBuiltIn: false,
            isActive: true,
            isOnline: true,
            isAsleep: false,
            isMain: false,
            isMirrored: false,
            currentWidth: 1920,
            currentHeight: 1080,
            currentPixelWidth: 3840,
            currentPixelHeight: 2160,
            refreshRate: 60,
            scaleFactor: 2,
            isHiDPI: true,
            rotation: 0,
            modes: []
        )
        
        tracker.remember(displayInfo)
        let snapshots = tracker.snapshots(excluding: [])
        
        #expect(snapshots.count == 1)
        #expect(snapshots[0].displayID == 42)
        #expect(snapshots[0].isAppDisconnected == true)
        #expect(snapshots[0].isOnline == false)
        
        // Restoring from persisted snapshots keeps the display disabled.
        let restored = DisabledDisplayTracker(snapshots: tracker.snapshotList)
        #expect(restored.isDisabled(identifier) == true)
        
        tracker.clear(identifier)
        #expect(tracker.snapshots(excluding: []).isEmpty)
    }
    
    @Test("DisplayIdentifier custom Equatable and Hashable ignores transient displayID")
    func testDisplayIdentifierCustomEquatableAndHashable() async throws {
        let identifier1 = DisplayIdentifier(
            displayID: 1,
            uuid: "STABLE-UUID",
            vendorID: 111,
            productID: 222,
            serialNumber: 333
        )
        let identifier2 = DisplayIdentifier(
            displayID: 2, // different displayID!
            uuid: "STABLE-UUID",
            vendorID: 111,
            productID: 222,
            serialNumber: 333
        )
        
        #expect(identifier1 == identifier2)
        
        var hasher1 = Hasher()
        identifier1.hash(into: &hasher1)
        let hash1 = hasher1.finalize()
        
        var hasher2 = Hasher()
        identifier2.hash(into: &hasher2)
        let hash2 = hasher2.finalize()
        
        #expect(hash1 == hash2)
    }
    
    @Test("syncWithActiveDisplays prunes active displays from disabled list")
    func testSyncWithActiveDisplaysPrunesActiveDisplays() {
        var tracker = DisabledDisplayTracker()
        
        let identifier = DisplayIdentifier(
            uuid: "TEST-SYNC-UUID",
            vendorID: 111,
            productID: 222,
            serialNumber: 333
        )
        
        let displayInfo = DisplayInfo(
            displayID: 1,
            identifier: identifier,
            name: "Test Sync Display",
            isBuiltIn: false,
            isActive: true,
            isOnline: true,
            isAsleep: false,
            isMain: false,
            isMirrored: false,
            currentWidth: 1920,
            currentHeight: 1080,
            currentPixelWidth: 3840,
            currentPixelHeight: 2160,
            refreshRate: 60,
            scaleFactor: 2,
            isHiDPI: true,
            rotation: 0,
            modes: []
        )
        
        // Mark as disabled initially
        tracker.remember(displayInfo)
        #expect(tracker.isDisabled(identifier) == true)
        #expect(tracker.snapshots(excluding: []).count == 1)
        
        // Sync with active displays containing the display
        #expect(tracker.sync(withActive: [displayInfo]) == true)
        
        // Verify it was pruned
        #expect(tracker.isDisabled(identifier) == false)
        #expect(tracker.snapshots(excluding: []).isEmpty)
        #expect(tracker.sync(withActive: [displayInfo]) == false)
    }

    // MARK: - Helpers extracted from app services

    @Test("Custom resolutions validate ranges and match rotated modes")
    func testCustomResolutionRules() {
        #expect(CustomResolution.isValid(width: 320, height: 200) == true)
        #expect(CustomResolution.isValid(width: 319, height: 1080) == false)
        #expect(CustomResolution.isValid(width: 1920, height: 8193) == false)

        let stored = [CustomResolution(width: 2560, height: 1440)]
        #expect(CustomResolution.contains(width: 2560, height: 1440, rotation: 0, in: stored) == true)
        #expect(CustomResolution.contains(width: 1440, height: 2560, rotation: 90, in: stored) == true)
        #expect(CustomResolution.contains(width: 1440, height: 2560, rotation: 0, in: stored) == false)
    }

    @Test("Display override paths and plist entries")
    func testDisplayOverrideHelpers() {
        let url = DisplayOverride.fileURL(vendorID: 0x410c, productID: 0x1234)
        #expect(url.path == "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-410c/DisplayProductID-1234")
        #expect(DisplayOverride.isManagedOverridePath(url.path) == true)
        #expect(DisplayOverride.isManagedOverridePath("/Library/Displays/Contents/Resources/Overrides/../../../etc/DisplayVendorID-1/DisplayProductID-2") == false)
        #expect(DisplayOverride.isManagedOverridePath("/tmp/DisplayVendorID-1/DisplayProductID-2") == false)
        #expect(DisplayOverride.isVendorDirectory(url.deletingLastPathComponent()) == true)

        let entry = DisplayOverride.scaleResolutionData(width: 3840, height: 2160)
        #expect(Array(entry) == [0, 0, 0x0F, 0x00, 0, 0, 0x08, 0x70, 0, 0, 0, 1, 0, 0, 0, 0])
    }

    @Test("Clear Config preview blocks paths outside the overrides folder")
    func testCleanupPreview() {
        var manifest = DisplayConfigManifest()
        manifest.registerCreatedFile("/tmp/evil")
        manifest.registerCreatedFile(DisplayOverride.fileURL(vendorID: 1, productID: 2).path)
        let preview = manifest.cleanupPreview()
        #expect(preview.contains("Blocked unsafe manifest path: /tmp/evil"))
        #expect(preview.contains { $0.hasPrefix("Remove Mac Monitor file: /Library/Displays/") })
    }

    @Test("DDC/CI packets carry the XOR checksum and replies parse to 0...1")
    func testDDCPackets() {
        // 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32 = 0x9A
        #expect(DDCPacket.setVCPFeature(DDCPacket.vcpBrightness, value: 50) == [0x51, 0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        #expect(DDCPacket.getVCPFeature(DDCPacket.vcpContrast) == [0x51, 0x82, 0x01, 0x12, 0xAE])

        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x64, 0x00, 0x19, 0x00, 0x00, 0x00]
        #expect(DDCPacket.parseVCPReply(reply, vcpCode: DDCPacket.vcpBrightness) == 0.25)
        #expect(DDCPacket.parseVCPReply(reply, vcpCode: DDCPacket.vcpContrast) == nil)
        #expect(DDCPacket.percentValue(1.7) == 100)
    }

    @Test("Privileged commands quote paths for shell and AppleScript")
    func testPrivilegedCommandQuoting() {
        #expect(PrivilegedCommand.shellQuoted("/tmp/it's here") == "'/tmp/it'\\''s here'")
        #expect(PrivilegedCommand.appleScriptSource(for: "echo \"a\\b\"")
            == "do shell script \"echo \\\"a\\\\b\\\"\" with administrator privileges")
    }
}
