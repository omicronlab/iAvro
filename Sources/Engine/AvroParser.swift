//
//  AvroKeyboard
//
//  Swift port of AvroParser.m (original by Rifat Nabi, OmicronLab, 2012).
//

import Foundation

/// Shared longest-match transliteration engine behind AvroParser and
/// RegexParser. The pattern table comes from a bundled JSON file whose
/// "patterns" array is sorted for binary search: longer "find" strings first,
/// same-length strings in ascending order.
///
/// All character handling is done on UTF-16 code units (the original code
/// used `unichar` throughout); every pattern and rule check below mirrors the
/// Objective-C implementation exactly to preserve typing behavior.
// @unchecked Sendable: immutable after init; InputMethodKit drives everything
// on the main thread, matching the original Objective-C's assumptions.
public class PatternTableParser: NSObject, @unchecked Sendable {

    struct RuleMatch {
        let isSuffix: Bool
        let scope: String
        let value: [UInt16]
        let negative: Bool
    }

    struct Rule {
        let matches: [RuleMatch]
        let replace: String
    }

    struct Pattern {
        let find: [UInt16]
        let replace: String
        let rules: [Rule]
    }

    private let vowels: [UInt16]
    private let consonants: [UInt16]
    private let caseSensitives: [UInt16]
    private let patterns: [Pattern]
    private let maxPatternLength: Int

    /// Appended after every pattern replacement. RegexParser uses this to turn
    /// its output into a regular expression; AvroParser appends nothing.
    private let replacementSuffix: String

    init(resourceName: String, replacementSuffix: String = "") {
        self.replacementSuffix = replacementSuffix

        guard let path = Bundle.main.path(forResource: resourceName, ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .uncached),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            fatalError("Unable to load \(resourceName).json")
        }

        vowels = Array(((json["vowel"] as? String) ?? "").utf16)
        consonants = Array(((json["consonant"] as? String) ?? "").utf16)
        caseSensitives = Array(((json["casesensitive"] as? String) ?? "").utf16)

        patterns = ((json["patterns"] as? [[String: Any]]) ?? []).map { rawPattern in
            let rules = ((rawPattern["rules"] as? [[String: Any]]) ?? []).map { rawRule in
                let matches = ((rawRule["matches"] as? [[String: Any]]) ?? []).map { rawMatch -> RuleMatch in
                    let rawNegative = rawMatch["negative"]
                    let negative = (rawNegative as? NSNumber)?.boolValue
                        ?? (rawNegative as? NSString)?.boolValue
                        ?? false
                    return RuleMatch(isSuffix: (rawMatch["type"] as? String) == "suffix",
                                     scope: (rawMatch["scope"] as? String) ?? "",
                                     value: Array(((rawMatch["value"] as? String) ?? "").utf16),
                                     negative: negative)
                }
                return Rule(matches: matches, replace: (rawRule["replace"] as? String) ?? "")
            }
            return Pattern(find: Array(((rawPattern["find"] as? String) ?? "").utf16),
                           replace: (rawPattern["replace"] as? String) ?? "",
                           rules: rules)
        }

        maxPatternLength = patterns.first?.find.count ?? 0
        super.init()
    }

    /// Input normalization applied before matching; subclasses override
    /// (AvroParser lowercases, RegexParser also drops case-sensitive chars).
    func normalized(_ string: String) -> String {
        return string
    }

    func transliterate(_ input: String?) -> String {
        guard let input, !input.isEmpty else { return "" }

        let fixed = Array(normalized(input).utf16)
        let len = fixed.count
        var output = ""

        var cur = 0
        while cur < len {
            let start = cur
            var matched = false

            var chunkLen = maxPatternLength
            while chunkLen > 0 && !matched {
                let end = start + chunkLen
                if end <= len {
                    let chunk = Array(fixed[start..<end])

                    // Binary search over the pattern table (longest first,
                    // then ascending — same ordering as the original code).
                    var left = 0
                    var right = patterns.count - 1
                    while right >= left {
                        let mid = (right + left) / 2
                        let pattern = patterns[mid]
                        if pattern.find == chunk {
                            var ruleApplied = false
                            for rule in pattern.rules where ruleMatches(rule, in: fixed, start: start, end: end) {
                                output += rule.replace + replacementSuffix
                                ruleApplied = true
                                break
                            }
                            if !ruleApplied {
                                output += pattern.replace + replacementSuffix
                            }
                            cur = end - 1
                            matched = true
                            break
                        } else if pattern.find.count > chunk.count
                                    || (pattern.find.count == chunk.count && isLexicallyLess(pattern.find, chunk)) {
                            left = mid + 1
                        } else {
                            right = mid - 1
                        }
                    }
                }
                chunkLen -= 1
            }

            if !matched {
                output += String(utf16CodeUnits: [fixed[cur]], count: 1)
            }
            cur += 1
        }

        return output
    }

    private func ruleMatches(_ rule: Rule, in fixed: [UInt16], start: Int, end: Int) -> Bool {
        let len = fixed.count
        for match in rule.matches {
            let chk = match.isSuffix ? end : start - 1

            switch match.scope {
            case "punctuation":
                // Out-of-bounds positions (string boundaries) count as punctuation.
                let holds = (chk < 0 && !match.isSuffix)
                    || (chk >= len && match.isSuffix)
                    || isPunctuation(fixed[chk])
                if holds == match.negative { return false }

            case "vowel":
                let inBounds = (chk >= 0 && !match.isSuffix) || (chk < len && match.isSuffix)
                let holds = inBounds && isVowel(fixed[chk])
                if holds == match.negative { return false }

            case "consonant":
                let inBounds = (chk >= 0 && !match.isSuffix) || (chk < len && match.isSuffix)
                let holds = inBounds && isConsonant(fixed[chk])
                if holds == match.negative { return false }

            case "exact":
                let s: Int, e: Int
                if match.isSuffix {
                    s = end
                    e = end + match.value.count
                } else {
                    s = start - match.value.count
                    e = start
                }
                // Note: `e < len` (not <=) matches the original implementation.
                let holds = s >= 0 && e < len && Array(fixed[s..<e]) == match.value
                if holds == match.negative { return false }

            default:
                break
            }
        }
        return true
    }

    // Both arrays are the same length when this is called from the search.
    private func isLexicallyLess(_ a: [UInt16], _ b: [UInt16]) -> Bool {
        for (x, y) in zip(a, b) where x != y {
            return x < y
        }
        return false
    }

    // MARK: - Character classification (ASCII-lowercased before lookup)

    final func smallCap(_ c: UInt16) -> UInt16 {
        let upperA: UInt16 = 65, upperZ: UInt16 = 90  // 'A'...'Z'
        if c >= upperA && c <= upperZ {
            return c + 32
        }
        return c
    }

    final func isVowel(_ c: UInt16) -> Bool { vowels.contains(smallCap(c)) }
    final func isConsonant(_ c: UInt16) -> Bool { consonants.contains(smallCap(c)) }
    final func isPunctuation(_ c: UInt16) -> Bool { !(isVowel(c) || isConsonant(c)) }
    final func isCaseSensitive(_ c: UInt16) -> Bool { caseSensitives.contains(smallCap(c)) }
}

/// Transliterates phonetic Latin text into Bengali using the pattern table
/// in data.json.
@objc(AvroParser)
public final class AvroParser: PatternTableParser, @unchecked Sendable {

    private static let shared = AvroParser(resourceName: "data")

    @objc(sharedInstance)
    public class func sharedInstance() -> AvroParser { shared }

    @objc(parse:)
    public func parse(_ string: String?) -> String {
        return transliterate(string)
    }

    /// Lowercases every character that is not marked case-sensitive.
    @objc(fix:)
    public func fix(_ string: String) -> String {
        return normalized(string)
    }

    override func normalized(_ string: String) -> String {
        var units = [UInt16]()
        units.reserveCapacity(string.utf16.count)
        for c in string.utf16 {
            units.append(isCaseSensitive(c) ? c : smallCap(c))
        }
        return String(utf16CodeUnits: units, count: units.count)
    }
}
