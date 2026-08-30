//
//  AvroKeyboard
//
//  Swift port of Suggestion.m and NSString+Levenshtein.m
//  (originals by Rifat Nabi, OmicronLab, 2012 and Stefano Pigozzi, 2009).
//

import Foundation

/// Builds the candidate list for a typed term: cached results, autocorrect,
/// dictionary matches sorted by edit distance, suffix-derived words, and
/// finally the plain phonetic transliteration.
@objc(Suggestion)
public final class Suggestion: NSObject, @unchecked Sendable {

    private static let shared = Suggestion()

    @objc(sharedInstance)
    public class func sharedInstance() -> Suggestion { shared }

    /// Shared with AvroKeyboardController, which clears and decorates this
    /// array in place between keystrokes — it must stay one long-lived
    /// NSMutableArray, exactly like the original.
    private let suggestions = NSMutableArray()

    // Bengali kars (dependent vowel signs) and independent vowels; each check
    // replaces a single-character regex match in the original code.
    private static let kars = Set("\u{09be}\u{09bf}\u{09c0}\u{09c1}\u{09c2}\u{09c3}\u{09c7}\u{09c8}\u{09cb}\u{09cc}\u{09c4}".utf16)
    private static let vowels = Set(("\u{0985}\u{0986}\u{0987}\u{0988}\u{0989}\u{098a}\u{098b}\u{098f}\u{0990}\u{0993}\u{0994}"
        + "\u{098c}\u{09e1}\u{09be}\u{09bf}\u{09c0}\u{09c1}\u{09c2}\u{09c3}\u{09c7}\u{09c8}\u{09cb}\u{09cc}").utf16)

    @objc(getList:)
    public func getList(_ term: String) -> NSMutableArray {
        if term.isEmpty {
            return suggestions
        }

        let termNS = term as NSString
        let parsed = AvroParser.sharedInstance().parse(term)
        let cacheManager = CacheManager.sharedInstance()
        let database = Database.sharedInstance()

        if UserDefaults.standard.bool(forKey: "IncludeDictionary") {
            if let cached = cacheManager.array(forKey: term) {
                suggestions.addObjects(from: cached)
            }
            if suggestions.count == 0 {
                let autoCorrect = AutoCorrect.sharedInstance().find(term)
                if let autoCorrect {
                    suggestions.add(autoCorrect)
                }

                let dicList = database.find(term)
                // Remove the autocorrect entry if the dictionary already has it.
                if let autoCorrect, dicList.contains(autoCorrect) {
                    suggestions.remove(autoCorrect)
                }

                let parsedUnits = Array(parsed.utf16)
                let sortedDicList = dicList
                    .map { (word: $0, distance: Suggestion.levenshteinDistance(parsedUnits, Array($0.utf16))) }
                    .sorted { $0.distance < $1.distance }
                    .map(\.word)
                suggestions.addObjects(from: sortedDicList)

                cacheManager.setArray(suggestions.compactMap { $0 as? String }, forKey: term)
            }

            // Suggestions with suffix: split the term at every position and
            // combine cached suggestions for the base with the Bengali suffix.
            var alreadySelected = false
            cacheManager.removeAllBase()
            var i = termNS.length - 1
            while i > 0 {
                defer { i -= 1 }
                guard let suffix = database.banglaForSuffix(termNS.substring(from: i).lowercased()) else { continue }

                let base = termNS.substring(to: i)
                var selected: String?
                if !alreadySelected {
                    selected = cacheManager.string(forKey: base)
                }
                guard let cached = cacheManager.array(forKey: base) else { continue }

                for item in cached {
                    // Skip the autocorrect English entry.
                    if base == item { continue }

                    let itemNS = item as NSString
                    let cutPos = itemNS.length - 1
                    let itemRMC = itemNS.substring(from: cutPos)      // rightmost character
                    let suffixLMC = (suffix as NSString).substring(to: 1)  // leftmost character

                    // Sandhi rules for joining a base word and suffix.
                    let word: String
                    if Suggestion.isSingle(itemRMC, in: Suggestion.vowels) && Suggestion.isSingle(suffixLMC, in: Suggestion.kars) {
                        word = "\(item)\u{09df}\(suffix)"
                    } else if itemRMC == "\u{09ce}" {
                        word = "\(itemNS.substring(to: cutPos))\u{09a4}\(suffix)"
                    } else if itemRMC == "\u{0982}" {
                        word = "\(itemNS.substring(to: cutPos))\u{0999}\(suffix)"
                    } else {
                        word = "\(item)\(suffix)"
                    }

                    // Reverse suffix caching, so selecting the combined word
                    // also teaches the base word's preference.
                    cacheManager.setBase([base, item], forKey: word)

                    if !suggestions.contains(word) {
                        if !alreadySelected, let selected, item == selected {
                            if cacheManager.string(forKey: term) == nil {
                                cacheManager.setString(word, forKey: term)
                            }
                            alreadySelected = true
                        }
                        suggestions.add(word)
                    }
                }
            }
        }

        if !suggestions.contains(parsed) {
            suggestions.add(parsed)
        }

        return suggestions
    }

    @objc(isKar:)
    func isKar(_ letter: String) -> Bool {
        return Suggestion.isSingle(letter, in: Suggestion.kars)
    }

    @objc(isVowel:)
    func isVowel(_ letter: String) -> Bool {
        return Suggestion.isSingle(letter, in: Suggestion.vowels)
    }

    private static func isSingle(_ letter: String, in set: Set<UInt16>) -> Bool {
        let units = Array(letter.utf16)
        return units.count == 1 && set.contains(units[0])
    }

    /// Classic dynamic-programming edit distance on UTF-16 units. Returns -1
    /// when either string is empty (quirk kept from the original library).
    private static func levenshteinDistance(_ a: [UInt16], _ b: [UInt16]) -> Int {
        let n = a.count
        let m = b.count
        if n == 0 || m == 0 { return -1 }

        let width = n + 1
        var d = [Int](repeating: 0, count: width * (m + 1))
        for k in 0...n { d[k] = k }
        for k in 0...m { d[k * width] = k }

        for i in 1...n {
            for j in 1...m {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[j * width + i] = min(d[(j - 1) * width + i] + 1,
                                       d[j * width + i - 1] + 1,
                                       d[(j - 1) * width + i - 1] + cost)
            }
        }
        return d[width * (m + 1) - 1]
    }
}
