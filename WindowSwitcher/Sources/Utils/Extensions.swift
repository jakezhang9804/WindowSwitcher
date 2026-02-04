import SwiftUI
import AppKit

// MARK: - View Extensions

extension View {
    /// Apply a modifier conditionally
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Hide the view conditionally
    @ViewBuilder
    func hidden(_ isHidden: Bool) -> some View {
        if isHidden {
            self.hidden()
        } else {
            self
        }
    }
}

// MARK: - NSImage Extensions

extension NSImage {
    /// Resize image to specified size
    func resized(to newSize: NSSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        self.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1.0
        )
        
        newImage.unlockFocus()
        return newImage
    }
}

// MARK: - String Extensions

extension String {
    /// Check if string contains another string (case insensitive)
    func containsIgnoringCase(_ other: String) -> Bool {
        self.lowercased().contains(other.lowercased())
    }
    
    /// Truncate string to specified length with ellipsis
    func truncated(to length: Int) -> String {
        if self.count <= length {
            return self
        }
        return String(self.prefix(length)) + "..."
    }
}

// MARK: - Color Extensions

extension Color {
    /// System accent color
    static var systemAccent: Color {
        Color(NSColor.controlAccentColor)
    }
    
    /// Selection background color
    static var selectionBackground: Color {
        Color(NSColor.selectedContentBackgroundColor)
    }
}

// MARK: - Keyboard Shortcut Helpers

extension KeyEquivalent {
    static let upArrow = KeyEquivalent(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    static let downArrow = KeyEquivalent(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
}
