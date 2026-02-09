import SwiftUI
import AppKit

struct SwitcherWindow: View {
    @StateObject private var viewModel: SwitcherViewModel
    let onDismiss: () -> Void
    
    // MARK: - Constants
    
    private let windowWidth: CGFloat = 640
    private let minHeight: CGFloat = 120
    private let maxHeight: CGFloat = 500
    private let itemHeight: CGFloat = 58
    private let headerHeight: CGFloat = 60
    
    init(windowService: WindowService, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: SwitcherViewModel(windowService: windowService))
        self.onDismiss = onDismiss
    }
    
    // MARK: - Computed Properties
    
    private var dynamicHeight: CGFloat {
        let contentHeight = CGFloat(viewModel.filteredWindows.count) * itemHeight + headerHeight + 16
        return min(max(contentHeight, minHeight), maxHeight)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Field
            searchSection
            
            // Divider
            Divider()
                .background(Color.primary.opacity(0.1))
            
            // Results List or Empty State
            resultsSection
        }
        .frame(width: windowWidth, height: dynamicHeight)
        .background(windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(windowBorder)
        .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 15)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .onAppear {
            viewModel.refreshWindows()
        }
        // Escape key
        .onKeyPress(.escape) {
            handleEscape()
            return .handled
        }
        // Arrow keys
        .onKeyPress(.upArrow) {
            viewModel.selectPrevious()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.selectNext()
            return .handled
        }
        // Enter key
        .onKeyPress(.return) {
            handleReturn()
            return .handled
        }
        // Cmd+1 through Cmd+9
        .onKeyPress(keys: ["1", "2", "3", "4", "5", "6", "7", "8", "9"], phases: .down) { press in
            if press.modifiers.contains(.command) {
                if let number = Int(press.characters), number >= 1 && number <= 9 {
                    handleCommandNumber(number)
                    return .handled
                }
            }
            return .ignored
        }
        // App trigger key in panel (single key, no modifiers except shift)
        .onKeyPress(phases: .down) { press in
            handlePanelTrigger(press)
        }
    }
    
    // MARK: - Subviews
    
    private var searchSection: some View {
        SearchField(
            text: $viewModel.searchText,
            placeholder: dynamicPlaceholder
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    private var dynamicPlaceholder: String {
        let count = viewModel.totalCount
        if count == 0 {
            return "Search windows"
        } else if count == 1 {
            return "Search 1 window"
        } else {
            return "Search \(count) windows"
        }
    }
    
    @ViewBuilder
    private var resultsSection: some View {
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
    }
    
    private var windowBackground: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
    }
    
    private var windowBorder: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color.white.opacity(0.15), lineWidth: 1)
    }
    
    // MARK: - Key Handlers
    
    private func handleEscape() {
        if viewModel.searchText.isEmpty {
            onDismiss()
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                viewModel.searchText = ""
            }
        }
    }
    
    private func handleReturn() {
        if let window = viewModel.selectedWindow {
            viewModel.activateWindow(window)
            onDismiss()
        }
    }
    
    private func handleCommandNumber(_ number: Int) {
        let index = number - 1
        if index < viewModel.filteredWindows.count {
            let window = viewModel.filteredWindows[index]
            viewModel.activateWindow(window)
            onDismiss()
        }
    }

    private func handlePanelTrigger(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command) ||
            press.modifiers.contains(.option) ||
            press.modifiers.contains(.control) {
            return .ignored
        }

        if viewModel.activateWindowForPanelTrigger(press.characters) {
            onDismiss()
            return .handled
        }

        return .ignored
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

// MARK: - Preview

#Preview {
    SwitcherWindow(windowService: WindowService()) {
        print("Dismissed")
    }
}
