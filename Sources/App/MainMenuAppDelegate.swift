//
//  AvroKeyboard
//
//  Swift port of MainMenuAppDelegate.m (original by Rifat Nabi,
//  OmicronLab, 2012).
//

import Cocoa

@objc(MainMenuAppDelegate)
public final class MainMenuAppDelegate: NSObject, NSApplicationDelegate {

    // The 2012 MainMenu nib connects this outlet by its underscore name.
    @objc var _menu: NSMenu!

    /// Exposed so AvroKeyboardController can return the shared menu that
    /// appears in the system's Text Input menu.
    @objc public func menu() -> NSMenu {
        return _menu
    }

    public override func awakeFromNib() {
        super.awakeFromNib()

        // Menu items without an action are disabled in the Text Input Menu;
        // showPreferences: is implemented by IMKInputController.
        if let preferences = _menu.item(withTag: 1) {
            preferences.action = NSSelectorFromString("showPreferences:")
        }

        // Warm the singletons so the first keystroke isn't slow.
        if UserDefaults.standard.bool(forKey: "IncludeDictionary") {
            NSLog("Loading Dictionary...")
            _ = Database.sharedInstance()
            _ = RegexParser.sharedInstance()
            _ = CacheManager.sharedInstance()
        }
        _ = AutoCorrect.sharedInstance()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: "IncludeDictionary") {
            CacheManager.sharedInstance().persist()
        }
    }
}
