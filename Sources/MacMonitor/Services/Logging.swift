import os

extension Logger {
    /// All app logs share the bundle id as subsystem; filter with
    /// `log stream --predicate 'subsystem == "dev.sumetph.MacMonitor"'`.
    init(category: String) {
        self.init(subsystem: "dev.sumetph.MacMonitor", category: category)
    }
}
