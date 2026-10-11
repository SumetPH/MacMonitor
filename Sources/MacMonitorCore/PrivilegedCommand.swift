/// Builds the AppleScript used to run a shell command with administrator
/// privileges. Pure string escaping; execution stays in `PrivilegedFileManager`.
public enum PrivilegedCommand {
    /// Single-quote a value for `/bin/sh` (embedded `'` becomes `'\''`).
    public static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    public static func appleScriptSource(for command: String) -> String {
        // Escape characters สำหรับ AppleScript string
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escapedCommand)\" with administrator privileges"
    }
}
