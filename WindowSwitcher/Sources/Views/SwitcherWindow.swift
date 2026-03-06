import SwiftUI
import AppKit

/// 主切换器面板，位于屏幕左侧，深色风格，与 TabTab 一致
struct SwitcherWindow: View {
    @StateObject private var viewModel: SwitcherViewModel
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void
    
    init(windowService: WindowService, onDismiss: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: SwitcherViewModel(windowService: windowService))
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索框
            SearchField(text: $viewModel.searchText)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            // 结果列表或空状态
            if viewModel.filteredWindows.isEmpty {
                EmptyStateView(searchText: viewModel.searchText)
            } else {
                ResultsList(
                    windows: viewModel.filteredWindows,
                    selectedIndex: $viewModel.selectedIndex,
                    onSelect: { window in
                        viewModel.activateWindow(window)
                        onDismiss()
                    },
                    onHover: { index in
                        viewModel.selectedIndex = index
                    }
                )
            }
            
            // 底部设置齿轮
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
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack {
            Spacer()
            Button(action: { onOpenSettings() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
        if let window = viewModel.selectedWindow {
            viewModel.activateWindow(window)
            onDismiss()
        }
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
