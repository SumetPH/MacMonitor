import Foundation
import MacMonitorCore
import os

private let logger = Logger(category: "PrivilegedFileManager")

@MainActor
public final class PrivilegedFileManager {
    public static let shared = PrivilegedFileManager()
    
    private init() {}

    /// รันคำสั่งเชลล์สคริปต์ด้วยสิทธิ์ผู้ดูแลระบบ (Administrator Privileges)
    /// - Parameter command: คำสั่งเชลล์ที่จะทำงาน
    /// - Returns: ผลลัพธ์ว่าทำงานสำเร็จหรือไม่
    public func executePrivileged(command: String) -> Bool {
        let scriptSource = PrivilegedCommand.appleScriptSource(for: command)
        
        guard let appleScript = NSAppleScript(source: scriptSource) else {
            return false
        }
        
        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            logger.error("Privileged execution failed: \(error, privacy: .public)")
            return false
        }
        return true
    }
    
    /// สร้างโฟลเดอร์ปลายทางด้วยสิทธิ์ผู้ดูแลระบบ
    public func createDirectory(atPath path: String) -> Bool {
        return executePrivileged(command: "mkdir -p \(PrivilegedCommand.shellQuoted(path))")
    }
    
    /// คัดลอกไฟล์จากต้นทางไปปลายทางด้วยสิทธิ์ผู้ดูแลระบบ
    public func copyItem(fromPath: String, toPath: String) -> Bool {
        return executePrivileged(command: "cp -f \(PrivilegedCommand.shellQuoted(fromPath)) \(PrivilegedCommand.shellQuoted(toPath))")
    }
    
    /// ลบไฟล์ปลายทางด้วยสิทธิ์ผู้ดูแลระบบ
    public func removeItem(atPath path: String) -> Bool {
        return executePrivileged(command: "rm -f \(PrivilegedCommand.shellQuoted(path))")
    }

    /// ลบโฟลเดอร์ด้วยสิทธิ์ผู้ดูแลระบบเฉพาะเมื่อโฟลเดอร์ว่างเท่านั้น
    public func removeDirectoryIfEmpty(atPath path: String) -> Bool {
        return executePrivileged(command: "rmdir \(PrivilegedCommand.shellQuoted(path))")
    }
}
