public protocol SwitcherSettingsStoring {
    func load() -> SwitcherSettings
    func save(_ settings: SwitcherSettings) throws
}
