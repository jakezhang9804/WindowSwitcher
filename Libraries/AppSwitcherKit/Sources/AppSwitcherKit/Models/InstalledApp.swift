public struct InstalledApp: Hashable, Codable, Sendable {
    public let bundleID: String
    public let displayName: String
    public let bundlePath: String
    /// `LSUIElement` and `LSBackgroundOnly` apps remain searchable, but callers
    /// can rank or label them as utilities instead of ordinary document apps.
    public let isBackgroundOnly: Bool
    public let searchAliases: [String]

    public init(
        bundleID: String,
        displayName: String,
        bundlePath: String,
        isBackgroundOnly: Bool = false,
        searchAliases: [String] = []
    ) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.bundlePath = bundlePath
        self.isBackgroundOnly = isBackgroundOnly
        self.searchAliases = searchAliases
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID
        case displayName
        case bundlePath
        case isBackgroundOnly
        case searchAliases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        displayName = try container.decode(String.self, forKey: .displayName)
        bundlePath = try container.decode(String.self, forKey: .bundlePath)
        isBackgroundOnly = try container.decodeIfPresent(Bool.self, forKey: .isBackgroundOnly) ?? false
        searchAliases = try container.decodeIfPresent([String].self, forKey: .searchAliases) ?? []
    }
}
