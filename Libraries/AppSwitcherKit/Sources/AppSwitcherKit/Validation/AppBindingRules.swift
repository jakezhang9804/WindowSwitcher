import Foundation

public enum AppBindingRules {
    private static let allowedCharacterSet = CharacterSet.alphanumerics

    public static func normalizeTriggerKey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        for scalar in trimmed.unicodeScalars {
            guard scalar.isASCII else {
                continue
            }

            guard allowedCharacterSet.contains(scalar) else {
                continue
            }

            return String(Character(scalar)).uppercased()
        }

        return nil
    }

    public static func conflictingBundleIDs(for bindings: [AppBinding]) -> Set<String> {
        var keyToBundleIDs: [String: Set<String>] = [:]

        for binding in bindings {
            guard let normalizedKey = normalizeTriggerKey(binding.triggerKey),
                  !binding.bundleID.isEmpty else {
                continue
            }

            keyToBundleIDs[normalizedKey, default: []].insert(binding.bundleID)
        }

        var conflicts: Set<String> = []
        for bundleIDs in keyToBundleIDs.values where bundleIDs.count > 1 {
            conflicts.formUnion(bundleIDs)
        }

        return conflicts
    }

    public static func hasConflicts(_ bindings: [AppBinding]) -> Bool {
        !conflictingBundleIDs(for: bindings).isEmpty
    }

    public static func normalizedBindings(_ bindings: [AppBinding]) -> [AppBinding] {
        var seenBundleIDs: Set<String> = []
        var seenKeys: Set<String> = []
        var result: [AppBinding] = []

        for binding in bindings {
            guard !binding.bundleID.isEmpty,
                  let normalizedKey = normalizeTriggerKey(binding.triggerKey),
                  !seenBundleIDs.contains(binding.bundleID),
                  !seenKeys.contains(normalizedKey) else {
                continue
            }

            seenBundleIDs.insert(binding.bundleID)
            seenKeys.insert(normalizedKey)
            result.append(
                AppBinding(bundleID: binding.bundleID, triggerKey: normalizedKey)
            )
        }

        return result
    }
}
