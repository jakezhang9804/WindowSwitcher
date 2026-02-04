import SwiftUI

struct SwitcherWindow: View {
    @StateObject private var viewModel: SwitcherViewModel
    let onDismiss: () -> Void
    
    init(windowService: WindowService, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: SwitcherViewModel(windowService: windowService))
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Field
            SearchField(
                text: $viewModel.searchText,
                placeholder: "Search \(viewModel.totalCount) windows"
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
                .opacity(0.5)
            
            // Results List
            if viewModel.filteredWindows.isEmpty {
                emptyStateView
            } else {
                ResultsList(
                    windows: viewModel.filteredWindows,
                    selectedIndex: $viewModel.selectedIndex,
                    onSelect: { window in
                        viewModel.activateWindow(window)
                        onDismiss()
                    }
                )
            }
        }
        .frame(width: 600, height: 400)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            viewModel.refreshWindows()
        }
        .onKeyPress(.escape) {
            if viewModel.searchText.isEmpty {
                onDismiss()
            } else {
                viewModel.searchText = ""
            }
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
            if let window = viewModel.selectedWindow {
                viewModel.activateWindow(window)
                onDismiss()
            }
            return .handled
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No windows found")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
