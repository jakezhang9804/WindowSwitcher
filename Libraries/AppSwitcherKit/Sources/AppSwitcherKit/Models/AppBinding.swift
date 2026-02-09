public struct AppBinding: Hashable, Codable {
    public let bundleID: String
    public let triggerKey: String

    public init(bundleID: String, triggerKey: String) {
        self.bundleID = bundleID
        self.triggerKey = triggerKey
    }
}
