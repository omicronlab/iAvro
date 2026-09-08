//
//  AvroKeyboard
//
//  Swift port of AvroKeyboardController.m (original by Rifat Nabi,
//  OmicronLab, 2012). The class name is load-bearing: Info.plist's
//  InputMethodServerControllerClass points at "AvroKeyboardController".
//

import Cocoa
import InputMethodKit

@objc(AvroKeyboardController)
public class AvroKeyboardController: IMKInputController {

    /// Splits the composed buffer into (prefix, term, suffix), where prefix
    /// and suffix are runs of punctuation transliterated directly and term
    /// is looked up for suggestions. Same expression as the original
    /// (RegexKitLite there, NSRegularExpression here).
    private static let bufferSplitRegex = try! NSRegularExpression(
        pattern: #"(^(?::`|\.`|[-\]\\~!@#&*()_=+\[{}'";<>/?|.,])*?(?=(?:,{2,}))|^(?::`|\.`|[-\]\\~!@#&*()_=+\[{}'";<>/?|.,])*)(.*?(?:,,)*)((?::`|\.`|[-\]\\~!@#&*()_=+\[{}'";<>/?|.,])*$)"#)

    // The composed buffer is UTF-16-unit based (deleteBackward removes one
    // unit), matching the original NSMutableString behavior.
    private let composedBuffer = NSMutableString()

    /// After the first lookup this is Suggestion's own long-lived array;
    /// clearing and decorating it in place is intentional (see Suggestion).
    private var currentCandidates = NSMutableArray()

    private var prevSelected = -1
    private var prefix = ""
    private var term = ""
    private var suffix = ""

    private var includeDictionary: Bool {
        UserDefaults.standard.bool(forKey: "IncludeDictionary")
    }

    // MARK: - Candidate list building

    private func findCurrentCandidates() {
        currentCandidates.removeAllObjects()
        guard composedBuffer.length > 0 else { return }

        let buffer = composedBuffer as String
        let range = NSRange(location: 0, length: composedBuffer.length)
        guard let match = AvroKeyboardController.bufferSplitRegex.firstMatch(in: buffer, range: range) else { return }

        func group(_ index: Int) -> String {
            let groupRange = match.range(at: index)
            return groupRange.location == NSNotFound ? "" : composedBuffer.substring(with: groupRange)
        }

        prefix = AvroParser.sharedInstance().parse(group(1))
        term = group(2)
        suffix = AvroParser.sharedInstance().parse(group(3))

        currentCandidates = Suggestion.sharedInstance().getList(term)
        if currentCandidates.count > 0 {
            var prevString: String?
            if includeDictionary {
                prevSelected = -1
                prevString = CacheManager.sharedInstance().string(forKey: term)
            }
            for i in 0..<currentCandidates.count {
                let item = currentCandidates[i] as? String ?? ""
                // prevSelected != 0 mirrors the original's use of the index
                // as a boolean: once slot 0 is chosen, stop rechecking.
                if includeDictionary && prevSelected != 0 && item == prevString {
                    prevSelected = i
                }
                currentCandidates[i] = "\(prefix)\(item)\(suffix)"
            }
            // Emoticons
            if (composedBuffer as String) != term && includeDictionary {
                if let smily = AutoCorrect.sharedInstance().find(composedBuffer as String) {
                    currentCandidates.insert(smily, at: 0)
                }
            }
        } else {
            currentCandidates.add(prefix)
        }
    }

    private func updateCandidatesPanel() {
        let candidateCount = currentCandidates.count
        let selectedIndex = prevSelected
        let panelType = IMKCandidatePanelType(UserDefaults.standard.integer(forKey: "CandidatePanelType"))
        // IMK delivers all controller callbacks on the main thread; the
        // candidate panel is @MainActor, so assert that isolation here.
        MainActor.assumeIsolated {
            guard let panel = Candidates.sharedInstance() else { return }
            if candidateCount > 0 {
                panel.setPanelType(panelType)
                panel.update()
                panel.show(kIMKLocateCandidatesBelowHint)
                if selectedIndex > -1 {
                    panel.selectCandidate(selectedIndex)
                }
            } else {
                panel.hide()
            }
        }
    }

    private func selectedCandidateString() -> NSAttributedString? {
        nonisolated(unsafe) var result: NSAttributedString?
        MainActor.assumeIsolated {
            result = Candidates.sharedInstance()?.selectedCandidateString()
        }
        return result
    }

    // MARK: - IMKInputController overrides

    public override func candidates(_ sender: Any!) -> [Any]! {
        return currentCandidates as? [Any]
    }

    public override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
        guard includeDictionary, !term.isEmpty, let candidateString else { return }

        let isDefaultSelection = candidateString.string == (currentCandidates.firstObject as? String)
        if !(isDefaultSelection && prevSelected == -1) {
            let prefixLength = (prefix as NSString).length
            let suffixLength = (suffix as NSString).length
            let range = NSRange(location: prefixLength,
                                length: candidateString.length - (prefixLength + suffixLength))
            CacheManager.sharedInstance().setString((candidateString.string as NSString).substring(with: range),
                                                    forKey: term)

            // Reverse suffix caching
            if let baseInfo = CacheManager.sharedInstance().base(forKey: candidateString.string),
               baseInfo.count > 1 {
                CacheManager.sharedInstance().setString(baseInfo[1], forKey: baseInfo[0])
            }
        }
    }

    public override func candidateSelected(_ candidateString: NSAttributedString!) {
        client()?.insertText(candidateString, replacementRange: NSRange(location: NSNotFound, length: 0))

        clearCompositionBuffer()
        currentCandidates.removeAllObjects()
        updateCandidatesPanel()
    }

    public override func commitComposition(_ sender: Any!) {
        (sender as? IMKTextInput)?.insertText(composedBuffer, replacementRange: NSRange(location: NSNotFound, length: 0))

        clearCompositionBuffer()
        currentCandidates.removeAllObjects()
        updateCandidatesPanel()
    }

    public override func composedString(_ sender: Any!) -> Any! {
        return NSAttributedString(string: composedBuffer as String)
    }

    private func clearCompositionBuffer() {
        composedBuffer.deleteCharacters(in: NSRange(location: 0, length: composedBuffer.length))
    }

    public override func inputText(_ string: String!, client sender: Any!) -> Bool {
        // Returning true swallows the keystroke; returning false passes the
        // original key event through to the client application.
        if string == " " {
            if currentCandidates.count > 0 {
                candidateSelected(selectedCandidateString())
            }
            return false
        } else {
            composedBuffer.append(string)
            findCurrentCandidates()
            updateComposition()
            updateCandidatesPanel()
            return true
        }
    }

    @objc func deleteBackward(_ sender: Any!) {
        // Called only when the composition buffer is non-empty.
        composedBuffer.deleteCharacters(in: NSRange(location: composedBuffer.length - 1, length: 1))
        findCurrentCandidates()
        updateComposition()
        updateCandidatesPanel()
    }

    @objc func insertTab(_ sender: Any!) {
        commitText("\t")
    }

    @objc func insertNewline(_ sender: Any!) {
        if UserDefaults.standard.bool(forKey: "CommitNewLineOnEnter") {
            commitText("\n")
        } else {
            commitText("")
        }
    }

    public override func didCommand(by aSelector: Selector!, client sender: Any!) -> Bool {
        // Return true only for commands handled here, so everything else
        // reaches the client application untouched.
        if responds(to: aSelector), composedBuffer.length > 0 {
            if aSelector == #selector(insertTab(_:))
                || aSelector == #selector(insertNewline(_:))
                || aSelector == #selector(deleteBackward(_:)) {
                perform(aSelector, with: sender)
                return true
            }
        }
        return false
    }

    @objc(commitText:)
    public func commitText(_ string: String) {
        if let selected = selectedCandidateString() {
            candidateSelected(selected)
        }
        client()?.insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    public override func menu() -> NSMenu! {
        nonisolated(unsafe) var result: NSMenu?
        MainActor.assumeIsolated {
            result = (NSApp.delegate as AnyObject).menu
        }
        return result
    }
}
