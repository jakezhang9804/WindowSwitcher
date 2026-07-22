import AppKit
import ApplicationServices

/// Private-but-stable AX API that maps an AXUIElement to its CGWindowID,
/// letting us raise the exact window instead of guessing by title
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

/// Private SkyLight API (used by AltTab & co.): asks the WindowServer to
/// bring a specific window of a process to front — including switching to
/// the Space the window lives on, which no public API can do
@_silgen_name("_SLPSSetFrontProcessWithOptions")
private func _SLPSSetFrontProcessWithOptions(
    _ psn: inout ProcessSerialNumber, _ windowID: CGWindowID, _ mode: UInt32
) -> CGError

/// Private SkyLight API: posts a window-server event record to a process,
/// used to make the target window the key window after fronting it
@_silgen_name("SLPSPostEventRecordTo")
private func SLPSPostEventRecordTo(_ psn: inout ProcessSerialNumber, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

/// Carbon API mapping a pid to its ProcessSerialNumber (deprecated but present)
@_silgen_name("GetProcessForPID")
private func GetProcessForPID(_ pid: pid_t, _ psn: inout ProcessSerialNumber) -> OSStatus

/// kCPSUserGenerated — treat the fronting as user-initiated
private let kSLPSUserGenerated: UInt32 = 0x200

final class WindowService {

    /// Get all switchable windows, optionally filtered by allowed bundle IDs.
    /// When `allowedBundleIDs` is empty, all windows are returned (no filter).
    /// Includes windows on other Spaces and minimized ones (.optionAll) —
    /// .optionOnScreenOnly only sees the current Space, which made windows
    /// living on other desktops unreachable. Current-Space windows keep their
    /// z-order at the front; off-Space/minimized ones follow.
    func getAllWindows(allowedBundleIDs: Set<String> = []) -> [WindowInfo] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
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

        var onScreenResult: [WindowInfo] = []
        var offScreenResult: [WindowInfo] = []

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

            let isOnScreen = (windowDict[kCGWindowIsOnscreen as String] as? Bool) ?? false
            if isOnScreen {
                onScreenResult.append(windowInfo)
            } else {
                offScreenResult.append(windowInfo)
            }
        }

        return onScreenResult + offScreenResult
    }

    /// Activate a specific window. AX raise handles current-Space and
    /// minimized windows; windows on other Spaces are invisible to AX, so
    /// those are fronted via the WindowServer (SkyLight), which also switches
    /// to the target Space.
    func activateWindow(_ window: WindowInfo) {
        let raised = raiseWindow(window)

        if !raised {
            NSLog("[WS] activateWindow: AX raise unavailable — fronting via WindowServer (space switch)")
            frontWindowViaWindowServer(window)
            // Once the Space switch lands the window becomes AX-visible;
            // raise again so it also becomes the app's main window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                _ = self?.raiseWindow(window)
            }
        }

        if let app = NSRunningApplication(processIdentifier: window.appPID) {
            let activated = app.activate()
            NSLog("[WS] activateWindow: \(window.appName) pid=\(window.appPID) activate=\(activated) raised=\(raised)")
        } else {
            NSLog("[WS] activateWindow: no NSRunningApplication for pid=\(window.appPID) (\(window.appName))")
        }
    }

    /// Front a specific window through the WindowServer — the AltTab
    /// technique that works across Spaces where AX cannot see the window
    private func frontWindowViaWindowServer(_ window: WindowInfo) {
        var psn = ProcessSerialNumber()
        guard GetProcessForPID(window.appPID, &psn) == noErr else {
            NSLog("[WS] frontWindowViaWindowServer: no PSN for pid=\(window.appPID)")
            return
        }

        _ = _SLPSSetFrontProcessWithOptions(&psn, window.id, kSLPSUserGenerated)

        // Make the target window the key window: post synthetic window-server
        // activate records (byte layout as used by AltTab/yabai)
        var windowID = window.id
        for eventKind: UInt8 in [0x01, 0x02] {
            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x08] = eventKind
            bytes[0x3a] = 0x10
            memset(&bytes[0x20], 0xff, 0x10)
            withUnsafeBytes(of: &windowID) { widBytes in
                for (offset, byte) in widBytes.enumerated() {
                    bytes[0x3c + offset] = byte
                }
            }
            bytes.withUnsafeMutableBufferPointer { buffer in
                _ = SLPSPostEventRecordTo(&psn, buffer.baseAddress!)
            }
        }
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

    /// Raise the window via AX. Returns false when AX cannot see the window
    /// (typical for windows on another Space).
    @discardableResult
    private func raiseWindow(_ window: WindowInfo) -> Bool {
        let appElement = AXUIElementCreateApplication(window.appPID)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success,
              let windows = windowsRef as? [AXUIElement] else {
            NSLog("[WS] raiseWindow: AXWindows unavailable for \(window.appName) (AXError=\(result.rawValue))")
            return false
        }

        // Prefer an exact CGWindowID match; fall back to the first title match
        // (windows sharing a title would otherwise be indistinguishable)
        var titleMatch: AXUIElement?
        for axWindow in windows {
            var windowID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &windowID) == .success, windowID == window.id {
                raise(axWindow)
                return true
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
            return true
        }

        NSLog("[WS] raiseWindow: no AX match among \(windows.count) windows for id=\(window.id) title=\(window.title)")
        return false
    }

    private func raise(_ axWindow: AXUIElement) {
        // Restore first if minimized — raise has no effect on a minimized window
        var minimizedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef)
        if (minimizedRef as? Bool) == true {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        }

        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, true as CFTypeRef)
    }
}
