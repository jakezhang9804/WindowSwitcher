import Foundation
import Testing
@testable import AppSwitcherKit

@Suite("Application MRU store")
struct ApplicationMRUStoreTests {
    @Test("Recording moves an app to the front and persists normalized IDs")
    func recordsAndPersists() throws {
        let suite = "ApplicationMRUStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ApplicationMRUStore(defaults: defaults, key: "mru", limit: 5)
        store.record(bundleID: "com.example.First")
        store.record(bundleID: "com.example.Second")
        store.record(bundleID: "COM.EXAMPLE.FIRST")

        #expect(store.snapshot() == ["com.example.first", "com.example.second"])
        #expect(store.rank(of: "com.example.FIRST") == 0)
        #expect(store.rank(of: "com.example.second") == 1)

        let reloaded = ApplicationMRUStore(defaults: defaults, key: "mru", limit: 5)
        #expect(reloaded.snapshot() == store.snapshot())
    }

    @Test("The MRU ring enforces its capacity and returns the best member rank")
    func capacityAndBestRank() throws {
        let suite = "ApplicationMRUStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ApplicationMRUStore(defaults: defaults, key: "mru", limit: 2)
        store.record(bundleID: "one")
        store.record(bundleID: "two")
        store.record(bundleID: "three")

        #expect(store.snapshot() == ["three", "two"])
        #expect(store.rank(of: "one") == nil)
        #expect(store.bestRank(among: ["missing", "two", "three"]) == 0)
    }
}
