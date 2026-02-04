import SwiftUI

struct ResultsList: View {
    let windows: [WindowInfo]
    @Binding var selectedIndex: Int
    let onSelect: (WindowInfo) -> Void
    let onHover: ((Int) -> Void)?
    
    init(
        windows: [WindowInfo],
        selectedIndex: Binding<Int>,
        onSelect: @escaping (WindowInfo) -> Void,
        onHover: ((Int) -> Void)? = nil
    ) {
        self.windows = windows
        self._selectedIndex = selectedIndex
        self.onSelect = onSelect
        self.onHover = onHover
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                        ResultItem(
                            window: window,
                            isSelected: index == selectedIndex,
                            index: index
                        )
                        .id(index)
                        .onTapGesture {
                            onSelect(window)
                        }
                        .onHover { isHovered in
                            if isHovered {
                                onHover?(index)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty ? "rectangle.stack" : "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text(searchText.isEmpty ? "No windows available" : "No results found")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            
            if !searchText.isEmpty {
                Text("Try a different search term")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    ResultsList(
        windows: [
            WindowInfo(id: 1, title: "Window 1", appName: "App 1", appPID: 1, appIcon: nil),
            WindowInfo(id: 2, title: "Window 2", appName: "App 2", appPID: 2, appIcon: nil),
        ],
        selectedIndex: .constant(0),
        onSelect: { _ in }
    )
    .frame(width: 500, height: 300)
}
