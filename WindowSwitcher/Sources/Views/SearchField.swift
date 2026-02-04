import SwiftUI

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var isFocused: Bool
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Search Icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            // Text Field
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.secondary.opacity(0.8)))
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($isFocused)
            
            // Clear Button with Animation
            if !text.isEmpty {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        text = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isHovered ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            // Delay focus to ensure view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
}

#Preview {
    SearchField(text: .constant(""), placeholder: "Search 42 windows")
        .padding()
        .frame(width: 500)
}
