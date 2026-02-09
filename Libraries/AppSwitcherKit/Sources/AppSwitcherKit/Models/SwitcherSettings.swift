public struct SwitcherSettings: Codable, Equatable {
    public var allowedBundleIDs: Set<String>
    public var appBindings: [AppBinding]

    public init(
        allowedBundleIDs: Set<String> = [],
        appBindings: [AppBinding] = []
    ) {
        self.allowedBundleIDs = allowedBundleIDs
        self.appBindings = appBindings
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
