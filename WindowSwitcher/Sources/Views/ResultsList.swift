import SwiftUI

struct ResultsList: View {
    let windows: [WindowInfo]
    @Binding var selectedIndex: Int
    let onSelect: (WindowInfo) -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
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
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}
