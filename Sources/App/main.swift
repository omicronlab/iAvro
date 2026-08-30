//
//  AvroKeyboard
//
//  Swift port of main.m (original by Rifat Nabi, OmicronLab, 2012).
//

import Cocoa
import InputMethodKit

// Each input method needs a unique connection name, matching
// InputMethodConnectionName in Info.plist (no periods or spaces).
let kConnectionName = "Avro_Keyboard_Connection"

_ = AvroParser.sharedInstance()
_ = Suggestion.sharedInstance()

// Initialize the input method server with the bundle identifier.
let server = IMKServer(name: kConnectionName,
                       bundleIdentifier: Bundle.main.bundleIdentifier)

Candidates.allocateSharedInstance(server: server!)

// Load the main nib explicitly (this is a background-only application) and
// keep its top-level objects alive for the app's lifetime — the nib owns
// the application delegate and the Text Input menu.
var topLevelObjects: NSArray?
Bundle.main.loadNibNamed("MainMenu", owner: NSApplication.shared, topLevelObjects: &topLevelObjects)

NSApplication.shared.run()

Candidates.deallocateSharedInstance()
