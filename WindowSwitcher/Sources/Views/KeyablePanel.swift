import AppKit

/// A custom NSPanel subclass that ensures it can become the key window,
/// allowing it to receive keyboard events even in non-activating mode.
///
/// This is the same approach used by TabTab. Without this, NSPanel with
/// `.nonactivatingPanel` style mask returns `false` for `canBecomeKey`,
/// which prevents NSEvent local monitors from receiving keyboard events
/// when the panel is displayed.
final class KeyablePanel: NSPanel {

    /// Called when the panel loses key window status (user clicked elsewhere)
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
