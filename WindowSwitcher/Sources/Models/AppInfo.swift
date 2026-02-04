import AppKit

/// Represents information about an application
struct AppInfo: Identifiable, Equatable {
    
    // MARK: - Properties
    
    /// Process ID
    let pid: pid_t
    
    /// Application name
    let name: String
    
    /// Bundle identifier
    let bundleIdentifier: String?
    
    /// Application icon
    let icon: NSImage?
    
    /// Whether the app is currently active
    var isActive: Bool
    
    /// Whether the app is hidden
    var isHidden: Bool
    
    // MARK: - Identifiable
    
    var id: pid_t { pid }
    
    // MARK: - Initialization
    
    init(from runningApp: NSRunningApplication) {
        self.pid = runningApp.processIdentifier
        self.name = runningApp.localizedName ?? "Unknown"
        self.bundleIdentifier = runningApp.bundleIdentifier
        self.icon = runningApp.icon
        self.isActive = runningApp.isActive
        self.isHidden = runningApp.isHidden
    }
}
