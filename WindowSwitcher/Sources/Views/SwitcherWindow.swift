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
/// Interaction:
/// - Hold the modifier, Tab cycles the top-level list (apps in by-app mode).
/// - Releasing the modifier confirms; number keys 1-9 jump + confirm.
/// - In by-app grouping, → drills into the selected app's windows (a secondary
///   detail panel, TabTab-style); ← / Esc backs out; ↑/↓ move within it.
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
    // and render with vibrancy inside the NSVisualEffectView.

    private var secondaryText: Color { .secondary }
    private var tertiaryText: Color { Color(nsColor: .tertiaryLabelColor) }
    private var subtleText: Color { Color(nsColor: .quaternaryLabelColor) }
    private var fillBg: Color { Color.primary.opacity(0.08) }

    // MARK: - List sizing

    /// The vertical list shows at most this many rows; beyond it it scrolls.
    /// Keep in sync with `AppDelegate.calculatePanelHeight`.
    static let listMaxVisibleRows = 9
    /// Row content (28pt icon) + vertical padding 7×2
    static let listRowHeight: CGFloat = 42
    static let listRowSpacing: CGFloat = 2

    /// Height of a results list capped at `listMaxVisibleRows`.
    static func listHeight(for count: Int) -> CGFloat {
        let n = min(count, listMaxVisibleRows)
        guard n > 0 else { return 0 }
        return CGFloat(n) * listRowHeight + CGFloat(n - 1) * listRowSpacing
    }

    /// Windows of the drilled-into app, as switcher items
    private var secondaryItems: [SwitcherItem] {
        viewModel.expandedWindows.map { .window($0) }
    }

    var body: some View {
        Group {
            if viewModel.secondaryActive {
                secondaryBody
            } else {
                switch layout {
                case .list: listBody
                case .strip: stripBody
                }
            }
        }
        // Tab cycles the top-level list (with key-repeat)
        .onKeyPress(.tab) {
            viewModel.selectNext()
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.moveUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.moveDown()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.enterSecondary()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            viewModel.exitSecondary()
            return .handled
        }
        // Resize when the displayed count changes (top-level, search, or drill-in)
        .onChange(of: viewModel.displayItems.count) { _, _ in
            onItemCountChange(viewModel.displayedItems.count)
        }
        .onChange(of: viewModel.secondaryActive) { _, _ in
            onItemCountChange(viewModel.displayedItems.count)
        }
        .onChange(of: viewModel.isSearchActive) { _, isActive in
            if isActive {
                // Activate the app so the input method (IME / 中英文) engages —
                // a non-activating key panel alone can't route IME.
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isTextFieldFocused = true
                }
            } else {
                isTextFieldFocused = false
            }
            onItemCountChange(viewModel.displayedItems.count)
        }
    }

    // MARK: - List Layout (left/right edge panel)

    private var listBody: some View {
        VStack(spacing: 0) {
            searchBar

            let items = viewModel.displayItems
            if items.isEmpty {
                emptyState
            } else {
                SwitcherResultsList(
                    items: items,
                    selectedIndex: $viewModel.selectedIndex,
                    onSelect: { activateItem($0) },
                    onHover: { hoverSelect($0) }
                )
                // Cap at 9 rows; extra rows scroll inside this frame.
                .frame(height: Self.listHeight(for: items.count))
            }

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
                                    .onHover { if $0 { hoverSelect(index) } }
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

                // Selected item caption + drill-in hint
                HStack(spacing: 6) {
                    Text(selectedCaption)
                        .font(.system(size: 12))
                        .foregroundColor(secondaryText)
                        .lineLimit(1)
                    if viewModel.expandedWindows.count >= 2 {
                        Label(L10n.drillHint, systemImage: "arrow.right")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(tertiaryText)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 16)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - Secondary (per-app windows) drill-down

    private var secondaryBody: some View {
        VStack(spacing: 0) {
            // Back header: ‹ App name · N windows
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(secondaryText)
                Text(viewModel.selectedItem?.displayName ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(L10n.windowCountText(secondaryItems.count))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(tertiaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .contentShape(Rectangle())
            .onTapGesture { viewModel.exitSecondary() }

            SwitcherResultsList(
                items: secondaryItems,
                selectedIndex: $viewModel.secondaryIndex,
                onSelect: { item in
                    if case .window(let w) = item { activateWindow(w) }
                },
                onHover: { viewModel.secondaryIndex = $0 }
            )
            .frame(height: Self.listHeight(for: secondaryItems.count))
        }
        .padding(.vertical, 6)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func stripIcon(item: SwitcherItem, isSelected: Bool, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.primary.opacity(0.18) : Color.clear)

                if let groupIcons = item.groupIcons {
                    GroupStackIcon(icons: groupIcons, size: 60)
                } else if let icon = item.icon {
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

                // Multi-window apps show a small stacked-count pill
                if item.windows.count >= 2 {
                    Text("\(item.windows.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(fillBg))
                        .offset(y: 2)
                }
            }

            // Quick-select number badge (keys 1-9)
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .primary : tertiaryText)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(isSelected ? Color.primary.opacity(0.2) : fillBg))
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
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            } else {
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
            if !viewModel.isSearchActive { viewModel.isSearchActive = true }
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
            HStack(spacing: 3) {
                Text(L10n.isChinese ? "基于" : "Powered by")
                    .font(.system(size: 10))
                    .foregroundStyle(subtleText)
                Text("Manus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tertiaryText)
            }

            HStack {
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

    private func activateWindow(_ window: WindowInfo) {
        viewModel.activate(window: window)
        onDismiss()
    }
}

// MARK: - Switcher Results List (supports mixed SwitcherItem)

struct SwitcherResultsList: View {
    let items: [SwitcherItem]
    @Binding var selectedIndex: Int
    let onSelect: (SwitcherItem) -> Void
    let onHover: ((Int) -> Void)?

    private var selectedBg: Color { Color(nsColor: .controlAccentColor) }
    private var tertiaryText: Color { Color(nsColor: .tertiaryLabelColor) }
    private var fillBg: Color { Color.primary.opacity(0.08) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        resultItem(item: item, isSelected: index == selectedIndex, index: index)
                            .id(index)
                            .onTapGesture { onSelect(item) }
                            .onHover { if $0 { onHover?(index) } }
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
            if let groupIcons = item.groupIcons {
                GroupStackIcon(icons: groupIcons, size: 28)
            } else if let icon = item.icon {
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

            // Drill-in chevron for multi-window apps
            if item.windows.count >= 2 {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : tertiaryText)
            }

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

// MARK: - Group Stack Icon

/// Composite icon for an app group: member icons overlapping diagonally on a
/// screen-shaped backdrop — "the apps as they sit on the screen".
struct GroupStackIcon: View {
    let icons: [NSImage]
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var backdrop: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    private var border: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.15)
    }

    var body: some View {
        let shown = Array(icons.prefix(3))
        let iconSize = size * (shown.count == 1 ? 0.62 : 0.52)
        let span = size * 0.32
        let step = shown.count > 1 ? span / CGFloat(shown.count - 1) : 0
        let start = -span / 2

        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(backdrop)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.18)
                        .strokeBorder(border, lineWidth: 1)
                )

            ForEach(Array(shown.enumerated()), id: \.offset) { index, icon in
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.25), radius: size * 0.03, x: 0, y: size * 0.015)
                    .offset(
                        x: start + step * CGFloat(index),
                        y: start + step * CGFloat(index)
                    )
            }
        }
        .frame(width: size, height: size)
    }
}
