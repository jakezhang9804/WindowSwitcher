import SwiftUI

struct ResultItem: View {
    let window: WindowInfo
    let isSelected: Bool
    let index: Int
    let showShortcut: Bool
    
    @State private var isHovered: Bool = false
    
    init(window: WindowInfo, isSelected: Bool, index: Int, showShortcut: Bool = true) {
        self.window = window
        self.isSelected = isSelected
        self.index = index
        self.showShortcut = showShortcut
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // App Icon
            appIconView
            
            // Text Content
            VStack(alignment: .leading, spacing: 3) {
                // Primary Title (Window Title)
                Text(window.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Secondary Info (App Name)
                Text(window.appName)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer(minLength: 8)
            
            // Shortcut Hint (for first 9 items)
            if showShortcut && index < 9 {
                shortcutBadge
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundView)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var appIconView: some View {
        if let icon = window.appIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
                .frame(width: 36, height: 36)
        }
    }
    
    private var shortcutBadge: some View {
        Text("⌘\(index + 1)")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.06))
            )
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        } else {
            Color.clear
        }
    }
}

#Preview {
    VStack(spacing: 4) {
        ResultItem(
            window: WindowInfo(
                id: 1,
                title: "SwitcherWindow.swift - WindowSwitcher",
                appName: "Xcode",
                appPID: 123,
                appIcon: nil
            ),
            isSelected: true,
            index: 0
        )
        ResultItem(
            window: WindowInfo(
                id: 2,
                title: "Google Chrome",
                appName: "Chrome",
                appPID: 456,
                appIcon: nil
            ),
            isSelected: false,
            index: 1
        )
    }
    .padding()
    .frame(width: 500)
    .background(Color.gray.opacity(0.1))
}
