import Foundation

/// A saved window frame in Accessibility global coordinates (top-left origin).
/// Captured when the user snapshots a group's layout, restored on activation.
public struct AppGroupWindowFrame: Hashable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
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
    /// to when a member has no captured frame
    public var screenIndex: Int
    /// Captured window frames per member (keyed by bundle ID). Empty until the
    /// user snapshots the current layout.
    public var frames: [String: AppGroupWindowFrame]

    public init(
        id: UUID = UUID(),
        name: String,
        bundleIDs: [String],
        screenIndex: Int = 0,
        frames: [String: AppGroupWindowFrame] = [:]
    ) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.screenIndex = screenIndex
        self.frames = frames
    }

    // Custom decoding keeps groups stored before `frames` existed loadable
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.bundleIDs = try container.decode([String].self, forKey: .bundleIDs)
        self.screenIndex = try container.decodeIfPresent(Int.self, forKey: .screenIndex) ?? 0
        self.frames = try container.decodeIfPresent([String: AppGroupWindowFrame].self, forKey: .frames) ?? [:]
    }

    /// Whether a layout has been captured for this group
    public var hasCapturedLayout: Bool { !frames.isEmpty }
}

public enum AppGroupRules {
    /// A group is storable when it has a non-empty name and at least one member.
    /// Frames for bundle IDs that are no longer members are dropped.
    public static func sanitized(_ groups: [AppGroup]) -> [AppGroup] {
        groups.compactMap { group in
            let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let members = group.bundleIDs.filter { !$0.isEmpty }
            guard !name.isEmpty, !members.isEmpty else { return nil }
            var sanitized = group
            sanitized.name = name
            // De-duplicate members, keeping first occurrence order
            var seen = Set<String>()
            sanitized.bundleIDs = members.filter { seen.insert($0).inserted }
            sanitized.screenIndex = max(0, group.screenIndex)
            // Keep only frames whose bundle ID is still a member
            let memberSet = Set(sanitized.bundleIDs)
            sanitized.frames = group.frames.filter { memberSet.contains($0.key) }
            return sanitized
        }
    }
}
