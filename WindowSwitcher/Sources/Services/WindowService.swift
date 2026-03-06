import AppKit
import ApplicationServices

final class WindowService {
    
    /// Get all visible windows across all applications
    func getAllWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        let runningApps = NSWorkspace.shared.runningApplications
        let appsByPID = Dictionary(uniqueKeysWithValues: runningApps.compactMap { app -> (pid_t, NSRunningApplication)? in
            (app.processIdentifier, app)
        })
        
        let currentBundleID = Bundle.main.bundleIdentifier
        
        // Count windows per app for windowCount field
        var windowCountByPID: [pid_t: Int] = [:]
        for windowDict in windowList {
            guard let ownerPID = windowDict[kCGWindowOwnerPID as String] as? pid_t,
                  let windowName = windowDict[kCGWindowName as String] as? String,
                  !windowName.isEmpty,
                  let layer = windowDict[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            windowCountByPID[ownerPID, default: 0] += 1
        }
        
        var result: [WindowInfo] = []
        
        for windowDict in windowList {
            guard let ownerPID = windowDict[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }
            
            // Skip our own windows
            if let app = appsByPID[ownerPID],
               app.bundleIdentifier == currentBundleID {
                continue
            }
            
            guard let windowName = windowDict[kCGWindowName as String] as? String,
                  !windowName.isEmpty else {
                continue
            }
            
            guard let windowID = windowDict[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = windowDict[kCGWindowOwnerName as String] as? String else {
                continue
            }
            
            // Skip system windows (layer != 0)
            let layer = windowDict[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 { continue }
            
            // Skip very small windows
            if let bounds = windowDict[kCGWindowBounds as String] as? [String: CGFloat] {
                let width = bounds["Width"] ?? 0
                let height = bounds["Height"] ?? 0
                if width < 50 || height < 50 { continue }
            }
            
            let app = appsByPID[ownerPID]
            let appIcon = app?.icon
            let appPath = app?.bundleURL?.path
            let count = windowCountByPID[ownerPID] ?? 1
            
            let windowInfo = WindowInfo(
                id: windowID,
                title: windowName,
                appName: ownerName,
                appPID: ownerPID,
                appIcon: appIcon,
                appPath: appPath,
                windowCount: count
            )
            
            result.append(windowInfo)
        }
        
        return result
    }
    
    /// Activate a specific window
    func activateWindow(_ window: WindowInfo) {
        if let app = NSRunningApplication(processIdentifier: window.appPID) {
            app.activate()
        }
        raiseWindow(window)
    }
    
    private func raiseWindow(_ window: WindowInfo) {
        let appElement = AXUIElementCreateApplication(window.appPID)
        
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return
        }
        
        for axWindow in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            
            if let title = titleRef as? String, title == window.title {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                break
            }
        }
    }
}
