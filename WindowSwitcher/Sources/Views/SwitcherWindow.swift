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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    var layout: SwitcherLayout = .list
    let onConfirm: () -> Void
    let onOpenSettings: () -> Void
    let onItemCountChange: (Int) -> Void

    @FocusState private var isTextFieldFocused: Bool

    /// Mouse position when the panel appeared. Hover-selection stays disabled until
    /// the mouse actually moves — the panel often opens under a stationary cursor,
    /// which would otherwise silently override the default "previous window" selection.
    @State private var initialMouseLocation: CGPoint = NSEvent.mouseLocation
    @State private var mouseHasMoved = false
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()

    init(
        viewModel: SwitcherViewModel,
        layout: SwitcherLayout = .list,
        onConfirm: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onItemCountChange: @escaping (Int) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.layout = layout
        self.onConfirm = onConfirm
        self.onOpenSettings = onOpenSettings
        self.onItemCountChange = onItemCountChange
    }

    // Keep translucent color stacking intentionally shallow: one material at the
    // window level, one neutral surface for controls/selections, and accent color
    // only for focus. This avoids muddy overlays in both light and dark themes.
    private var secondaryText: Color { .secondary }
    private var tertiaryText: Color { Color(nsColor: .tertiaryLabelColor) }
    private var subtleText: Color { Color(nsColor: .quaternaryLabelColor) }
    private var quietSurface: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.05)
    }
    private var raisedSurface: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.075)
    }
    private var selectedSurface: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.085)
    }
    private var hairline: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.11)
    }

    // MARK: - List sizing

    /// The vertical list shows at most this many rows; beyond it it scrolls.
    /// Keep in sync with `AppDelegate.calculatePanelHeight`.
    static let listMaxVisibleRows = 9
    static let listWidth: CGFloat = 360
    /// Row content (30pt icon) + vertical padding 8×2
    static let listRowHeight: CGFloat = 46
    static let listRowSpacing: CGFloat = 2
    static let stripCellSize: CGFloat = 82
    static let stripSpacing: CGFloat = 4
    static let stripHorizontalPadding: CGFloat = 16

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
        .onKeyPress(keys: [.tab]) { press in
            if press.modifiers.contains(.shift) {
                viewModel.selectPrevious()
            } else {
                viewModel.selectNext()
            }
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
        .onAppear {
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
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
                    onSelect: { index, item in selectOrConfirm(item, at: index) },
                    onHover: { hoverSelect($0) }
                )
                // Cap at 9 rows; extra rows scroll inside this frame.
                .frame(height: Self.listHeight(for: items.count))
            }

            bottomBar
        }
        .frame(width: Self.listWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hairline, lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                        HStack(spacing: Self.stripSpacing) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                stripIcon(item: item, isSelected: index == viewModel.selectedIndex, index: index)
                                    .id(index)
                                    .onTapGesture { selectOrConfirm(item, at: index) }
                                    .onHover { if $0 { hoverSelect(index) } }
                            }
                        }
                        .padding(.horizontal, Self.stripHorizontalPadding)
                    }
                    .onChange(of: viewModel.selectedIndex) { _, newValue in
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }

                // Selection detail stays visually anchored while the icons move.
                HStack(spacing: 7) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 13)

                    Text(selectedCaption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let selected = viewModel.selectedItem, selected.windows.count >= 2 {
                        Text("·")
                            .foregroundStyle(subtleText)

                        Text(L10n.windowCountText(selected.windows.count))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(secondaryText)

                        Spacer(minLength: 4)

                        HStack(spacing: 4) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text(L10n.drillHint)
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(tertiaryText)
                    }

                    Spacer(minLength: 0)

                    Button(action: { onOpenSettings() }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tertiaryText)
                            .frame(width: 24, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.settings)
                    .accessibilityLabel(L10n.settings)
                }
                .padding(.horizontal, 18)
                .frame(height: 22)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Secondary (per-app windows) drill-down

    private var secondaryBody: some View {
        VStack(spacing: 0) {
            // Back header: ‹ App name · N windows
            HStack(spacing: 8) {
                Button(action: { viewModel.exitSecondary() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(secondaryText)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.back)

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

            SwitcherResultsList(
                items: secondaryItems,
                selectedIndex: $viewModel.secondaryIndex,
                onSelect: { index, item in
                    guard case .window = item else { return }
                    viewModel.secondaryIndex = index
                    onConfirm()
                },
                onHover: { viewModel.secondaryIndex = $0 }
            )
            .frame(height: Self.listHeight(for: secondaryItems.count))
        }
        .padding(.vertical, 6)
        .frame(width: Self.listWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hairline, lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func stripIcon(item: SwitcherItem, isSelected: Bool, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(isSelected ? selectedSurface : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.42) : Color.clear, lineWidth: 1)
                )

            Group {
                if let groupIcons = item.groupIcons {
                    GroupStackIcon(icons: groupIcons, size: 62)
                } else if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 62, height: 62)
                } else {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(quietSurface)
                        .frame(width: 62, height: 62)
                        .overlay(
                            Image(systemName: "app")
                                .font(.system(size: 26, weight: .light))
                                .foregroundColor(tertiaryText)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            // The center layout has exactly one badge, anchored to top-right.
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? .white : secondaryText)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.accentColor : raisedSurface)
                            .overlay(Circle().strokeBorder(hairline, lineWidth: isSelected ? 0 : 0.75))
                    )
                    .padding(.top, 3)
                    .padding(.trailing, 3)
            }
        }
        .frame(width: Self.stripCellSize, height: Self.stripCellSize)
        .contentShape(Rectangle())
        .scaleEffect(isSelected && !reduceMotion ? 1.025 : 1)
        .shadow(color: isSelected ? Color.black.opacity(colorScheme == .dark ? 0.2 : 0.12) : .clear, radius: 7, y: 2)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(item.subtitle ?? L10n.windowCountText(item.windows.count))
        .accessibilityHint(index < 9 ? L10n.quickSelectHint(index + 1) : L10n.activateItemHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedCaption: String {
        guard let item = viewModel.selectedItem else { return " " }
        if item.windows.count >= 2 {
            return item.displayName
        }
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
                        .onSubmit { onConfirm() }
                }

                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                    .help(L10n.clearSearch)
                    .accessibilityLabel(L10n.clearSearch)
                }
            } else {
                Text(L10n.searchInactivePlaceholder)
                    .font(.system(size: 13))
                    .foregroundColor(tertiaryText)
                Spacer()
                Text("↩")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .frame(width: 22, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(raisedSurface))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(viewModel.isSearchActive ? selectedSurface : quietSurface)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(viewModel.isSearchActive ? Color.accentColor.opacity(0.42) : hairline, lineWidth: 0.75)
        )
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !viewModel.isSearchActive { viewModel.isSearchActive = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.searchWindowsAndApps)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: emptyStateSymbol)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(isPermissionEmptyState ? .orange : tertiaryText)

            Text(emptyStateTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(secondaryText)

            Text(emptyStateHint)
                .font(.system(size: 11))
                .foregroundColor(tertiaryText)
                .multilineTextAlignment(.center)

            if isPermissionEmptyState {
                Button(L10n.openSettings) { onOpenSettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 80)
        .padding(.vertical, 30)
    }

    private var isPermissionEmptyState: Bool {
        viewModel.searchText.isEmpty && !screenRecordingGranted
    }

    private var emptyStateSymbol: String {
        if isPermissionEmptyState { return "exclamationmark.triangle" }
        return viewModel.searchText.isEmpty ? "rectangle.stack" : "magnifyingglass"
    }

    private var emptyStateTitle: String {
        if isPermissionEmptyState { return L10n.screenRecordingRequiredTitle }
        return viewModel.searchText.isEmpty ? L10n.noWindows : L10n.noResults
    }

    private var emptyStateHint: String {
        if isPermissionEmptyState { return L10n.screenRecordingRequiredDescription }
        return viewModel.searchText.isEmpty ? L10n.noWindowsHint : L10n.noResultsHint
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            let items = viewModel.displayItems
            if !items.isEmpty {
                Label(L10n.itemCountText(viewModel.totalCount), systemImage: "rectangle.stack")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tertiaryText)
            }

            Spacer()

            HStack(spacing: 4) {
                Text("esc")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(quietSurface))
                Text(L10n.dismissAction)
                    .font(.system(size: 10))
                    .foregroundStyle(tertiaryText)
            }

            Button(action: { onOpenSettings() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tertiaryText)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.settings)
            .accessibilityLabel(L10n.settings)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Actions

    private func selectOrConfirm(_ item: SwitcherItem, at index: Int) {
        viewModel.selectedIndex = index
        if item.windows.count >= 2 {
            viewModel.enterSecondary()
        } else {
            onConfirm()
        }
    }
}

// MARK: - Switcher Results List (supports mixed SwitcherItem)

struct SwitcherResultsList: View {
    let items: [SwitcherItem]
    @Binding var selectedIndex: Int
    let onSelect: (Int, SwitcherItem) -> Void
    let onHover: ((Int) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var tertiaryText: Color { Color(nsColor: .tertiaryLabelColor) }
    private var quietSurface: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.05)
    }
    private var selectedSurface: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.085)
    }
    private var hairline: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.11)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        resultItem(item: item, isSelected: index == selectedIndex, index: index)
                            .id(index)
                            .onTapGesture { onSelect(index, item) }
                            .onHover { if $0 { onHover?(index) } }
                    }
                }
                .padding(.horizontal, 8)
            }
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func resultItem(item: SwitcherItem, isSelected: Bool, index: Int) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 3, height: 22)

            if let groupIcons = item.groupIcons {
                GroupStackIcon(icons: groupIcons, size: 30)
            } else if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(quietSurface)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "app")
                            .font(.system(size: 14))
                            .foregroundColor(tertiaryText)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Drill-in chevron for multi-window apps
            if item.windows.count >= 2 {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tertiaryText)
            }

            // Badge: keyboard shortcut number for first 9 items
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(isSelected ? .primary : tertiaryText)
                    .frame(width: 20, height: 20)
                    .background(quietSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? selectedSurface : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? hairline : Color.clear, lineWidth: 0.75)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(item.subtitle ?? L10n.windowCountText(item.windows.count))
        .accessibilityHint(index < 9 ? L10n.quickSelectHint(index + 1) : L10n.activateItemHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Group Stack Icon

/// Composite icon for an app group: member icons overlapping diagonally on a
/// screen-shaped backdrop — "the apps as they sit on the screen".
struct GroupStackIcon: View {
    let icons: [NSImage]
    let size: CGFloat

    var body: some View {
        let shown = Array(icons.prefix(3))
        let iconSize = size * (shown.count == 1 ? 0.62 : 0.52)
        let span = size * 0.32
        let step = shown.count > 1 ? span / CGFloat(shown.count - 1) : 0
        let start = -span / 2

        ZStack {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, icon in
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.18), radius: size * 0.025, x: 0, y: size * 0.012)
                    .offset(
                        x: start + step * CGFloat(index),
                        y: start + step * CGFloat(index)
                    )
            }
        }
        .frame(width: size, height: size)
    }
}
