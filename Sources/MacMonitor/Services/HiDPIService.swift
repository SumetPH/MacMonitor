import Foundation
import CoreGraphics

@MainActor
public final class HiDPIService {
    public static let shared = HiDPIService()
    
    private let fileManager = FileManager.default
    private let overridesPath = "/Library/Displays/Contents/Resources/Overrides"
    
    private init() {}
    
    public func isModeHiDPI(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int) -> Bool {
        return pixelWidth > width || pixelHeight > height
    }
    
    public func getVendorHex(_ vendorID: UInt32) -> String {
        return String(format: "%x", vendorID)
    }
    
    public func getProductHex(_ productID: UInt32) -> String {
        return String(format: "%x", productID)
    }
    
    public func generateScaleResolutionData(width: Int, height: Int) -> Data {
        var wBig = UInt32(width).bigEndian
        var hBig = UInt32(height).bigEndian
        
        var data = Data()
        withUnsafeBytes(of: &wBig) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &hBig) { data.append(contentsOf: $0) }
        
        // Append 4 bytes of flags (usually 0x00000001 or similar, let's keep it simple with 8 bytes or 16 bytes.
        // Some systems expect 16 bytes: [Width][Height][Flags][Scale]
        // Adding 0x00000001 flag
        var flags: UInt32 = UInt32(1).bigEndian
        withUnsafeBytes(of: &flags) { data.append(contentsOf: $0) }
        
        var zero: UInt32 = 0
        withUnsafeBytes(of: &zero) { data.append(contentsOf: $0) }
        
        return data
    }
    
    public func checkOverridesWriteAccess() -> Bool {
        return fileManager.isWritableFile(atPath: overridesPath)
    }
    
    public func isHiDPIOverrideEnabled(for display: DisplayInfo) -> Bool {
        ConfigManifestStore.shared.isHiDPIEnabled(displayIdentifier: display.identifier)
    }
    
    public func overrideFileURL(vendorID: UInt32, productID: UInt32) -> URL {
        let vendorHex = getVendorHex(vendorID)
        let productHex = getProductHex(productID)
        return URL(fileURLWithPath: overridesPath)
            .appendingPathComponent("DisplayVendorID-\(vendorHex)")
            .appendingPathComponent("DisplayProductID-\(productHex)")
    }
    
    public func setHiDPIOverrideEnabled(
        _ enabled: Bool,
        for display: DisplayInfo,
        customResolutions: [(width: Int, height: Int)],
        hotReload: Bool,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let vendorID = display.identifier.vendorID,
              let productID = display.identifier.productID else {
            completion(.failure(NSError(domain: "HiDPIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "ไม่พบ vendor/product ID ของจอภาพนี้"])))
            return
        }
        
        if enabled {
            createOverrideFile(
                vendorID: vendorID,
                productID: productID,
                customResolutions: customResolutions
            ) { result in
                switch result {
                case .success(let path):
                    ConfigManifestStore.shared.setHiDPIEnabled(true, displayIdentifier: display.identifier)
                    self.hotReloadIfNeeded(displayID: display.displayID, enabled: hotReload)
                    completion(.success(path))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            removeOverrideFile(vendorID: vendorID, productID: productID) { result in
                switch result {
                case .success(let path):
                    ConfigManifestStore.shared.setHiDPIEnabled(false, displayIdentifier: display.identifier)
                    self.hotReloadIfNeeded(displayID: display.displayID, enabled: hotReload)
                    completion(.success(path))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    public func createOverrideFile(
        vendorID: UInt32,
        productID: UInt32,
        customResolutions: [(width: Int, height: Int)],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let vendorHex = getVendorHex(vendorID)
        let productHex = getProductHex(productID)
        
        let folderName = "DisplayVendorID-\(vendorHex)"
        let fileName = "DisplayProductID-\(productHex)"
        
        let folderURL = URL(fileURLWithPath: overridesPath).appendingPathComponent(folderName)
        let fileURL = folderURL.appendingPathComponent(fileName)
        
        // Generate scale-resolutions array
        var scaleResolutionsData: [Data] = []
        for res in customResolutions {
            // HiDPI requires double pixel resolution
            let data = generateScaleResolutionData(width: res.width * 2, height: res.height * 2)
            scaleResolutionsData.append(data)
        }
        
        // Create Plist dictionary
        let plistDict: [String: Any] = [
            "DisplayProductID": Int(productID),
            "DisplayVendorID": Int(vendorID),
            "scale-resolutions": scaleResolutionsData
        ]
        
        do {
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: plistDict,
                format: .xml,
                options: 0
            )
            
            // We need root/admin permission to write to /Library/Displays/...
            // We'll write to a temp file in App Support first, then copy or ask the user to authorize.
            let tempDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacMonitor/temp")
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            let tempFileURL = tempDir.appendingPathComponent("\(folderName)_\(fileName).plist")
            
            try plistData.write(to: tempFileURL)
            
            DiagnosticsService.shared.log(
                displayID: 0,
                operation: "createOverrideFile",
                success: true,
                details: "Created temporary display override plist at \(tempFileURL.path)"
            )
            
            // Register file to manifest
            ConfigManifestStore.shared.registerCreatedFile(fileURL.path)
            
            // To write to the actual destination, we might need a privileged command.
            // Let's copy it. If it fails due to permission, we try using PrivilegedFileManager.
            var writeSuccess = false
            
            // Backup existing file if needed
            if fileManager.fileExists(atPath: fileURL.path) {
                let backupURL = tempDir.appendingPathComponent("\(fileName).bak")
                if fileManager.fileExists(atPath: backupURL.path) {
                    try? fileManager.removeItem(at: backupURL)
                }
                
                // Try backup normally first
                do {
                    try fileManager.copyItem(at: fileURL, to: backupURL)
                    ConfigManifestStore.shared.registerBackup(originalPath: fileURL.path, backupPath: backupURL.path)
                } catch {
                    // Try backup with privileges
                    if PrivilegedFileManager.shared.copyItem(fromPath: fileURL.path, toPath: backupURL.path) {
                        ConfigManifestStore.shared.registerBackup(originalPath: fileURL.path, backupPath: backupURL.path)
                    }
                }
            }
            
            // Try normal operations first
            do {
                if !fileManager.fileExists(atPath: folderURL.path) {
                    try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
                }
                try plistData.write(to: fileURL)
                writeSuccess = true
            } catch {
                // Fallback to PrivilegedFileManager if normal creation/write fails
                let dirSuccess = fileManager.fileExists(atPath: folderURL.path) || PrivilegedFileManager.shared.createDirectory(atPath: folderURL.path)
                if dirSuccess {
                    writeSuccess = PrivilegedFileManager.shared.copyItem(fromPath: tempFileURL.path, toPath: fileURL.path)
                }
            }
            
            if writeSuccess {
                completion(.success(fileURL.path))
            } else {
                completion(.failure(NSError(domain: "HiDPIService", code: 403, userInfo: [NSLocalizedDescriptionKey: "ไม่สามารถขอสิทธิ์เขียนไฟล์หน้าจอ (Display Overrides) ในโฟลเดอร์ระบบได้"])))
            }
            
        } catch {
            DiagnosticsService.shared.log(
                displayID: 0,
                operation: "createOverrideFile",
                success: false,
                details: "Failed to write override file: \(error.localizedDescription)"
            )
            completion(.failure(error))
        }
    }
    
    public func removeOverrideFile(
        vendorID: UInt32,
        productID: UInt32,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let fileURL = overrideFileURL(vendorID: vendorID, productID: productID)
        let filePath = fileURL.path
        let manifest = ConfigManifestStore.shared.getManifest()
        let backupPath = manifest.backups[filePath]
        
        if let backupPath, fileManager.fileExists(atPath: backupPath) {
            do {
                if fileManager.fileExists(atPath: filePath) {
                    try fileManager.removeItem(atPath: filePath)
                }
                try fileManager.copyItem(atPath: backupPath, toPath: filePath)
                ConfigManifestStore.shared.unregisterCreatedFile(filePath)
                ConfigManifestStore.shared.unregisterBackup(originalPath: filePath)
                completion(.success("กู้คืน override เดิมจาก backup แล้ว: \(filePath)"))
                return
            } catch {
                _ = PrivilegedFileManager.shared.removeItem(atPath: filePath)
                if PrivilegedFileManager.shared.copyItem(fromPath: backupPath, toPath: filePath) {
                    ConfigManifestStore.shared.unregisterCreatedFile(filePath)
                    ConfigManifestStore.shared.unregisterBackup(originalPath: filePath)
                    completion(.success("กู้คืน override เดิมด้วยสิทธิ์ผู้ดูแลระบบแล้ว: \(filePath)"))
                    return
                }
            }
        }
        
        guard fileManager.fileExists(atPath: filePath) else {
            ConfigManifestStore.shared.unregisterCreatedFile(filePath)
            completion(.success("ไม่มี override ให้ลบสำหรับจอนี้"))
            return
        }
        
        guard manifest.createdFiles.contains(filePath) else {
            completion(.failure(NSError(domain: "HiDPIService", code: 409, userInfo: [NSLocalizedDescriptionKey: "พบ override เดิมที่ไม่ได้ถูกสร้างโดย Mac Monitor จึงไม่ลบไฟล์นี้อัตโนมัติ"])))
            return
        }
        
        do {
            try fileManager.removeItem(atPath: filePath)
            ConfigManifestStore.shared.unregisterCreatedFile(filePath)
            completion(.success("ลบ override แล้ว: \(filePath)"))
        } catch {
            if PrivilegedFileManager.shared.removeItem(atPath: filePath) {
                ConfigManifestStore.shared.unregisterCreatedFile(filePath)
                completion(.success("ลบ override ด้วยสิทธิ์ผู้ดูแลระบบแล้ว: \(filePath)"))
            } else {
                completion(.failure(NSError(domain: "HiDPIService", code: 403, userInfo: [NSLocalizedDescriptionKey: "ไม่สามารถลบไฟล์ override ของจอนี้ได้"])))
            }
        }
    }
    
    private func hotReloadIfNeeded(displayID: CGDirectDisplayID, enabled: Bool) {
        guard enabled else { return }
        
        let disconnected = DisplayConnectionService.shared.setEnabled(displayID: displayID, enabled: false)
        if disconnected {
            _ = DisplayConnectionService.shared.setEnabled(displayID: displayID, enabled: true)
        } else {
            _ = DisplayPowerService.shared.resetDisplayConnections()
        }
        DisplayManager.shared.refreshDisplays()
    }
}
