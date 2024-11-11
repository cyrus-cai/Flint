import SwiftUICore
import SwiftUI

// MARK: - TitleBar Related Views
struct TitleBarView: View {
    let title: String
    let isHovered: Bool
    @StateObject private var toolbarState = TitleBarToolbarState()
    
    var body: some View {
        ZStack {
            // 拖动区域
            DraggableView()
                .frame(height: 32)
            
            HStack {
                TitleBarToolbar(state: toolbarState, isVisible: isHovered).opacity(0)
                
                Spacer()
                // 居中标题
                titleSection
                Spacer()
                
                // 右侧工具栏
                TitleBarToolbar(state: toolbarState, isVisible: isHovered)
            }
        }
    }
    
    private var titleSection: some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .opacity(isHovered ? 0.5 : 0.25)
            .padding(.trailing, 2)
    }
}

// MARK: - TitleBar Toolbar
struct TitleBarToolbar: View {
    @ObservedObject var state: TitleBarToolbarState
    let isVisible: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            TitleBarButton(
                icon: .command,
//                isActive: state.isSplitActive,
                action: { state.toggleSplit() }
            )
            
            TitleBarButton(
                icon: .note,
//                isActive: state.isListVisible,
                action: { state.toggleList() }
            )
            
            TitleBarButton(
                icon: .plus,
                action: { state.addNew() }
            )
        }
        .padding(.trailing, 4)
        .opacity(isVisible ? 1 : 0)
    }
}

// MARK: - TitleBar Button
struct TitleBarButton: View {
    let icon: TitleBarIcon
//    var isActive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon.systemName)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TitleBar Icon Enum
enum TitleBarIcon {
    case command
    case note
    case plus
    
    var systemName: String {
        switch self {
        case .command:
            return "command"
        case .note:
            return "note.text"
        case .plus:
            return "plus"
        }
    }
}

// MARK: - Toolbar State
class TitleBarToolbarState: ObservableObject {
    @Published var isSplitActive = false
    @Published var isListVisible = false
    
    func toggleSplit() {
        isSplitActive.toggle()
    }
    
    func toggleList() {
        isListVisible.toggle()
    }
    
    func addNew() {
        // 处理添加新笔记逻辑
    }
}

// MARK: - Draggable View
struct DraggableView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
