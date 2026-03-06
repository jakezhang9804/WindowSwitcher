import SwiftUI

/// 窗口结果列表
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
            ScrollView(.vertical, showsIndicators: false) {
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
}

/// 空状态视图
struct EmptyStateView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: searchText.isEmpty ? "rectangle.stack" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            
            Text(searchText.isEmpty ? "No windows available" : "No results found")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
    }
}
