/// Rules for the optional hidden menu bar icon (`MacMonitor.HideMenuBarIcon`).
public enum MenuBarIconVisibility {
    /// On launch/reopen, briefly reveal the icon so the user can reach the menu.
    public static func shouldTemporarilyReveal(hideMenuBarIcon: Bool) -> Bool {
        hideMenuBarIcon
    }

    public static func isVisible(isPresentingTemporaryMenu: Bool, hideMenuBarIcon: Bool) -> Bool {
        isPresentingTemporaryMenu || !hideMenuBarIcon
    }
}
