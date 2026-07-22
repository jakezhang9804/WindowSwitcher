import SwiftUI
import AppKit
import AppSwitcherKit

/// Panel layout style
enum SwitcherLayout {
    /// Vertical list panel (used for the left/right edge positions)
    case list
    /// Horizontal icon strip in the center of the screen, mirroring the
    /// native macOS Cmd+Tab app switcher
    case strip
}

/// Main switcher panel view.
///
/// Interaction flow:
/// 1. Panel opens with the hotkey, second item pre-selected (last used window)
/// 2. Search bar is visible at the top but **inactive** by default (placeholder only)
/// 3. While holding the modifier, each Tab press cycles to the next window
/// 4. Releasing the modifier confirms the selection and switches to that window
/// 5. Number keys 1-9 jump to the Nth item and confirm (when search is inactive)
/// 6. Enter activates the search bar (when search is inactive) or confirms selection (when search is active)
/// 7. Escape deactivates search (if active) or dismisses the panel
struct SwitcherWindow: View {
    @ObservedObject var viewModel: SwitcherViewModel
    var layout: SwitcherLayout = .list
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void
    let onItemCountChange: (Int) -> Void

    @FocusState private var isTextFieldFocused: Bool

    /// Mouse position when the panel appeared. Hover-selection stays disabled until
    /// the mouse actually moves — the panel often opens under a stationary cursor,
    /// which would otherwise silently override the default "previous window" selection.
    @State private var initialMouseLocation: CGPoint = NSEvent.mouseLocation
    @State private var mouseHasMoved = false

    init(
        viewModel: SwitcherViewModel,
        layout: SwitcherLayout = .list,
        onDismiss: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onItemCountChange: @escaping (Int) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.layout = layout
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
        self.onItemCountChange = onItemCountChange
    }

    // Semantic system colors — they adapt to the panel appearance automatically
    // and render with vibrancy inside the NSVisualEffectView, matching the
    // label hierarchy Apple's own HUD panels use.

    /// Secondary text color
    private var secondaryText: Color {
        .secondary
    }

    /// Tertiary / muted text color
    private var tertiaryText: Color {
        Color(nsColor: .tertiaryLabelColor)
    }

    /// Very subtle text color (for branding, hints)
    private var subtleText: Color {
        Color(nsColor: .quaternaryLabelColor)
    }

    /// Neutral fill for the search bar, badges, and icon placeholders
    private var fillBg: Color {
        Color.primary.opacity(0.08)
    }

    var body: some View {
        Group {
            switch layout {
            case .list: listBody
            case .strip: stripBody
            }
        }
        // Handle Tab and Arrow keys via SwiftUI for key repeat support
        .onKeyPress(.tab) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.selectNext()
            return .handled
        }
        // Let the panel resize to match the filtered result count
        .onChange(of: viewModel.displayItems.count) { _, newCount in
            onItemCountChange(newCount)
        }
        // Watch for isSearchActive changes from ViewModel to focus TextField
        .onChange(of: viewModel.isSearchActive) { _, isActive in
            if isActive {
                // Focus the TextField after a brief delay to let SwiftUI render it
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isTextFieldFocused = true
                }
            } else {
                isTextFieldFocused = false
            }
            // The strip panel grows when the search bar appears
            onItemCountChange(viewModel.displayItems.count)
        }
    }

    // MARK: - List Layout (left/right edge panel)

    private var listBody: some View {
        VStack(spacing: 0) {
            // Search bar — always visible at top
            searchBar

            // Results list or empty state
            let items = viewModel.displayItems
            if items.isEmpty {
                emptyState
            } else {
                SwitcherResultsList(
                    items: items,
                    selectedIndex: $viewModel.selectedIndex,
                    searchText: viewModel.searchText,
                    onSelect: { item in
                        activateItem(item)
                    },
                    onHover: { index in
                        hoverSelect(index)
                    }
                )
            }

            // Bottom bar
            bottomBar
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Strip Layout (native Cmd+Tab style, centered)

    private var stripBody: some View {
        VStack(spacing: 6) {
            if viewModel.isSearchActive {
                searchBar
            }

            let items = viewModel.displayItems
            if items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                stripIcon(item: item, isSelected: index == viewModel.selectedIndex, index: index)
                                    .id(index)
                                    .onTapGesture { activateItem(item) }
                                    .onHover { isHovered in
                                        if isHovered { hoverSelect(index) }
                                    }
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    .onChange(of: viewModel.selectedIndex) { _, newValue in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }

                // Selected item caption — needed because multiple windows of
                // the same app share an icon (unlike the app-level native switcher)
                Text(selectedCaption)
                    .font(.system(size: 12))
                    .foregroundColor(secondaryText)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(height: 16)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private func stripIcon(item: SwitcherItem, isSelected: Bool, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.primary.opacity(0.18) : Color.clear)

                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(fillBg)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "app")
                                .font(.system(size: 26))
                                .foregroundColor(tertiaryText)
                        )
                }
            }

            // Quick-select number badge (keys 1-9)
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .primary : tertiaryText)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle().fill(isSelected ? Color.primary.opacity(0.2) : fillBg)
                    )
                    .padding(4)
            }
        }
        .frame(width: 76, height: 76)
        .contentShape(Rectangle())
    }

    private var selectedCaption: String {
        guard let item = viewModel.selectedItem else { return " " }
        if let subtitle = item.subtitle, !subtitle.isEmpty, subtitle != item.displayName {
            return "\(item.displayName) — \(subtitle)"
        }
        return item.displayName
    }

    /// Shared hover-selection with the stationary-cursor guard
    private func hoverSelect(_ index: Int) {
        if !mouseHasMoved {
            let location = NSEvent.mouseLocation
            guard abs(location.x - initialMouseLocation.x) > 2
                    || abs(location.y - initialMouseLocation.y) > 2 else { return }
            mouseHasMoved = true
        }
        viewModel.selectedIndex = index
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(secondaryText)

            if viewModel.isSearchActive {
                // Active mode: show real TextField
                ZStack(alignment: .leading) {
                    if viewModel.searchText.isEmpty {
                        Text(L10n.searchPlaceholder)
                            .font(.system(size: 13))
                            .foregroundColor(tertiaryText)
                    }

                    TextField("", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .focused($isTextFieldFocused)
                }

                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            } else {
                // Inactive mode: show placeholder text only (no TextField)
                Text(L10n.searchInactivePlaceholder)
                    .font(.system(size: 13))
                    .foregroundColor(tertiaryText)

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(fillBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !viewModel.isSearchActive {
                viewModel.isSearchActive = true
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.searchText.isEmpty ? "rectangle.stack" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(tertiaryText)

            Text(viewModel.searchText.isEmpty ? L10n.noWindows : L10n.noResults)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(secondaryText)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 80)
        .padding(.vertical, 30)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        ZStack {
            // Center: Powered by Manus (absolutely centered)
            HStack(spacing: 3) {
                Text(L10n.isChinese ? "基于" : "Powered by")
                    .font(.system(size: 10))
                    .foregroundStyle(subtleText)
                Text("Manus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tertiaryText)
            }

            // Left & Right overlay
            HStack {
                // Left: window count (number only)
                let items = viewModel.displayItems
                if !items.isEmpty {
                    Text("\(viewModel.totalCount)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(tertiaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(fillBg)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                // Right: settings button
                Button(action: { onOpenSettings() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Actions

    private func activateItem(_ item: SwitcherItem) {
        viewModel.activate(item)
        onDismiss()
    }
}

// MARK: - Switcher Results List (supports mixed SwitcherItem)

struct SwitcherResultsList: View {
    let items: [SwitcherItem]
    @Binding var selectedIndex: Int
    let searchText: String
    let onSelect: (SwitcherItem) -> Void
    let onHover: ((Int) -> Void)?

    /// Selection uses the user's accent color with white content, the same
    /// treatment as Spotlight results and native menu highlights.
    private var selectedBg: Color {
        Color(nsColor: .controlAccentColor)
    }
    private var tertiaryText: Color {
        Color(nsColor: .tertiaryLabelColor)
    }
    private var fillBg: Color {
        Color.primary.opacity(0.08)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        resultItem(item: item, isSelected: index == selectedIndex, index: index)
                            .id(index)
                            .onTapGesture { onSelect(item) }
                            .onHover { isHovered in
                                if isHovered { onHover?(index) }
                            }
                    }
                }
                .padding(.horizontal, 6)
            }
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func resultItem(item: SwitcherItem, isSelected: Bool, index: Int) -> some View {
        HStack(spacing: 10) {
            // App icon
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.white.opacity(0.2) : fillBg)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "app")
                            .font(.system(size: 14))
                            .foregroundColor(isSelected ? .white : tertiaryText)
                    )
            }

            // Text area
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.75) : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Badge: keyboard shortcut number for first 9 items
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(isSelected ? .white : tertiaryText)
                    .frame(width: 20, height: 20)
                    .background(isSelected ? Color.white.opacity(0.2) : fillBg)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? selectedBg : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
