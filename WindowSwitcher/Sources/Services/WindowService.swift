import AppKit
import ApplicationServices

/// Private-but-stable AX API that maps an AXUIElement to its CGWindowID,
/// letting us raise the exact window instead of guessing by title
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

final class WindowService {

    /// Get all visible windows, optionally filtered by allowed bundle IDs.
    /// When `allowedBundleIDs` is empty, all windows are returned (no filter).
    func getAllWindows(allowedBundleIDs: Set<String> = []) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let runningApps = NSWorkspace.shared.runningApplications
        // processIdentifier can be -1 for apps without a PID, so keys may collide
        let appsByPID = Dictionary(
            runningApps.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

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

            let app = appsByPID[ownerPID]

            // Skip our own windows
            if let bundleID = app?.bundleIdentifier, bundleID == currentBundleID {
                continue
            }

            // Filter by allowed bundle IDs (when set is non-empty)
            if !allowedBundleIDs.isEmpty {
                guard let bundleID = app?.bundleIdentifier,
                      allowedBundleIDs.contains(bundleID) else {
                    continue
                }
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

            let appIcon = app?.icon
            let appPath = app?.bundleURL?.path
            let count = windowCountByPID[ownerPID] ?? 1
            let bundleIdentifier = app?.bundleIdentifier

            let windowInfo = WindowInfo(
                id: windowID,
                title: windowName,
                appName: ownerName,
                appPID: ownerPID,
                appBundleID: bundleIdentifier,
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
            let activated = app.activate()
            NSLog("[WS] activateWindow: \(window.appName) pid=\(window.appPID) activate=\(activated) policy=\(app.activationPolicy.rawValue)")
        } else {
            NSLog("[WS] activateWindow: no NSRunningApplication for pid=\(window.appPID) (\(window.appName))")
        }
        raiseWindow(window)
    }

    /// Activate the frontmost window of an app by bundle ID
    func activateApp(bundleID: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        }) else {
            // App is not running; try to launch it
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            return
        }

        let activated = app.activate()
        NSLog("[WS] activateApp: \(bundleID) pid=\(app.processIdentifier) activate=\(activated) hidden=\(app.isHidden)")

        if app.isHidden {
            app.unhide()
        }

        // activate() alone never restores a minimized window — the app becomes
        // active but nothing appears on screen, which reads as a failed switch
        restoreMinimizedWindowIfNeeded(pid: app.processIdentifier)
    }

    /// If the app has windows but none are visible (all minimized), restore
    /// and raise the first minimized one via the Accessibility API
    private func restoreMinimizedWindowIfNeeded(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            return
        }

        var anyVisible = false
        var firstMinimized: AXUIElement?
        for axWindow in windows {
            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef)
            if (minimizedRef as? Bool) == true {
                if firstMinimized == nil { firstMinimized = axWindow }
            } else {
                anyVisible = true
            }
        }

        if !anyVisible, let axWindow = firstMinimized {
            NSLog("[WS] activateApp: all windows minimized (pid=\(pid)) — restoring one")
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            raise(axWindow)
        }
    }

    private func raiseWindow(_ window: WindowInfo) {
        let appElement = AXUIElementCreateApplication(window.appPID)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            NSLog("[WS] raiseWindow: AXWindows unavailable for \(window.appName) (AXError=\(result.rawValue))")
            return
        }

        // Prefer an exact CGWindowID match; fall back to the first title match
        // (windows sharing a title would otherwise be indistinguishable)
        var titleMatch: AXUIElement?
        for axWindow in windows {
            var windowID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &windowID) == .success, windowID == window.id {
                raise(axWindow)
                return
            }

            if titleMatch == nil {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                if let title = titleRef as? String, title == window.title {
                    titleMatch = axWindow
                }
            }
        }

        if let axWindow = titleMatch {
            raise(axWindow)
        } else {
            NSLog("[WS] raiseWindow: no AX match among \(windows.count) windows for id=\(window.id) title=\(window.title)")
        }
    }

    private func raise(_ axWindow: AXUIElement) {
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, true as CFTypeRef)
    }
}
