import AppKit

/// Represents information about a window
struct WindowInfo: Identifiable, Equatable, Hashable {
    
    // MARK: - Properties
    
    /// Unique window identifier (CGWindowID)
    let id: CGWindowID
    
    /// Window title
    let title: String
    
    /// Name of the owning application
    let appName: String
    
    /// Process ID of the owning application
    let appPID: pid_t
    
    /// Bundle identifier of the owning application
    let appBundleIdentifier: String?

    /// Application icon
    let appIcon: NSImage?
    
    /// Timestamp of last access (for sorting by recency)
    var lastAccessTime: Date = Date()

    // MARK: - Initialization

    init(
        id: CGWindowID,
        title: String,
        appName: String,
        appPID: pid_t,
        appBundleIdentifier: String? = nil,
        appIcon: NSImage?,
        lastAccessTime: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.appName = appName
        self.appPID = appPID
        self.appBundleIdentifier = appBundleIdentifier
        self.appIcon = appIcon
        self.lastAccessTime = lastAccessTime
    }
    
    // MARK: - Equatable
    
    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
