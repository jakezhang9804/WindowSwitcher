/// A legacy per-application shortcut binding retained for lossless migration.
/// WindowSwitcher 0.7 does not expose this feature, but preserving the values
/// prevents an unrelated window-group edit from erasing older user settings.
public struct AppBinding: Hashable, Codable, Sendable {
    public let bundleID: String
    public let triggerKey: String

    public init(bundleID: String, triggerKey: String) {
        self.bundleID = bundleID
        self.triggerKey = triggerKey
    }
}
