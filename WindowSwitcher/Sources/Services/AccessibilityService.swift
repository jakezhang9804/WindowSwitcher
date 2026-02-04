import AppKit
import ApplicationServices

class AccessibilityService {
    
    // MARK: - Permission Check
    
    /// Check if accessibility permission is granted
    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }
    
    /// Request accessibility permission with prompt
    static func requestAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Window Operations
    
    /// Get all windows for a specific application
    static func getWindows(for pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            return []
        }
        
        return windows
    }
    
    /// Get the title of an AXUIElement window
    static func getWindowTitle(_ window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        
        guard result == .success else {
            return nil
        }
        
        return titleRef as? String
    }
    
    /// Raise a window to the front
    static func raiseWindow(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
    
    /// Focus a window
    static func focusWindow(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFTypeRef)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, true as CFTypeRef)
    }
    
    /// Get window position
    static func getWindowPosition(_ window: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
        
        guard result == .success else {
            return nil
        }
        
        var point = CGPoint.zero
        if AXValueGetValue(positionRef as! AXValue, .cgPoint, &point) {
            return point
        }
        
        return nil
    }
    
    /// Get window size
    static func getWindowSize(_ window: AXUIElement) -> CGSize? {
        var sizeRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        
        guard result == .success else {
            return nil
        }
        
        var size = CGSize.zero
        if AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) {
            return size
        }
        
        return nil
    }
}
