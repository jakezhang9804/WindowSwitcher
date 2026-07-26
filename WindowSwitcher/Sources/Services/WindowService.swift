import AppKit
import ApplicationServices
import AppSwitcherKit

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

    /// Minimum fraction of a window's own area that must lie on a screen for it
    /// to count as "shown" — the switcher only lists apps whose UI is actually
    /// displayed (>90% on-screen), excluding minimized, other-Space, or windows
    /// dragged mostly off the edge. Occlusion by other apps does NOT hide a
    /// window: the whole point of a switcher is to reach the apps behind.
    static let minVisibleFraction = 0.9

    /// Get all switchable windows: layer-0, on the current Space (not minimized
    /// / not on another Space), a real title, big enough, and ≥90% of the window
    /// on some screen. Returns front-to-back z-order (frontmost first).
    func getAllWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let appsByPID = Dictionary(
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentBundleID = Bundle.main.bundleIdentifier
        // Screen rects in CGWindow's top-left coordinate space
        let screenRects = NSScreen.screens.map { axRect(fromAppKit: $0.frame) }

        var visible: [WindowInfo] = []

        for windowDict in windowList {
            guard let layer = windowDict[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPID = windowDict[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = windowDict[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            let app = appsByPID[ownerPID]
            if app?.bundleIdentifier == currentBundleID { continue }

            let rect = CGRect(
                x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0
            )

            guard rect.width >= 50, rect.height >= 50,
                  let windowName = windowDict[kCGWindowName as String] as? String, !windowName.isEmpty,
                  let windowID = windowDict[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = windowDict[kCGWindowOwnerName as String] as? String,
                  screenRects.contains(where: { areaFraction(of: rect, within: $0) >= Self.minVisibleFraction }) else {
                continue
            }

            visible.append(WindowInfo(
                id: windowID,
                title: windowName,
                appName: ownerName,
                appPID: ownerPID,
                appBundleID: app?.bundleIdentifier,
                appIcon: app?.icon,
                appPath: app?.bundleURL?.path,
                windowCount: 1
            ))
        }

        // Fill in per-app window counts (used by the by-app grouping subtitle)
        var countByPID: [pid_t: Int] = [:]
        for w in visible { countByPID[w.appPID, default: 0] += 1 }
        for i in visible.indices { visible[i].windowCount = countByPID[visible[i].appPID] ?? 1 }

        return visible
    }

    /// Fraction of `rect`'s area that lies inside `container`.
    private func areaFraction(of rect: CGRect, within container: CGRect) -> Double {
        guard rect.width > 0, rect.height > 0 else { return 0 }
        let inter = rect.intersection(container)
        guard !inter.isNull else { return 0 }
        return (inter.width * inter.height) / (rect.width * rect.height)
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
            forceActivate(app, label: "\(window.appName) (raised=\(raised))")
        } else {
            NSLog("[WS] activateWindow: no NSRunningApplication for pid=\(window.appPID) (\(window.appName))")
        }
    }

    /// `NSRunningApplication.activate()` can return false (dropped) when invoked
    /// from an accessory app while the window server is mid-transition — retry
    /// once shortly after so an intermittent drop doesn't read as "didn't switch".
    private func forceActivate(_ app: NSRunningApplication, label: String) {
        if app.activate() {
            NSLog("[WS] activate \(label) ok")
            return
        }
        NSLog("[WS] activate \(label) returned false — retrying once")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            let ok = app.activate()
            NSLog("[WS] activate \(label) retry=\(ok)")
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

        if app.isHidden {
            app.unhide()
        }
        forceActivate(app, label: "\(bundleID) (hidden=\(app.isHidden))")

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

    // MARK: - App Groups

    /// Bundle IDs are case-insensitive on macOS — the app catalog and
    /// NSRunningApplication can report different casing, so never compare with `==`
    private func runningApp(forBundleID bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier?.caseInsensitiveCompare(bundleID) == .orderedSame
        }
    }

    /// The result of recording a screen: the apps found on it (front-to-back
    /// order, so the frontmost app is first and ends up focused on activation)
    /// and each app's window frame.
    struct ScreenRecording {
        let bundleIDs: [String]
        let frames: [String: AppGroupWindowFrame]
    }

    /// Record every app that currently has a window on the given screen, along
    /// with that window's frame. This is how a group is defined — the user
    /// arranges a screen, then records it; no manual app selection.
    ///
    /// CGWindow bounds and AX position share the same coordinate space
    /// (top-left origin, y downward, origin at the primary screen's top-left),
    /// so bounds are stored directly as restorable frames.
    ///
    /// The list is front-to-back, so the FIRST window seen per app is its
    /// frontmost one — recorded as the app's representative frame. Restore
    /// targets the app's main window, which is that same frontmost window, so
    /// record and restore stay consistent for the common single-window case.
    func recordScreen(screenIndex: Int) -> ScreenRecording {
        let screens = NSScreen.screens
        guard screens.indices.contains(screenIndex) else {
            return ScreenRecording(bundleIDs: [], frames: [:])
        }
        let screenRect = axRect(fromAppKit: screens[screenIndex].frame)

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return ScreenRecording(bundleIDs: [], frames: [:])
        }

        let appsByPID = Dictionary(
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentBundleID = Bundle.main.bundleIdentifier?.lowercased()

        var orderedBundleIDs: [String] = []
        var frames: [String: AppGroupWindowFrame] = [:]

        for dict in list {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let name = dict[kCGWindowName as String] as? String, !name.isEmpty,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  let bundleID = appsByPID[pid]?.bundleIdentifier,
                  bundleID.lowercased() != currentBundleID,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            let rect = CGRect(
                x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0
            )

            // Only apps with a large window that lives (>90% of its area) on the
            // target screen — the apps genuinely arranged on that screen.
            guard rect.width >= 50, rect.height >= 50,
                  areaFraction(of: rect, within: screenRect) >= Self.minVisibleFraction else {
                continue
            }

            // First (frontmost) window per app wins — matches restore's main window
            guard frames[bundleID] == nil else { continue }
            frames[bundleID] = AppGroupWindowFrame(
                x: Double(rect.minX), y: Double(rect.minY),
                width: Double(rect.width), height: Double(rect.height)
            )
            orderedBundleIDs.append(bundleID)
        }

        return ScreenRecording(bundleIDs: orderedBundleIDs, frames: frames)
    }

    /// Activate an app group: launch members that aren't running, re-open a
    /// window for members that are running but window-less, restore each
    /// member's saved frame (or move it to the bound screen when no layout was
    /// captured), bring them all to the front, and leave the FIRST member focused.
    func activateGroup(_ group: AppGroup) {
        let screens = NSScreen.screens
        let targetScreen = screens.indices.contains(group.screenIndex)
            ? screens[group.screenIndex]
            : (NSScreen.main ?? screens.first)
        guard let targetScreen else { return }

        NSLog("[WS][Group] Activating '\(group.name)' → screen \(group.screenIndex) (\(targetScreen.localizedName)), layout=\(group.hasCapturedLayout)")

        // The first member is the intended focus — only it should end up frontmost
        let focusBundleID = group.bundleIDs.first

        // Activate in reverse so the first member ends up frontmost
        for bundleID in group.bundleIDs.reversed() {
            let savedFrame = frameLookup(group.frames, bundleID: bundleID)
            let isFocus = bundleID.caseInsensitiveCompare(focusBundleID ?? "") == .orderedSame

            guard let app = runningApp(forBundleID: bundleID) else {
                // Not running → launch, then place its windows once they appear
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSLog("[WS][Group] Launching \(bundleID)")
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    placeWindowsAfterLaunch(bundleID: bundleID, savedFrame: savedFrame, to: targetScreen, focus: isFocus)
                } else {
                    NSLog("[WS][Group] Could not resolve app for \(bundleID)")
                }
                continue
            }

            app.unhide()

            if !hasVisibleWindow(pid: app.processIdentifier) {
                // Running but no visible window (all closed to the menu bar, or
                // only minimized ones) — re-open to recreate/restore a window,
                // then place it once it appears
                NSLog("[WS][Group] \(bundleID) running but no visible window — reopening")
                reopen(app)
                placeWindowsAfterLaunch(bundleID: bundleID, savedFrame: savedFrame, to: targetScreen, focus: isFocus)
            } else {
                placeAppWindows(pid: app.processIdentifier, savedFrame: savedFrame, to: targetScreen)
                app.activate()
            }
        }
    }

    /// Whether the app has at least one non-minimized window. `kAXWindowsAttribute`
    /// still lists minimized windows, so an app whose only window is minimized
    /// would otherwise look like it has a window when it has nothing visible.
    private func hasVisibleWindow(pid: pid_t) -> Bool {
        AccessibilityService.getWindows(for: pid).contains { window in
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               let minimized = minimizedRef as? Bool {
                return !minimized
            }
            return true // attribute missing → assume visible
        }
    }

    /// Trigger an app to recreate a window (the dock-icon-click behavior). For a
    /// running app, re-opening its bundle URL delivers a "reopen" event, which
    /// apps like Slack/Notion answer by showing a window again.
    private func reopen(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// A freshly launched or re-opened app creates its windows at an
    /// unpredictable time — poll (up to ~8s) and place them once they exist.
    /// Only the focus member re-activates on completion, so a late-launching
    /// non-focus member can't steal focus from the intended first member.
    private func placeWindowsAfterLaunch(
        bundleID: String,
        savedFrame: AppGroupWindowFrame?,
        to targetScreen: NSScreen,
        focus: Bool,
        attempt: Int = 0
    ) {
        guard attempt < 10 else {
            NSLog("[WS][Group] Gave up waiting for windows of \(bundleID)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }
            if let app = self.runningApp(forBundleID: bundleID),
               self.hasVisibleWindow(pid: app.processIdentifier) {
                NSLog("[WS][Group] Windows of \(bundleID) appeared (attempt \(attempt)) — placing")
                self.placeAppWindows(pid: app.processIdentifier, savedFrame: savedFrame, to: targetScreen)
                if focus { app.activate() }
            } else {
                self.placeWindowsAfterLaunch(bundleID: bundleID, savedFrame: savedFrame, to: targetScreen, focus: focus, attempt: attempt + 1)
            }
        }
    }

    /// Place an app's windows: restore the exact saved frame when one exists,
    /// otherwise move windows onto the bound screen (relative position preserved).
    private func placeAppWindows(pid: pid_t, savedFrame: AppGroupWindowFrame?, to targetScreen: NSScreen) {
        if let saved = savedFrame {
            restoreFrame(pid: pid, savedFrame: saved, boundScreen: targetScreen)
        } else {
            moveAppWindows(pid: pid, to: targetScreen)
        }
    }

    /// Restore the app's main window to a saved position and size. If the saved
    /// frame no longer fits any screen, clamp it onto the bound screen.
    private func restoreFrame(pid: pid_t, savedFrame: AppGroupWindowFrame, boundScreen: NSScreen) {
        guard let window = mainWindow(pid: pid) else { return }

        var origin = CGPoint(x: savedFrame.x, y: savedFrame.y)
        let size = CGSize(width: savedFrame.width, height: savedFrame.height)

        // If the saved origin isn't on any current screen, clamp onto the bound one
        if screenContaining(axPoint: CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)) == nil {
            let bound = axRect(fromAppKit: boundScreen.visibleFrame)
            origin.x = min(max(origin.x, bound.minX), max(bound.maxX - size.width, bound.minX))
            origin.y = min(max(origin.y, bound.minY), max(bound.maxY - size.height, bound.minY))
        }

        NSLog("[WS][Group] Restoring window (pid \(pid)) → \(Int(origin.x)),\(Int(origin.y)) \(Int(size.width))×\(Int(size.height))")
        // Set size before and after the move: some apps clamp size to the
        // current screen, so a second pass lands the intended dimensions
        setAXSize(window, size)
        setAXPosition(window, origin)
        setAXSize(window, size)
    }

    /// Move every standard window of the app to the target screen, preserving
    /// each window's relative position within its current screen.
    private func moveAppWindows(pid: pid_t, to targetScreen: NSScreen) {
        let windows = AccessibilityService.getWindows(for: pid)
        guard !windows.isEmpty else { return }

        let targetFrame = axRect(fromAppKit: targetScreen.visibleFrame)

        for window in windows {
            guard let frame = axFrame(of: window), frame.width > 1, frame.height > 1 else { continue }

            // Already on the target screen → leave it alone
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if targetFrame.contains(center) { continue }

            // Preserve the window's relative position within its current screen
            let sourceScreen = screenContaining(axPoint: center) ?? NSScreen.main ?? targetScreen
            let sourceFrame = axRect(fromAppKit: sourceScreen.visibleFrame)

            let relX = sourceFrame.width > 0 ? (frame.minX - sourceFrame.minX) / sourceFrame.width : 0
            let relY = sourceFrame.height > 0 ? (frame.minY - sourceFrame.minY) / sourceFrame.height : 0

            var newX = targetFrame.minX + relX * targetFrame.width
            var newY = targetFrame.minY + relY * targetFrame.height

            // Clamp so the window stays reachable on the target screen
            newX = min(max(newX, targetFrame.minX), max(targetFrame.maxX - frame.width, targetFrame.minX))
            newY = min(max(newY, targetFrame.minY), max(targetFrame.maxY - frame.height, targetFrame.minY))

            NSLog("[WS][Group] Moving window (pid \(pid)) \(Int(frame.minX)),\(Int(frame.minY)) → \(Int(newX)),\(Int(newY))")
            setAXPosition(window, CGPoint(x: newX, y: newY))
        }
    }

    /// Case-insensitive lookup into a group's saved-frame dictionary
    private func frameLookup(_ frames: [String: AppGroupWindowFrame], bundleID: String) -> AppGroupWindowFrame? {
        if let exact = frames[bundleID] { return exact }
        return frames.first { $0.key.caseInsensitiveCompare(bundleID) == .orderedSame }?.value
    }

    /// The app's main window (or its first window as a fallback)
    private func mainWindow(pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var mainRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainRef) == .success,
           let mainValue = mainRef, CFGetTypeID(mainValue) == AXUIElementGetTypeID() {
            return (mainValue as! AXUIElement)
        }
        return AccessibilityService.getWindows(for: pid).first
    }

    // MARK: - AX Geometry Helpers

    /// AX coordinates use a top-left origin (y grows downward, origin at the
    /// primary screen's top-left); AppKit uses bottom-left. Flip around the
    /// primary screen's top edge.
    private var primaryScreenMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    private func axRect(fromAppKit rect: NSRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func screenContaining(axPoint point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { axRect(fromAppKit: $0.frame).contains(point) }
    }

    /// Read a window's frame in AX (top-left origin) coordinates
    private func axFrame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, let sizeValue = sizeRef,
              CFGetTypeID(posValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        // swiftlint:enable force_cast
        return CGRect(origin: position, size: size)
    }

    private func setAXPosition(_ window: AXUIElement, _ point: CGPoint) {
        var position = point
        guard let value = AXValueCreate(.cgPoint, &position) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private func setAXSize(_ window: AXUIElement, _ size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }
}
