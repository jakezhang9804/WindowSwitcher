public struct InstalledApp: Hashable, Codable {
    public let bundleID: String
    public let displayName: String
    public let bundlePath: String

    public init(bundleID: String, displayName: String, bundlePath: String) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.bundlePath = bundlePath
    }
}
