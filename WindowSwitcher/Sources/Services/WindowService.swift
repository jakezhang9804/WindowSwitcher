import AppKit
import ApplicationServices

class WindowService {
    
    // MARK: - Public Methods
    
    /// Get all visible windows across all applications
    func getAllWindows() -> [WindowInfo] {
        var result: [WindowInfo] = []
        
        // Get window list from CGWindowList
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return result
        }
        
        // Get running applications for icon lookup
        let runningApps = NSWorkspace.shared.runningApplications
        let appsByPID = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })
        
        for windowDict in windowList {
            // Skip windows without names or with empty names
            guard let windowName = windowDict[kCGWindowName as String] as? String,
                  !windowName.isEmpty else {
                continue
            }
            
            // Get window properties
            guard let windowID = windowDict[kCGWindowNumber as String] as? CGWindowID,
                  let ownerPID = windowDict[kCGWindowOwnerPID as String] as? pid_t,
                  let ownerName = windowDict[kCGWindowOwnerName as String] as? String else {
                continue
            }
            
            // Skip system windows
            let layer = windowDict[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 {
                continue
            }
            
            // Get app icon
            let appIcon = appsByPID[ownerPID]?.icon
            
            // Create WindowInfo
            let windowInfo = WindowInfo(
                id: windowID,
                title: windowName,
                appName: ownerName,
                appPID: ownerPID,
                appIcon: appIcon
            )
            
            result.append(windowInfo)
        }
        
        return result
    }
    
    /// Activate a specific window
    func activateWindow(_ window: WindowInfo) {
        // First, activate the application
        if let app = NSRunningApplication(processIdentifier: window.appPID) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        
        // Then, raise the specific window using Accessibility API
        let appElement = AXUIElementCreateApplication(window.appPID)
        
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return
        }
        
        // Find and raise the matching window
        for axWindow in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            
            if let title = titleRef as? String, title == window.title {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                break
            }
        }
    }
}
