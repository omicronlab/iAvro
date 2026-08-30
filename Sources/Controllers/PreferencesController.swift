//
//  AvroKeyboard
//
//  Swift port of PreferencesController.m (original by Rifat Nabi,
//  OmicronLab, 2012).
//

import Cocoa

/// Preferences window with a toolbar that swaps between the General,
/// AutoCorrect, and About panes, resizing the window to fit.
@objc(PreferencesController)
public final class PreferencesController: NSWindowController, NSToolbarItemValidation {

    // The 2012 nib connects outlets by these exact underscore names — they
    // cannot be renamed without rebuilding the nib.
    @objc var _aboutView: NSView!
    @objc var _autoCorrectView: NSView!
    @objc var _generalView: NSView!
    @objc var _aboutContent: NSTextView!

    private var currentViewTag = 0

    public override func awakeFromNib() {
        super.awakeFromNib()

        // awakeFromNib itself is nonisolated, but nib loading always happens
        // on the main thread; assert that so we can touch the UI.
        MainActor.assumeIsolated {
            window?.setContentSize(_generalView.frame.size)
            window?.contentView?.addSubview(_generalView)
            window?.contentView?.wantsLayer = true

            // Load Credits
            if let creditsPath = Bundle.main.path(forResource: "Credits", ofType: "rtfd") {
                _aboutContent.readRTFD(fromFile: creditsPath)
            }
            _aboutContent.scrollToBeginningOfDocument(_aboutContent)
        }
    }

    private func newFrame(forNewContentView view: NSView) -> NSRect {
        guard let window else { return .zero }
        let newFrameRect = window.frameRect(forContentRect: view.frame)
        let oldFrameRect = window.frame

        var frame = window.frame
        frame.size = newFrameRect.size
        frame.origin.y -= newFrameRect.size.height - oldFrameRect.size.height
        return frame
    }

    private func view(forTag tag: Int) -> NSView {
        switch tag {
        case 0: return _generalView
        case 1: return _autoCorrectView
        default: return _aboutView
        }
    }

    public func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        return item.tag != currentViewTag
    }

    @IBAction func switchView(_ sender: Any) {
        let tag = (sender as AnyObject).tag ?? 0
        let newView = view(forTag: tag)
        let previousView = view(forTag: currentViewTag)
        currentViewTag = tag
        let targetFrame = newFrame(forNewContentView: newView)

        NSAnimationContext.beginGrouping()
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            NSAnimationContext.current.duration = 1.0
        }
        window?.contentView?.animator().replaceSubview(previousView, with: newView)
        window?.animator().setFrame(targetFrame, display: true)
        NSAnimationContext.endGrouping()
    }
}
