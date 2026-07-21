import Testing
import Foundation
import CoreGraphics
@testable import MacMonitor

@Suite("MacMonitor Core Logic Tests")
struct MacMonitorTests {
    
    // MARK: - 1. HiDPI Detection Tests
    @Test("Test HiDPI detection with various resolutions")
    func testHiDPIDetection() async throws {
        // MainActor is required for HiDPIService
        await MainActor.run {
            let hidpiService = HiDPIService.shared
            
            // Standard Retina screen (2x scaling)
            let isHiDPI1 = hidpiService.isModeHiDPI(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160)
            #expect(isHiDPI1 == true)
            
            // Scaled Retina screen
            let isHiDPI2 = hidpiService.isModeHiDPI(width: 2560, height: 1440, pixelWidth: 3840, pixelHeight: 2160)
            #expect(isHiDPI2 == true)
            
            // Non-HiDPI standard screen (1x scaling)
            let isHiDPI3 = hidpiService.isModeHiDPI(width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080)
            #expect(isHiDPI3 == false)
        }
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
    @Test("Test RefreshRateService GroupedResolution helper structures")
    func testRefreshRateGrouping() async throws {
        await MainActor.run {
            // Test that GroupedResolution structure compiles and correctly identifies refresh rates list
            let group = RefreshRateService.GroupedResolution(
                width: 1920,
                height: 1080,
                isHiDPI: true,
                modes: []
            )
            #expect(group.width == 1920)
            #expect(group.height == 1080)
            #expect(group.isHiDPI == true)
            #expect(group.refreshRates.isEmpty)
        }
    }
    
    // MARK: - 4. Config Manifest Cleanup Logic Tests
    @Test("Test ConfigManifestStore tracking manifest and registrations")
    func testConfigManifestTracking() async throws {
        await MainActor.run {
            let manifestStore = ConfigManifestStore.shared
            
            // Clean initial state for test
            manifestStore.clearManifest()
            #expect(manifestStore.getManifest().createdFiles.isEmpty)
            #expect(manifestStore.getManifest().backups.isEmpty)
            #expect(manifestStore.getManifest().experimentalFlagsEnabled == false)
            
            // Register a file
            manifestStore.registerCreatedFile("/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-410c/DisplayProductID-1234")
            #expect(manifestStore.getManifest().createdFiles.count == 1)
            #expect(manifestStore.getManifest().createdFiles.first == "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-410c/DisplayProductID-1234")
            
            // Register a backup
            manifestStore.registerBackup(originalPath: "/path/to/orig", backupPath: "/path/to/backup")
            #expect(manifestStore.getManifest().backups["/path/to/orig"] == "/path/to/backup")
            
            // Toggle experimental flag
            manifestStore.setExperimentalFlagsEnabled(true)
            #expect(manifestStore.getManifest().experimentalFlagsEnabled == true)
            
            let displayIdentifier = DisplayIdentifier(
                uuid: "HIDPI-DISPLAY-UUID",
                vendorID: 111,
                productID: 222,
                serialNumber: 333
            )
            manifestStore.setHiDPIEnabled(true, displayIdentifier: displayIdentifier)
            #expect(manifestStore.isHiDPIEnabled(displayIdentifier: displayIdentifier) == true)
            manifestStore.setHiDPIEnabled(false, displayIdentifier: displayIdentifier)
            #expect(manifestStore.isHiDPIEnabled(displayIdentifier: displayIdentifier) == false)
            
            // Clear all
            manifestStore.clearManifest()
            #expect(manifestStore.getManifest().createdFiles.isEmpty)
            #expect(manifestStore.getManifest().backups.isEmpty)
            #expect(manifestStore.getManifest().experimentalFlagsEnabled == false)
            #expect(manifestStore.getManifest().hiDPIEnabledDisplayIDs.isEmpty)
        }
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
    func testDisabledDisplayTrackingUsesStableIdentifier() async throws {
        await MainActor.run {
            let service = DisplayPowerService.shared
            service.resetTrackedStateForTesting()
            
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
            
            service.markDisabledForTesting(originalIdentifier)
            
            #expect(service.isDisplayDisabled(originalIdentifier) == true)
            #expect(service.isDisplayDisabled(reenumeratedIdentifier) == true)
            service.clearDisabledForTesting(reenumeratedIdentifier)
            #expect(service.isDisplayDisabled(originalIdentifier) == false)
        }
    }
    
    @Test("Keep a disconnected display snapshot available for reconnect")
    func testDisconnectedDisplaySnapshotStaysVisible() async throws {
        await MainActor.run {
            let service = DisplayPowerService.shared
            service.resetTrackedStateForTesting()
            
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
            
            service.rememberDisplaySnapshot(displayInfo)
            let snapshots = service.disabledDisplaySnapshots(excluding: [])
            
            #expect(snapshots.count == 1)
            #expect(snapshots[0].displayID == 42)
            #expect(snapshots[0].isAppDisconnected == true)
            #expect(snapshots[0].isOnline == false)
            
            service.clearDisabledForTesting(identifier)
        }
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
    func testSyncWithActiveDisplaysPrunesActiveDisplays() async throws {
        await MainActor.run {
            let service = DisplayPowerService.shared
            service.resetTrackedStateForTesting()
            
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
            service.rememberDisplaySnapshot(displayInfo)
            #expect(service.isDisplayDisabled(identifier) == true)
            #expect(service.disabledDisplaySnapshots(excluding: []).count == 1)
            
            // Sync with active displays containing the display
            service.syncWithActiveDisplays([displayInfo])
            
            // Verify it was pruned
            #expect(service.isDisplayDisabled(identifier) == false)
            #expect(service.disabledDisplaySnapshots(excluding: []).isEmpty)
        }
    }
}
