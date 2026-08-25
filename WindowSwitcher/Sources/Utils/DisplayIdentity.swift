import AppKit
import CoreGraphics

extension NSScreen {
    /// A stable CoreGraphics display UUID suitable for persistence across screen
    /// array reordering and most disconnect/reconnect cycles.
    var persistentDisplayID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func screen(withPersistentDisplayID displayID: String?) -> NSScreen? {
        guard let displayID, !displayID.isEmpty else { return nil }
        return screens.first { $0.persistentDisplayID == displayID }
    }
}
