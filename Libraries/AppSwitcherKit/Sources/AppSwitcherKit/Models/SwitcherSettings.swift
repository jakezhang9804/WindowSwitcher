public struct SwitcherSettings: Codable, Equatable {
    /// Legacy fields are preserved losslessly so saving an unrelated group does
    /// not destroy settings created by versions that supported pinned apps.
    public var allowedBundleIDs: Set<String>
    public var appBindings: [AppBinding]
    public var appGroups: [AppGroup]

    public init(
        allowedBundleIDs: Set<String> = [],
        appBindings: [AppBinding] = [],
        appGroups: [AppGroup] = []
    ) {
        self.allowedBundleIDs = allowedBundleIDs
        self.appBindings = appBindings
        self.appGroups = appGroups
    }

    // Custom decoding keeps every historical shape loadable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.allowedBundleIDs = try container.decodeIfPresent(Set<String>.self, forKey: .allowedBundleIDs) ?? []
        self.appBindings = try container.decodeIfPresent([AppBinding].self, forKey: .appBindings) ?? []
        self.appGroups = try container.decodeIfPresent([AppGroup].self, forKey: .appGroups) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case allowedBundleIDs, appBindings, appGroups
    }
}
