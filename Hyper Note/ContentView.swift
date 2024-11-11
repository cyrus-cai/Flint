import SwiftDown
import SwiftUI

struct ContentView: View {
    @State private var text = ""
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme // 添加对当前颜色方案的引用
    
    private var title: String {
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        return firstLine.isEmpty ? "Untitled" : String(firstLine.prefix(10))
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(spacing: 0) {
                TitleBarView(title: title, isHovered: isHovered)
                
                VStack(spacing: 0) {
                    EditorView(text: $text)
                    CharacterCountView(count: text.count)
                }
            }
        }
        .frame(minWidth: 400, maxWidth: 400, minHeight: 120, maxHeight: 120)
        .ignoresSafeArea()
        // 移除固定的深色模式设置，改为响应系统
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.state = .active
        // 根据当前颜色方案设置材质
        view.material = colorScheme == .dark ? .dark : .light
        // 根据系统设置自动切换外观
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // 更新视图的外观
        nsView.material = colorScheme == .dark ? .dark : .light
        nsView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}

struct EditorView: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isEditing: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if !isEditing && text.isEmpty {
                Text("Start writing...")
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
                    .opacity(0.25)
            }
            
            TextEditor(text: $text)
                .font(.custom("PingFang SC", size: 13.0))
                .disableAutocorrection(true)
                .foregroundColor(.primary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .focused($isEditing)
        }
    }
}

struct CharacterCountView: View {
    let count: Int
    
    var body: some View {
        Text("\(count) characters")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .center)
            .opacity(0.25)
    }
}

#Preview {
    ContentView()
}

