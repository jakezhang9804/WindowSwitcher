public struct SwitcherSettings: Codable, Equatable {
    public var appGroups: [AppGroup]

    public init(appGroups: [AppGroup] = []) {
        self.appGroups = appGroups
    }

    // Custom decoding keeps settings stored by older versions loadable —
    // legacy keys (allowedBundleIDs, appBindings) are simply ignored.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.appGroups = try container.decodeIfPresent([AppGroup].self, forKey: .appGroups) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case appGroups
    }
}
