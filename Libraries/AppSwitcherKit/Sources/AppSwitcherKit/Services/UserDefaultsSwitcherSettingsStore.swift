import Foundation

public enum SwitcherSettingsStoreError: Error {
    case conflictingBindings(bundleIDs: [String])
}

extension SwitcherSettingsStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .conflictingBindings(let bundleIDs):
            return "Duplicate trigger keys exist for bundle IDs: \(bundleIDs.joined(separator: ", "))."
        }
    }
}

public final class UserDefaultsSwitcherSettingsStore: SwitcherSettingsStoring {
    public static let defaultStorageKey = "switcher.settings.v1"

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = UserDefaultsSwitcherSettingsStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func load() -> SwitcherSettings {
        guard let data = defaults.data(forKey: storageKey) else {
            return SwitcherSettings()
        }

        do {
            let decoded = try decoder.decode(SwitcherSettings.self, from: data)
            return SwitcherSettings(
                allowedBundleIDs: decoded.allowedBundleIDs,
                appBindings: AppBindingRules.normalizedBindings(decoded.appBindings)
            )
        } catch {
            return SwitcherSettings()
        }
    }

    public func save(_ settings: SwitcherSettings) throws {
        var normalizedCandidates: [AppBinding] = []

        for binding in settings.appBindings {
            guard !binding.bundleID.isEmpty,
                  let normalizedKey = AppBindingRules.normalizeTriggerKey(binding.triggerKey) else {
                continue
            }

            normalizedCandidates.append(
                AppBinding(bundleID: binding.bundleID, triggerKey: normalizedKey)
            )
        }

        let conflicts = AppBindingRules.conflictingBundleIDs(for: normalizedCandidates)
        if !conflicts.isEmpty {
            throw SwitcherSettingsStoreError.conflictingBindings(bundleIDs: Array(conflicts).sorted())
        }

        let sanitized = SwitcherSettings(
            allowedBundleIDs: settings.allowedBundleIDs,
            appBindings: AppBindingRules.normalizedBindings(normalizedCandidates)
        )

        let data = try encoder.encode(sanitized)
        defaults.set(data, forKey: storageKey)
    }
}
