import Foundation

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
            return SwitcherSettings(appGroups: AppGroupRules.sanitized(decoded.appGroups))
        } catch {
            return SwitcherSettings()
        }
    }

    public func save(_ settings: SwitcherSettings) throws {
        let sanitized = SwitcherSettings(appGroups: AppGroupRules.sanitized(settings.appGroups))
        let data = try encoder.encode(sanitized)
        defaults.set(data, forKey: storageKey)
    }
}
