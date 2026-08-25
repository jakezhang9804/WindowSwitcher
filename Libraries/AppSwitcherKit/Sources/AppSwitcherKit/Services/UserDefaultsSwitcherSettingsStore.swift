import Foundation

public final class UserDefaultsSwitcherSettingsStore: SwitcherSettingsStoring {
    public static let defaultStorageKey = "switcher.settings.v1"

    private let defaults: UserDefaults
    private let storageKey: String
    private var backupStorageKey: String { "\(storageKey).lastKnownGood" }
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
            return sanitized(decoded)
        } catch {
            guard let backupData = defaults.data(forKey: backupStorageKey),
                  let backup = try? decoder.decode(SwitcherSettings.self, from: backupData) else {
                return SwitcherSettings()
            }
            return sanitized(backup)
        }
    }

    public func save(_ settings: SwitcherSettings) throws {
        let sanitized = SwitcherSettings(
            allowedBundleIDs: settings.allowedBundleIDs,
            appBindings: settings.appBindings,
            appGroups: AppGroupRules.sanitized(settings.appGroups)
        )
        let data = try encoder.encode(sanitized)
        defaults.set(data, forKey: storageKey)
        defaults.set(data, forKey: backupStorageKey)
    }

    private func sanitized(_ settings: SwitcherSettings) -> SwitcherSettings {
        SwitcherSettings(
            allowedBundleIDs: settings.allowedBundleIDs,
            appBindings: settings.appBindings,
            appGroups: AppGroupRules.sanitized(settings.appGroups)
        )
    }
}
