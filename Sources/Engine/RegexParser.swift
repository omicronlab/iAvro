//
//  AvroKeyboard
//
//  Swift port of RegexParser.m (original by Rifat Nabi, OmicronLab, 2012).
//

import Foundation

/// Builds a regular-expression pattern from phonetic Latin text using the
/// pattern table in regex.json. Database.find matches the result against
/// every dictionary word to collect suggestions.
@objc(RegexParser)
public final class RegexParser: PatternTableParser, @unchecked Sendable {

    private static let shared = RegexParser(resourceName: "regex",
                                            replacementSuffix: "(\u{09cd}[\u{09af}\u{09ac}\u{09ae}])?(\u{09cd}?)([\u{0983}\u{0981}]?)")

    @objc(sharedInstance)
    public class func sharedInstance() -> RegexParser { shared }

    @objc(parse:)
    public func parse(_ string: String?) -> String {
        return transliterate(string)
    }

    /// Unlike AvroParser's fix(), this drops case-sensitive characters
    /// entirely and lowercases the rest.
    override func normalized(_ string: String) -> String {
        var units = [UInt16]()
        units.reserveCapacity(string.utf16.count)
        for c in string.utf16 where !isCaseSensitive(c) {
            units.append(smallCap(c))
        }
        return String(utf16CodeUnits: units, count: units.count)
    }
}
