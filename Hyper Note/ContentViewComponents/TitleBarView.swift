import SwiftUICore
import SwiftUI

// MARK: - TitleBar Related Views
struct TitleBarView: View {
    let title: String
    let isHovered: Bool
//    @StateObject var toolbarState = TitleBarToolbarState()
    @ObservedObject var toolbarState: TitleBarToolbarState
    
    var body: some View {
        ZStack {
            // 拖动区域
            DraggableView()
                .frame(height: 32)
            
            HStack {
//                TitleBarToolbar(state: toolbarState, isVisible: isHovered).opacity(0)
                VStack{}.frame(width: 96.0)
                
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
            .opacity(isHovered ? 0.85 : 0.25)
            .padding(.trailing, 2)
    }
}

struct TitleBarToolbar: View {
    @ObservedObject var state: TitleBarToolbarState
    let isVisible: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            TitleBarButton(
                icon: .command,
                action: { state.openSettings() }
            )
            
            TitleBarButton(
                icon: .note,
                action: { state.openFileDictionary() }
            )
            .popover(isPresented: $state.showRecentNotes) {
                RecentNotesListView(
                    notes: state.recentNotes,
                    onSelectNote: { content in
                        DispatchQueue.main.async {
                            state.onSelectNote?(content)
                            state.showRecentNotes = false
                        }
                    }
                )
            }
            
            TitleBarButton(
                icon: .plus,
                action: { state.addNew() }
            )
        }
        .padding(.horizontal, 8)
        .opacity(isVisible ? 1 : 0)
    }
}

// MARK: - TitleBar Button
struct TitleBarButton: View {
    let icon: TitleBarIcon
//    var isActive: Bool = false
    let action: () -> Void
    @State private var showTooltip = false
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    
    var body: some View {
        ZStack {
            Button(action: action) {
                Image(systemName: icon.systemName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Group {
                            if showTooltip {
                                Text(icon.tooltip)
                                    .font(.custom("PingFang SC", size: 12.0))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                            colorScheme == .dark ?
                                                Color(white: 0.2) :  // 深色模式下用20%白
                                                Color(white: 0.85)   // 浅色模式下用95%白
                                        )
                                    .foregroundColor(Color.primary)
                                    .zIndex(40)
                                    .cornerRadius(6)
                                    .offset(y: 24)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .transition(.opacity)
                            }
                        }
                    )
                    .onHover { hovering in
                        print("hovering")
                        // Start a delay when the mouse hovers over the button
                        withAnimation(.easeInOut(duration: 0.1)) {
                            if hovering {
                                DispatchQueue.main.async { //
                                    showTooltip = true
                                    print("hovering true")
                                }
                            } else {
                                showTooltip = false
                            }
                        }
                    }
            }
            .buttonStyle(.plain)
           
        }
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
            return "clock"
        case .plus:
            return "plus"
        }
    }
    
    var tooltip: String {
           switch self {
           case .command:
               return "Settings"
           case .note:
               return "All"
           case .plus:
               return "New"
           }
       }
    
}

// MARK: - Toolbar State
class TitleBarToolbarState: ObservableObject {
    @Published var isSplitActive = false
    @Published var isListVisible = false
    @Published var showRecentNotes = false
    @Published var recentNotes: [RecentNote] = []
    
    var onAddNew: (() -> Void)? // 添加闭包属性
    var onSelectNote: ((String) -> Void)?
    
    init() {
            refreshRecentNotes()
        }
        
    func refreshRecentNotes() {
        recentNotes =  FileManager.getRecentNotes()
    }
//    
    func scan() {
        ScreenCaptureManager.shared.startCapture { text in
                  NotificationCenter.default.post(
                      name: .init("InsertCapturedText"),
                      object: text
                  )
              }
    }
    
    func openFileDictionary() {
           showRecentNotes = true
//           refreshRecentNotes()
       }
   
    func openSettings() {
        WindowManager.shared.createSettingsWindow()
    }
    
    
//    func openFileDictionary() {
//        let notesURL = FileManager.shared.notesDirectory
//        NSWorkspace.shared.open(notesURL)
//    }
    
    func addNew() {
        onAddNew?() 
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

//#Preview {
//    TitleBarView(title: "78787", isHovered: true)
//}
