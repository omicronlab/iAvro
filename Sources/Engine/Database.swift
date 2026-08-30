//
//  AvroKeyboard
//
//  Swift port of Database.m (original by Rifat Nabi, OmicronLab, 2012).
//  Reads database.db3 directly with SQLite instead of the bundled FMDatabase.
//

import Foundation
import SQLite3

/// Loads the word dictionary (one table per initial phoneme) and the suffix
/// table from the bundled SQLite database into memory, then answers
/// pattern-matching lookups for suggestion building.
@objc(Database)
public final class Database: NSObject, @unchecked Sendable {

    private static let shared = Database()

    @objc(sharedInstance)
    public class func sharedInstance() -> Database { shared }

    private var db: [String: [String]] = [:]
    private var suffixes: [String: String] = [:]

    private static let tableNames = [
        "A", "AA", "B", "BH", "C", "CH", "D", "Dd", "Ddh", "Dh", "E", "G",
        "Gh", "H", "I", "II", "J", "JH", "K", "KH", "Khandatta", "L", "M",
        "N", "NGA", "NN", "NYA", "O", "OI", "OU", "P", "PH", "R", "RR",
        "RRH", "RRI", "S", "SH", "SS", "T", "TH", "TT", "TTH", "U", "UU",
        "Y", "Z",
    ]

    /// Candidate tables to search, keyed by the first letter of the typed term.
    private static let tablesByFirstLetter: [String: [String]] = [
        "a": ["a", "aa", "e", "oi", "o", "nya", "y"],
        "b": ["b", "bh"],
        "c": ["c", "ch", "k"],
        "d": ["d", "dh", "dd", "ddh"],
        "e": ["i", "ii", "e", "y"],
        "f": ["ph"],
        "g": ["g", "gh", "j"],
        "h": ["h"],
        "i": ["i", "ii", "y"],
        "j": ["j", "jh", "z"],
        "k": ["k", "kh"],
        "l": ["l"],
        "m": ["h", "m"],
        "n": ["n", "nya", "nga", "nn"],
        "o": ["a", "u", "uu", "oi", "o", "ou", "y"],
        "p": ["p", "ph"],
        "q": ["k"],
        "r": ["rri", "h", "r", "rr", "rrh"],
        "s": ["s", "sh", "ss"],
        "t": ["t", "th", "tt", "tth", "khandatta"],
        "u": ["u", "uu", "y"],
        "v": ["bh"],
        "w": ["o"],
        "x": ["e", "k"],
        "y": ["i", "y"],
        "z": ["h", "j", "jh", "z"],
    ]

    public override init() {
        super.init()

        guard let path = Bundle.main.path(forResource: "database", ofType: "db3") else { return }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return
        }
        defer { sqlite3_close(handle) }

        for table in Database.tableNames {
            db[table.lowercased()] = stringColumn("SELECT Words FROM \(table)", from: handle)
        }
        loadSuffixTable(from: handle)
    }

    private func stringColumn(_ query: String, from handle: OpaquePointer?) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var items: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                items.append(String(cString: text))
            }
        }
        return items
    }

    private func loadSuffixTable(from handle: OpaquePointer?) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT English, Bangla FROM Suffix", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let english = sqlite3_column_text(statement, 0),
               let bangla = sqlite3_column_text(statement, 1) {
                suffixes[String(cString: english)] = String(cString: bangla)
            }
        }
    }

    /// Returns every dictionary word that matches the regular expression
    /// generated from the typed term. Order is unspecified (the caller sorts).
    @objc(find:)
    func find(_ term: String) -> [String] {
        guard let firstLetter = term.lowercased().first else { return [] }
        let tableList = Database.tablesByFirstLetter[String(firstLetter)] ?? []
        if tableList.isEmpty { return [] }

        let pattern = "^\(RegexParser.sharedInstance().parse(term))$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var results = Set<String>()
        for table in tableList {
            for word in db[table] ?? [] {
                let range = NSRange(location: 0, length: (word as NSString).length)
                if regex.firstMatch(in: word, options: [], range: range) != nil {
                    results.insert(word)
                }
            }
        }
        return Array(results)
    }

    @objc(banglaForSuffix:)
    func banglaForSuffix(_ suffix: String) -> String? {
        return suffixes[suffix]
    }
}
