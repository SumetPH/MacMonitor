import Foundation
import CoreGraphics
import MacMonitorCore

@MainActor
public final class HiDPIService {
    public static let shared = HiDPIService()
    
    private let fileManager = FileManager.default
    private let overridesPath = DisplayOverride.overridesPath

    private var tempDirectoryURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMonitor/temp")
    }
    
    private init() {}
    
    public func checkOverridesWriteAccess() -> Bool {
        return fileManager.isWritableFile(atPath: overridesPath)
    }
    
    public func isHiDPIOverrideEnabled(for display: DisplayInfo) -> Bool {
        guard let vendorID = display.identifier.vendorID,
              let productID = display.identifier.productID else {
            return false
        }

        let path = overrideFileURL(vendorID: vendorID, productID: productID).path
        return ConfigManifestStore.shared.getManifest().createdFiles.contains(path) &&
               fileManager.fileExists(atPath: path)
    }
    
    public func overrideFileURL(vendorID: UInt32, productID: UInt32) -> URL {
        DisplayOverride.fileURL(vendorID: vendorID, productID: productID)
    }
    
    public func setHiDPIOverrideEnabled(
        _ enabled: Bool,
        for display: DisplayInfo,
        customResolutions: [CustomResolution],
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
        customResolutions: [CustomResolution],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard !customResolutions.isEmpty,
              customResolutions.allSatisfy(\.isValid) else {
            completion(.failure(NSError(
                domain: "HiDPIService",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "ความละเอียดต้องอยู่ระหว่าง 320–8192 พิกเซลสำหรับความกว้าง และ 200–8192 พิกเซลสำหรับความสูง"]
            )))
            return
        }

        let folderName = DisplayOverride.folderName(vendorID: vendorID)
        let fileName = DisplayOverride.fileName(productID: productID)
        let fileURL = DisplayOverride.fileURL(vendorID: vendorID, productID: productID)
        let folderURL = fileURL.deletingLastPathComponent()
        
        do {
            // HiDPI requires double pixel resolution; DisplayOverride doubles each entry.
            let plistData = try DisplayOverride.plistData(
                vendorID: vendorID,
                productID: productID,
                resolutions: customResolutions
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
            
            let manifestStore = ConfigManifestStore.shared
            let manifest = manifestStore.getManifest()
            let wasManaged = manifest.createdFiles.contains(fileURL.path)
            let existingBackupPath = manifest.backups[fileURL.path]
            var backupCreatedForThisWrite: URL?

            if let existingBackupPath,
               (!isAllowedBackupPath(existingBackupPath) || !fileManager.fileExists(atPath: existingBackupPath)) {
                completion(.failure(NSError(
                    domain: "HiDPIService",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "ไม่พบไฟล์ backup เดิม จึงหยุดเพื่อป้องกันการเขียนทับ override ต้นฉบับ"]
                )))
                return
            }

            if fileManager.fileExists(atPath: fileURL.path), !wasManaged, existingBackupPath == nil {
                let backupURL = tempDir.appendingPathComponent("backup_\(folderName)_\(fileName).plist")
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }

                let backupSucceeded: Bool
                do {
                    try fileManager.copyItem(at: fileURL, to: backupURL)
                    backupSucceeded = true
                } catch {
                    backupSucceeded = PrivilegedFileManager.shared.copyItem(fromPath: fileURL.path, toPath: backupURL.path)
                }

                guard backupSucceeded else {
                    completion(.failure(NSError(
                        domain: "HiDPIService",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "สร้าง backup ของ override เดิมไม่สำเร็จ จึงยังไม่ได้แก้ไขไฟล์ระบบ"]
                    )))
                    return
                }

                guard manifestStore.registerBackup(originalPath: fileURL.path, backupPath: backupURL.path) else {
                    try? fileManager.removeItem(at: backupURL)
                    completion(.failure(NSError(
                        domain: "HiDPIService",
                        code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "บันทึกข้อมูล backup ลง manifest ไม่สำเร็จ จึงยังไม่ได้แก้ไขไฟล์ระบบ"]
                    )))
                    return
                }
                backupCreatedForThisWrite = backupURL
            }

            guard manifestStore.registerCreatedFile(fileURL.path) else {
                if let backupCreatedForThisWrite {
                    if manifestStore.unregisterBackup(originalPath: fileURL.path) {
                        try? fileManager.removeItem(at: backupCreatedForThisWrite)
                    }
                }
                completion(.failure(NSError(
                    domain: "HiDPIService",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "บันทึกเส้นทาง override ลง manifest ไม่สำเร็จ จึงยังไม่ได้แก้ไขไฟล์ระบบ"]
                )))
                return
            }

            // To write to the actual destination, we might need a privileged command.
            var writeSuccess = false
            
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
                completion(.failure(NSError(
                    domain: "HiDPIService",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "เขียน Display Override ไม่สำเร็จ ระบบเก็บ manifest และ backup ไว้เพื่อให้ Clear Config กู้คืนได้อย่างปลอดภัย"]
                )))
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

        if let backupPath,
           (!isAllowedBackupPath(backupPath) || !fileManager.fileExists(atPath: backupPath)) {
            completion(.failure(NSError(
                domain: "HiDPIService",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "ไม่พบไฟล์ backup ที่ manifest ระบุ จึงไม่ลบ override เพื่อป้องกันข้อมูลต้นฉบับสูญหาย"]
            )))
            return
        }
        
        if let backupPath, fileManager.fileExists(atPath: backupPath) {
            guard restoreBackup(from: backupPath, to: filePath) else {
                completion(.failure(NSError(
                    domain: "HiDPIService",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "กู้คืน override เดิมจาก backup ไม่สำเร็จ ระบบเก็บ backup และ manifest ไว้สำหรับลองใหม่"]
                )))
                return
            }

            guard ConfigManifestStore.shared.unregisterCreatedFile(filePath),
                  ConfigManifestStore.shared.unregisterBackup(originalPath: filePath) else {
                completion(.failure(NSError(domain: "HiDPIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "กู้คืนไฟล์แล้ว แต่ปรับปรุง manifest ไม่สำเร็จ โปรดลอง Clear Config อีกครั้ง"])))
                return
            }
            try? fileManager.removeItem(atPath: backupPath)
            completion(.success("กู้คืน override เดิมจาก backup แล้ว: \(filePath)"))
            return
        }
        
        guard fileManager.fileExists(atPath: filePath) else {
            guard ConfigManifestStore.shared.unregisterCreatedFile(filePath) else {
                completion(.failure(NSError(domain: "HiDPIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "ไม่พบ override แต่ปรับปรุง manifest ไม่สำเร็จ"])))
                return
            }
            completion(.success("ไม่มี override ให้ลบสำหรับจอนี้"))
            return
        }
        
        guard manifest.createdFiles.contains(filePath) else {
            completion(.failure(NSError(domain: "HiDPIService", code: 409, userInfo: [NSLocalizedDescriptionKey: "พบ override เดิมที่ไม่ได้ถูกสร้างโดย Mac Monitor จึงไม่ลบไฟล์นี้อัตโนมัติ"])))
            return
        }
        
        do {
            try fileManager.removeItem(atPath: filePath)
            guard ConfigManifestStore.shared.unregisterCreatedFile(filePath) else {
                completion(.failure(NSError(domain: "HiDPIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "ลบ override แล้ว แต่ปรับปรุง manifest ไม่สำเร็จ"])))
                return
            }
            completion(.success("ลบ override แล้ว: \(filePath)"))
        } catch {
            if PrivilegedFileManager.shared.removeItem(atPath: filePath) {
                guard ConfigManifestStore.shared.unregisterCreatedFile(filePath) else {
                    completion(.failure(NSError(domain: "HiDPIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "ลบ override แล้ว แต่ปรับปรุง manifest ไม่สำเร็จ"])))
                    return
                }
                completion(.success("ลบ override ด้วยสิทธิ์ผู้ดูแลระบบแล้ว: \(filePath)"))
            } else {
                completion(.failure(NSError(domain: "HiDPIService", code: 403, userInfo: [NSLocalizedDescriptionKey: "ไม่สามารถลบไฟล์ override ของจอนี้ได้"])))
            }
        }
    }

    private func restoreBackup(from backupPath: String, to originalPath: String) -> Bool {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: backupPath))
            do {
                try data.write(to: URL(fileURLWithPath: originalPath), options: .atomic)
                return true
            } catch {
                try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
                let stagedRestoreURL = tempDirectoryURL.appendingPathComponent("restore-\(UUID().uuidString).plist")
                try data.write(to: stagedRestoreURL, options: .atomic)
                defer { try? fileManager.removeItem(at: stagedRestoreURL) }
                return PrivilegedFileManager.shared.copyItem(fromPath: stagedRestoreURL.path, toPath: originalPath)
            }
        } catch {
            return false
        }
    }

    private func isAllowedBackupPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let allowedDirectory = tempDirectoryURL.standardizedFileURL.path + "/"
        guard url.path.hasPrefix(allowedDirectory) else { return false }

        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType != .typeSymbolicLink
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
