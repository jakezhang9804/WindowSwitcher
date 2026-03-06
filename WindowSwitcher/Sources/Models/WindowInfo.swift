import AppKit

/// Represents information about a window
struct WindowInfo: Identifiable, Equatable, Hashable {
    
    /// Unique window identifier (CGWindowID)
    let id: CGWindowID
    
    /// Window title
    let title: String
    
    /// Name of the owning application
    let appName: String
    
    /// Process ID of the owning application
    let appPID: pid_t
    
    /// Application icon
    let appIcon: NSImage?
    
    /// Application bundle path
    let appPath: String?
    
    /// Number of windows belonging to the same application
    var windowCount: Int
    
    /// Timestamp of last access (for sorting by recency)
    var lastAccessTime: Date
    
    init(
        id: CGWindowID,
        title: String,
        appName: String,
        appPID: pid_t,
        appIcon: NSImage?,
        appPath: String? = nil,
        windowCount: Int = 1,
        lastAccessTime: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.appName = appName
        self.appPID = appPID
        self.appIcon = appIcon
        self.appPath = appPath
        self.windowCount = windowCount
        self.lastAccessTime = lastAccessTime
    }
    
    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
