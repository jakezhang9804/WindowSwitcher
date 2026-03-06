import AppKit

/// Represents information about an application
struct AppInfo: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?
    var isActive: Bool
    var isHidden: Bool
    
    var id: pid_t { pid }
    
    init(from runningApp: NSRunningApplication) {
        self.pid = runningApp.processIdentifier
        self.name = runningApp.localizedName ?? "Unknown"
        self.bundleIdentifier = runningApp.bundleIdentifier
        self.icon = runningApp.icon
        self.isActive = runningApp.isActive
        self.isHidden = runningApp.isHidden
    }
}
