//
//  AvroKeyboard
//
//  Swift port of CacheManager.m (original by Rifat Nabi, OmicronLab, 2012).
//

import Foundation

/// Three small caches used while composing:
/// - weight cache: the user's preferred candidate per term, persisted to
///   Application Support/OmicronLab/Avro Keyboard/weight.plist
/// - phonetic cache: dictionary suggestions per term (session only)
/// - base cache: maps suffixed words back to their base term (session only)
@objc(CacheManager)
public final class CacheManager: NSObject, @unchecked Sendable {

    private static let shared = CacheManager()

    @objc(sharedInstance)
    public class func sharedInstance() -> CacheManager { shared }

    private let weightCache: NSMutableDictionary
    private var phoneticCache: [String: [String]] = [:]
    private var recentBaseCache: [String: [String]] = [:]

    override init() {
        let folder = CacheManager.sharedFolder()
        if !FileManager.default.fileExists(atPath: folder) {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        let plistPath = (folder as NSString).appendingPathComponent("weight.plist")
        weightCache = NSMutableDictionary(contentsOfFile: plistPath) ?? NSMutableDictionary()
        super.init()
    }

    @objc public func persist() {
        let plistPath = (CacheManager.sharedFolder() as NSString).appendingPathComponent("weight.plist")
        weightCache.write(toFile: plistPath, atomically: true)
    }

    private static func sharedFolder() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
        return ((paths[0] as NSString).appendingPathComponent("OmicronLab") as NSString)
            .appendingPathComponent("Avro Keyboard")
    }

    // MARK: - Weight cache

    @objc(stringForKey:)
    public func string(forKey key: String) -> String? {
        return weightCache[key] as? String
    }

    @objc(removeStringForKey:)
    func removeString(forKey key: String) {
        weightCache.removeObject(forKey: key)
    }

    @objc(setString:forKey:)
    public func setString(_ string: String, forKey key: String) {
        weightCache[key] = string
    }

    // MARK: - Phonetic cache

    func array(forKey key: String) -> [String]? {
        return phoneticCache[key]
    }

    func setArray(_ array: [String], forKey key: String) {
        phoneticCache[key] = array
    }

    // MARK: - Base cache

    func removeAllBase() {
        recentBaseCache.removeAll()
    }

    @objc(baseForKey:)
    public func base(forKey key: String) -> [String]? {
        return recentBaseCache[key]
    }

    func setBase(_ base: [String], forKey key: String) {
        recentBaseCache[key] = base
    }
}
