import SwiftUI
import AppKit
import AppSwitcherKit

/// Main switcher panel view.
///
/// Interaction flow:
/// 1. Panel opens with Option+Tab, second item pre-selected (last used window)
/// 2. Search bar is visible at the top but **inactive** by default (placeholder only)
/// 3. While holding Option, each Tab press cycles to the next window
/// 4. Releasing Option confirms the selection and switches to that window
/// 5. Number keys 1-9 jump to the Nth item and confirm (when search is inactive)
/// 6. Enter activates the search bar (when search is inactive) or confirms selection (when search is active)
/// 7. Escape deactivates search (if active) or dismisses the panel
struct SwitcherWindow: View {
    @ObservedObject var viewModel: SwitcherViewModel
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(
        viewModel: SwitcherViewModel,
        onDismiss: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
    }

    /// Adaptive foreground color that works in both light and dark modes
    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    /// Secondary text color
    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.45)
    }

    /// Tertiary / muted text color
    private var tertiaryText: Color {
        colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3)
    }

    /// Very subtle text color (for branding, hints)
    private var subtleText: Color {
        colorScheme == .dark ? .white.opacity(0.25) : .black.opacity(0.2)
    }

    /// Search bar background
    private var searchBarBg: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    /// Selected item background
    private var selectedBg: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
    }

    /// Badge background
    private var badgeBg: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    /// Placeholder icon background
    private var placeholderBg: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    var body: some View {
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
                    colorScheme: colorScheme,
                    onSelect: { item in
                        activateItem(item)
                    },
                    onHover: { index in
                        viewModel.selectedIndex = index
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
        }
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
                        .foregroundColor(primaryText)
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
        .background(searchBarBg)
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
                        .background(badgeBg)
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
        switch item {
        case .window(let window):
            viewModel.activateWindow(window)
        case .app(let bundleID, _, _, _):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        }
        onDismiss()
    }
}

// MARK: - Switcher Results List (supports mixed SwitcherItem)

struct SwitcherResultsList: View {
    let items: [SwitcherItem]
    @Binding var selectedIndex: Int
    let searchText: String
    let colorScheme: ColorScheme
    let onSelect: (SwitcherItem) -> Void
    let onHover: ((Int) -> Void)?

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }
    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.45)
    }
    private var tertiaryText: Color {
        colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3)
    }
    private var selectedBg: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
    }
    private var badgeBg: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    private var placeholderBg: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
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
                    .fill(placeholderBg)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "app")
                            .font(.system(size: 14))
                            .foregroundColor(tertiaryText)
                    )
            }

            // Text area
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(primaryText)
                    .lineLimit(1)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Badge: keyboard shortcut number for first 9 items
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(tertiaryText)
                    .frame(width: 20, height: 20)
                    .background(badgeBg)
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
