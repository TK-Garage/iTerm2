import Cocoa

/// Applies localized translations to the main menu bar at runtime.
///
/// Because MainMenu.xib is not stored in Base.lproj, Xcode's built-in
/// XIB localization does not apply automatically. This class walks
/// the menu hierarchy and replaces titles using ja.lproj/MainMenu.strings
/// (or whichever localization matches the user's preferred language).
@objc final class iTermMenuLocalizer: NSObject {

    /// Call once from applicationDidFinishLaunching to translate every
    /// menu item in the main menu bar.
    @objc static func localizeMainMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        localizeMenu(mainMenu)
    }

    // MARK: - Private

    private static func localizeMenu(_ menu: NSMenu) {
        menu.title = localized(menu.title)
        for item in menu.items {
            localizeMenuItem(item)
        }
    }

    private static func localizeMenuItem(_ item: NSMenuItem) {
        if !item.isSeparatorItem {
            item.title = localized(item.title)
        }
        if let submenu = item.submenu {
            localizeMenu(submenu)
        }
    }

    private static let tables = ["MainMenu", "iTerm"]

    private static func localized(_ key: String) -> String {
        guard !key.isEmpty else { return key }
        for table in tables {
            let translated = Bundle.main.localizedString(
                forKey: key,
                value: key,
                table: table
            )
            if translated != key {
                return translated
            }
        }
        return key
    }
}
