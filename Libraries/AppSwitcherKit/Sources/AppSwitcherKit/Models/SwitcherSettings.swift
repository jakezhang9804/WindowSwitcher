public struct SwitcherSettings: Codable, Equatable {
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

    // Custom decoding keeps settings stored before `appGroups` existed loadable
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.allowedBundleIDs = try container.decodeIfPresent(Set<String>.self, forKey: .allowedBundleIDs) ?? []
        self.appBindings = try container.decodeIfPresent([AppBinding].self, forKey: .appBindings) ?? []
        self.appGroups = try container.decodeIfPresent([AppGroup].self, forKey: .appGroups) ?? []
    }

    public var bindingsByBundleID: [String: String] {
        var map: [String: String] = [:]
        for binding in appBindings {
            map[binding.bundleID] = binding.triggerKey
        }
        return map
    }

    public var bindingsByTriggerKey: [String: String] {
        var map: [String: String] = [:]
        for binding in appBindings {
            map[binding.triggerKey] = binding.bundleID
        }
        return map
    }

    public func triggerKey(for bundleID: String) -> String? {
        bindingsByBundleID[bundleID]
    }

    public func bundleID(for triggerKey: String) -> String? {
        guard let normalized = AppBindingRules.normalizeTriggerKey(triggerKey) else {
            return nil
        }
        return bindingsByTriggerKey[normalized]
    }

    public func allows(bundleID: String?) -> Bool {
        guard !allowedBundleIDs.isEmpty else {
            return true
        }

        guard let bundleID else {
            return false
        }

        return allowedBundleIDs.contains(bundleID)
    }
}
