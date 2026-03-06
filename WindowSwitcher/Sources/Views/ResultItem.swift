import SwiftUI
import AppKit

/// 单个窗口条目，与 TabTab 风格一致
/// 布局：[应用图标] [应用名(粗体) + 窗口标题(灰色)] [窗口数量]
struct ResultItem: View {
    let window: WindowInfo
    let isSelected: Bool
    let index: Int
    
    var body: some View {
        HStack(spacing: 10) {
            // 应用图标
            appIconView
            
            // 文字区域
            VStack(alignment: .leading, spacing: 2) {
                Text(window.appName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if !window.title.isEmpty {
                    Text(window.title)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 4)
            
            // 右侧窗口数量
            if window.windowCount > 1 {
                Text("\(window.windowCount)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
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
    
    @ViewBuilder
    private var appIconView: some View {
        if let icon = window.appIcon {
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
    }
}
