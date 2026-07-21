import Foundation

@MainActor
public final class PrivilegedFileManager {
    public static let shared = PrivilegedFileManager()
    
    private init() {}

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
    
    /// รันคำสั่งเชลล์สคริปต์ด้วยสิทธิ์ผู้ดูแลระบบ (Administrator Privileges)
    /// - Parameter command: คำสั่งเชลล์ที่จะทำงาน
    /// - Returns: ผลลัพธ์ว่าทำงานสำเร็จหรือไม่
    public func executePrivileged(command: String) -> Bool {
        // Escape characters สำหรับ AppleScript string
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        let scriptSource = "do shell script \"\(escapedCommand)\" with administrator privileges"
        
        guard let appleScript = NSAppleScript(source: scriptSource) else {
            return false
        }
        
        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            print("Privileged execution failed: \(error)")
            return false
        }
        return true
    }
    
    /// สร้างโฟลเดอร์ปลายทางด้วยสิทธิ์ผู้ดูแลระบบ
    public func createDirectory(atPath path: String) -> Bool {
        return executePrivileged(command: "mkdir -p \(shellQuoted(path))")
    }
    
    /// คัดลอกไฟล์จากต้นทางไปปลายทางด้วยสิทธิ์ผู้ดูแลระบบ
    public func copyItem(fromPath: String, toPath: String) -> Bool {
        return executePrivileged(command: "cp -f \(shellQuoted(fromPath)) \(shellQuoted(toPath))")
    }
    
    /// ลบไฟล์ปลายทางด้วยสิทธิ์ผู้ดูแลระบบ
    public func removeItem(atPath path: String) -> Bool {
        return executePrivileged(command: "rm -f \(shellQuoted(path))")
    }

    /// ลบโฟลเดอร์ด้วยสิทธิ์ผู้ดูแลระบบเฉพาะเมื่อโฟลเดอร์ว่างเท่านั้น
    public func removeDirectoryIfEmpty(atPath path: String) -> Bool {
        return executePrivileged(command: "rmdir \(shellQuoted(path))")
    }
}
