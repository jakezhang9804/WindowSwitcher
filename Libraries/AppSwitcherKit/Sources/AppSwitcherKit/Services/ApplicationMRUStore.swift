import Foundation

/// A small persistent most-recently-used ring keyed by normalized bundle ID.
/// WindowServer order remains a per-window tie-breaker, while this store captures
/// the user's actual application activation history across Spaces and relaunches.
public final class ApplicationMRUStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let limit: Int
    private let lock = NSLock()
    private var bundleIDs: [String]

    public init(
        defaults: UserDefaults = .standard,
        key: String = "applicationMRUBundleIDs",
        limit: Int = 100
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = max(1, limit)
        self.bundleIDs = Self.sanitize(defaults.stringArray(forKey: key) ?? [], limit: max(1, limit))
    }

    public func record(bundleID: String) {
        let normalized = Self.normalize(bundleID)
        guard !normalized.isEmpty else { return }

        lock.lock()
        bundleIDs.removeAll { $0 == normalized }
        bundleIDs.insert(normalized, at: 0)
        if bundleIDs.count > limit { bundleIDs.removeLast(bundleIDs.count - limit) }
        let snapshot = bundleIDs
        lock.unlock()

        defaults.set(snapshot, forKey: key)
    }

    public func rank(of bundleID: String) -> Int? {
        let normalized = Self.normalize(bundleID)
        lock.lock()
        let result = bundleIDs.firstIndex(of: normalized)
        lock.unlock()
        return result
    }

    public func bestRank<S: Sequence>(among bundleIDs: S) -> Int? where S.Element == String {
        bundleIDs.compactMap(rank(of:)).min()
    }

    public func snapshot() -> [String] {
        lock.lock()
        let result = bundleIDs
        lock.unlock()
        return result
    }

    private static func sanitize(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(min(values.count, limit))
        for value in values {
            let normalized = normalize(value)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            result.append(normalized)
            if result.count == limit { break }
        }
        return result
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
