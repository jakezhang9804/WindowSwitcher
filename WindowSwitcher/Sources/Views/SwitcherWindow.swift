import SwiftUI
import AppKit
import AppSwitcherKit

/// Main switcher panel view — modeled after TabTab's interaction patterns.
///
/// Interaction flow:
/// 1. Panel opens with Option+Tab, second item pre-selected (last used window)
/// 2. While holding Option, each Tab press cycles to the next window
/// 3. Releasing Option confirms the selection and switches to that window
/// 4. Type to search across all open windows AND installed apps
/// 5. Pressing Enter activates the selected item
/// 6. Pressing Escape clears search or dismisses the panel
struct SwitcherWindow: View {
    @StateObject private var viewModel: SwitcherViewModel
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    init(
        windowService: WindowService,
        settingsStore: UserDefaultsSwitcherSettingsStore = UserDefaultsSwitcherSettingsStore(),
        onDismiss: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: SwitcherViewModel(
            windowService: windowService,
            settingsStore: settingsStore
        ))
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            SearchField(text: $viewModel.searchText)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Results list or empty state
            let items = viewModel.displayItems
            if items.isEmpty {
                EmptyStateView(searchText: viewModel.searchText)
            } else {
                SwitcherResultsList(
                    items: items,
                    selectedIndex: $viewModel.selectedIndex,
                    searchText: viewModel.searchText,
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
        .frame(maxHeight: .infinity)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            viewModel.refreshWindows()
        }
        .onKeyPress(.escape) {
            handleEscape()
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
        .onKeyPress(.return) {
            handleReturn()
            return .handled
        }
        .onKeyPress(.tab) {
            viewModel.selectNext()
            return .handled
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 6) {
            let items = viewModel.displayItems
            if !items.isEmpty {
                Image(systemName: "macwindow")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                Text("\(viewModel.totalCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer()

            Text("Powered by Manus")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.2))

            Button(action: { onOpenSettings() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Background

    private var panelBackground: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color.black.opacity(0.65)
        }
    }

    // MARK: - Key Handlers

    private func handleEscape() {
        if viewModel.searchText.isEmpty {
            onDismiss()
        } else {
            viewModel.searchText = ""
        }
    }

    private func handleReturn() {
        viewModel.activateSelectedItem()
        onDismiss()
    }

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

// MARK: - Visual Effect View

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Switcher Results List (supports mixed SwitcherItem)

struct SwitcherResultsList: View {
    let items: [SwitcherItem]
    @Binding var selectedIndex: Int
    let searchText: String
    let onSelect: (SwitcherItem) -> Void
    let onHover: ((Int) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    // Determine if we need section headers
                    let windowIndices = items.indices.filter { items[$0].isWindow }
                    let appIndices = items.indices.filter { !items[$0].isWindow }
                    let showHeaders = !searchText.isEmpty && !windowIndices.isEmpty && !appIndices.isEmpty

                    if showHeaders {
                        sectionHeader("Open Windows")
                    }

                    ForEach(windowIndices, id: \.self) { index in
                        let item = items[index]
                        SwitcherResultItem(
                            item: item,
                            isSelected: index == selectedIndex,
                            index: index
                        )
                        .id(index)
                        .onTapGesture { onSelect(item) }
                        .onHover { isHovered in
                            if isHovered { onHover?(index) }
                        }
                    }

                    if showHeaders || (!searchText.isEmpty && windowIndices.isEmpty && !appIndices.isEmpty) {
                        sectionHeader("Applications")
                    }

                    ForEach(appIndices, id: \.self) { index in
                        let item = items[index]
                        SwitcherResultItem(
                            item: item,
                            isSelected: index == selectedIndex,
                            index: index
                        )
                        .id(index)
                        .onTapGesture { onSelect(item) }
                        .onHover { isHovered in
                            if isHovered { onHover?(index) }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

// MARK: - Switcher Result Item (supports SwitcherItem)

struct SwitcherResultItem: View {
    let item: SwitcherItem
    let isSelected: Bool
    let index: Int

    var body: some View {
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
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "app")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.3))
                    )
            }

            // Text area
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Badge: keyboard shortcut number for first 9 items
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
