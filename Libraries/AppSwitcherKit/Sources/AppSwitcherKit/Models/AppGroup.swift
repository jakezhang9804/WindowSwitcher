import Foundation

/// A saved window frame in Accessibility global coordinates (top-left origin).
/// Captured when the user snapshots a group's layout, restored on activation.
public struct AppGroupWindowFrame: Hashable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// Normalized origin within the bound display's available travel range.
    /// Optional so frames saved by earlier versions continue to decode.
    public var relativeX: Double?
    public var relativeY: Double?

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        relativeX: Double? = nil,
        relativeY: Double? = nil
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.relativeX = relativeX
        self.relativeY = relativeY
    }
}

/// A named group of applications treated as one switcher entry.
///
/// Activating a group launches any members that aren't running, restores each
/// member's window to its saved position and size (or moves it to the bound
/// screen when no layout was captured), and brings them all to the front —
/// a lightweight "workspace".
public struct AppGroup: Identifiable, Hashable, Codable {
    public let id: UUID
    public var name: String
    /// Member applications, in activation order — the first member ends up focused
    public var bundleIDs: [String]
    /// Index into `NSScreen.screens` whose screen the group's windows are moved
    /// to when a member has no captured frame. Retained as a legacy fallback.
    public var screenIndex: Int
    /// Stable CoreGraphics display UUID. New saves prefer this over screenIndex.
    public var displayID: String?
    /// Captured window frames per member (keyed by bundle ID). Empty until the
    /// user snapshots the current layout.
    public var frames: [String: AppGroupWindowFrame]

    public init(
        id: UUID = UUID(),
        name: String,
        bundleIDs: [String],
        screenIndex: Int = 0,
        displayID: String? = nil,
        frames: [String: AppGroupWindowFrame] = [:]
    ) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.screenIndex = screenIndex
        self.displayID = displayID
        self.frames = frames
    }

    // Custom decoding keeps groups stored before `frames` existed loadable
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.bundleIDs = try container.decode([String].self, forKey: .bundleIDs)
        self.screenIndex = try container.decodeIfPresent(Int.self, forKey: .screenIndex) ?? 0
        self.displayID = try container.decodeIfPresent(String.self, forKey: .displayID)
        self.frames = try container.decodeIfPresent([String: AppGroupWindowFrame].self, forKey: .frames) ?? [:]
    }

    /// Whether a layout has been captured for this group
    public var hasCapturedLayout: Bool { !frames.isEmpty }
}

public enum AppGroupRules {
    /// A group is storable when it has a non-empty name and at least one member.
    /// Frames for bundle IDs that are no longer members are dropped.
    public static func sanitized(_ groups: [AppGroup]) -> [AppGroup] {
        var globallyAssignedMembers = Set<String>()
        var seenGroupIDs = Set<UUID>()
        return groups.compactMap { group in
            guard seenGroupIDs.insert(group.id).inserted else { return nil }
            let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let members = group.bundleIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !name.isEmpty, !members.isEmpty else { return nil }
            var sanitized = group
            sanitized.name = name
            // Bundle IDs are case-insensitive. De-duplicate while preserving the
            // first spelling and activation order reported by Launch Services.
            var seen = Set<String>()
            sanitized.bundleIDs = members.filter { member in
                let key = member.lowercased()
                return seen.insert(key).inserted && globallyAssignedMembers.insert(key).inserted
            }
            guard !sanitized.bundleIDs.isEmpty else { return nil }
            sanitized.screenIndex = max(0, group.screenIndex)
            let displayID = group.displayID?.trimmingCharacters(in: .whitespacesAndNewlines)
            sanitized.displayID = displayID?.isEmpty == false ? displayID : nil
            // Keep frames case-insensitively too; otherwise a casing change in a
            // bundle identifier silently discards a recorded layout on save.
            let memberSet = Set(sanitized.bundleIDs.map { $0.lowercased() })
            sanitized.frames = group.frames.filter { memberSet.contains($0.key.lowercased()) }
            return sanitized
        }
    }
}
