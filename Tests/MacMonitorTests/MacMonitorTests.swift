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
    
    // MARK: - 4. Preset Serialization Tests
    @Test("Test Preset Serialization & Deserialization (JSON)")
    func testPresetSerialization() throws {
        let originalPreset = DisplayPreset(
            name: "Home Office LG",
            displayUUID: "D81C1014-998A-4211-8C10-E7A902263F1B",
            displayVendorID: 7890,
            displayProductID: 1234,
            displaySerialNumber: 99999,
            width: 2560,
            height: 1440,
            pixelWidth: 5120,
            pixelHeight: 2880,
            refreshRate: 60.0,
            isHiDPI: true,
            rotation: 90,
            brightness: 0.85,
            isEnabled: true,
            autoApply: true
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(originalPreset)
        let decodedPreset = try decoder.decode(DisplayPreset.self, from: data)
        
        #expect(decodedPreset.id == originalPreset.id)
        #expect(decodedPreset.name == originalPreset.name)
        #expect(decodedPreset.displayUUID == originalPreset.displayUUID)
        #expect(decodedPreset.displayVendorID == originalPreset.displayVendorID)
        #expect(decodedPreset.displayProductID == originalPreset.displayProductID)
        #expect(decodedPreset.displaySerialNumber == originalPreset.displaySerialNumber)
        #expect(decodedPreset.width == originalPreset.width)
        #expect(decodedPreset.height == originalPreset.height)
        #expect(decodedPreset.pixelWidth == originalPreset.pixelWidth)
        #expect(decodedPreset.pixelHeight == originalPreset.pixelHeight)
        #expect(decodedPreset.refreshRate == originalPreset.refreshRate)
        #expect(decodedPreset.isHiDPI == originalPreset.isHiDPI)
        #expect(decodedPreset.rotation == originalPreset.rotation)
        #expect(decodedPreset.brightness == originalPreset.brightness)
        #expect(decodedPreset.isEnabled == originalPreset.isEnabled)
        #expect(decodedPreset.autoApply == originalPreset.autoApply)
    }
    
    // MARK: - 5. Display Matching Tests
    @Test("Test Preset Display Matching logic")
    func testDisplayMatching() throws {
        let preset = DisplayPreset(
            name: "LG 4K Mode",
            displayUUID: "TEST-UUID-12345",
            displayVendorID: 1000,
            displayProductID: 2000,
            displaySerialNumber: 3000,
            width: 1920,
            height: 1080,
            pixelWidth: 3840,
            pixelHeight: 2160,
            refreshRate: 60.0,
            isHiDPI: true,
            rotation: 0
        )
        
        let mockIdentifier = DisplayIdentifier(
            uuid: "TEST-UUID-12345",
            vendorID: 1000,
            productID: 2000,
            serialNumber: 3000
        )
        
        let displayInfo = DisplayInfo(
            displayID: 1,
            identifier: mockIdentifier,
            name: "LG UltraFine 4K",
            isBuiltIn: false,
            isActive: true,
            isOnline: true,
            isAsleep: false,
            isMain: true,
            isMirrored: false,
            currentWidth: 1920,
            currentHeight: 1080,
            currentPixelWidth: 3840,
            currentPixelHeight: 2160,
            refreshRate: 60.0,
            scaleFactor: 2.0,
            isHiDPI: true,
            rotation: 0,
            modes: []
        )
        
        #expect(preset.matches(display: displayInfo) == true)
        
        // Mismatched Display Info
        let wrongIdentifier = DisplayIdentifier(
            uuid: "TEST-UUID-DIFFERENT",
            vendorID: 1111,
            productID: 2222,
            serialNumber: 3333
        )
        
        let wrongDisplay = DisplayInfo(
            displayID: 2,
            identifier: wrongIdentifier,
            name: "Built-in Screen",
            isBuiltIn: true,
            isActive: true,
            isOnline: true,
            isAsleep: false,
            isMain: false,
            isMirrored: false,
            currentWidth: 1440,
            currentHeight: 900,
            currentPixelWidth: 2880,
            currentPixelHeight: 1800,
            refreshRate: 120.0,
            scaleFactor: 2.0,
            isHiDPI: true,
            rotation: 0,
            modes: []
        )
        
        #expect(preset.matches(display: wrongDisplay) == false)
    }
    
    // MARK: - 6. Config Manifest Cleanup Logic Tests
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
}
