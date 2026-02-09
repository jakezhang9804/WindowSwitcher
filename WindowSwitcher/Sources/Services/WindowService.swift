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
        let appsByPID = Dictionary(uniqueKeysWithValues: runningApps.compactMap { app -> (pid_t, NSRunningApplication)? in
            return (app.processIdentifier, app)
        })
        
        // Current app bundle identifier to exclude self
        let currentBundleID = Bundle.main.bundleIdentifier
        
        for windowDict in windowList {
            // Get owner PID first to check if we should skip
            guard let ownerPID = windowDict[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }
            
            // Skip our own windows
            if let app = appsByPID[ownerPID],
               app.bundleIdentifier == currentBundleID {
                continue
            }
            
            // Skip windows without names or with empty names
            guard let windowName = windowDict[kCGWindowName as String] as? String,
                  !windowName.isEmpty else {
                continue
            }
            
            // Get window properties
            guard let windowID = windowDict[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = windowDict[kCGWindowOwnerName as String] as? String else {
                continue
            }
            
            // Skip system windows (layer != 0)
            let layer = windowDict[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 {
                continue
            }
            
            // Skip very small windows (likely UI elements)
            if let bounds = windowDict[kCGWindowBounds as String] as? [String: CGFloat] {
                let width = bounds["Width"] ?? 0
                let height = bounds["Height"] ?? 0
                if width < 100 || height < 100 {
                    continue
                }
            }
            
            // Get app icon
            let appIcon = appsByPID[ownerPID]?.icon
            
            // Create WindowInfo
            let windowInfo = WindowInfo(
                id: windowID,
                title: windowName,
                appName: ownerName,
                appPID: ownerPID,
                appBundleIdentifier: appsByPID[ownerPID]?.bundleIdentifier,
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
            app.activate()
        }
        
        // Then, raise the specific window using Accessibility API
        raiseWindow(window)
    }
    
    // MARK: - Private Methods
    
    private func raiseWindow(_ window: WindowInfo) {
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
                // Raise the window
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                
                // Also try to focus it
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                break
            }
        }
    }
}
