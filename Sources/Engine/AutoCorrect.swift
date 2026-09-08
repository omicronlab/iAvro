//
//  AvroKeyboard
//
//  Swift port of AutoCorrect.m (original by Rifat Nabi, OmicronLab, 2012).
//

import Foundation

/// Loads autodict.dct ("wrong right" pairs, one per line, sorted by the wrong
/// spelling) and answers binary-search lookups. Entries whose two fields
/// differ are transliterated through AvroParser at load time; identical pairs
/// (emoticons) are kept literal.
@objc(AutoCorrect)
public final class AutoCorrect: NSObject, @unchecked Sendable {

    private static let shared = AutoCorrect()

    @objc(sharedInstance)
    public class func sharedInstance() -> AutoCorrect { shared }

    /// Foundation containers and `dynamic` because the preferences nib
    /// instantiates this class and binds an NSArrayController to this property.
    @objc public dynamic var autoCorrectEntries: NSMutableArray = NSMutableArray()

    public override init() {
        super.init()

        guard let path = Bundle.main.path(forResource: "autodict", ofType: "dct") else { return }
        guard let content = (try? String(contentsOfFile: path, encoding: .utf8))
            ?? (try? String(contentsOfFile: path, encoding: .isoLatin1)) else { return }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let separator = line.rangeOfCharacter(from: .whitespaces) else { continue }

            let replace = String(line[..<separator.lowerBound])
            var with = String(line[separator.upperBound...].drop { $0 == " " || $0 == "\t" })

            if replace != with {
                with = AvroParser.sharedInstance().parse(with)
            }
            autoCorrectEntries.add(NSMutableDictionary(dictionary: ["replace": replace, "with": with]))
        }
    }

    @objc(find:)
    public func find(_ term: String) -> String? {
        let fixedTerm = AvroParser.sharedInstance().fix(term) as NSString

        var left = 0
        var right = autoCorrectEntries.count - 1
        while right >= left {
            let mid = (left + right) / 2
            guard let item = autoCorrectEntries[mid] as? NSDictionary,
                  let replace = item["replace"] as? String else { break }
            switch fixedTerm.compare(replace) {
            case .orderedDescending:
                left = mid + 1
            case .orderedAscending:
                right = mid - 1
            case .orderedSame:
                return item["with"] as? String
            }
        }
        return nil
    }
}
