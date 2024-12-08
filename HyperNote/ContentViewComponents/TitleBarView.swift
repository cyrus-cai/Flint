import SwiftUICore
import SwiftUI

// MARK: - TitleBar Related Views
struct TitleBarView: View {
    let title: String
    let isHovered: Bool
    @ObservedObject var toolbarState: TitleBarToolbarState
    let onNoteSelected: (String) -> Void  // 新增参数
    
    var body: some View {
        ZStack {
            // 拖动区域
            DraggableView()
                .frame(height: 32)
            
            HStack {
                VStack{}.frame(width: 96.0)
                
                Spacer()
                // 居中标题
                titleSection
                Spacer()
                
                // 右侧工具栏
                TitleBarToolbar(state: toolbarState, isVisible: isHovered || toolbarState.showRecentNotes || toolbarState.showSettingsList, onNoteSelected:onNoteSelected)
            }
        }.onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) {
                    switch event.charactersIgnoringModifiers {
                    case "f","h":
                        toolbarState.openFileDictionary()
                        return nil
                    case "n","k":
                        if !toolbarState.isEmpty {
                            toolbarState.addNew()
                            return nil
                        }
                    default:
                        break
                    }
                }
                return event
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
    let onNoteSelected: (String) -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            
            TitleBarButton(
                           icon: .command,
                           action: { state.showSettingsList = true }
                       )
                       .popover(isPresented: $state.showSettingsList) {
                           SettingsListView(
                               onRename: state.renameFile,
                               onDelete: state.deleteFile,
                               onSettings: state.openSettings
                           )
                       }
            
            TitleBarButton(
                icon: .note,
                action: { state.openFileDictionary() }
            )
            .popover(isPresented: $state.showRecentNotes) {
                RecentNotesListView(
                    notes: state.recentNotes,
                    onSelectNote: onNoteSelected
                )
            }
            
            TitleBarButton(
                icon: .plus,
                isDisabled: state.isEmpty, // Add disabled state
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
    let action: () -> Void
    let isDisabled: Bool
    @State private var isHovered = false  // 新增状态追踪悬停
    @State private var showTooltip = false
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    
    init(icon: TitleBarIcon, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.isDisabled = isDisabled
        self.action = action
    }
    
    var body: some View {
        ZStack {
            Button(action: action) {
                Image(systemName: icon.systemName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(isDisabled ? .secondary.opacity(0.6) : .secondary)
                    .frame(width: 26, height: 28)
                    .background(
                              RoundedRectangle(cornerRadius: 6)
                                  .fill(isHovered ? (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)) : Color.clear)
                          )
//                    .overlay(
//                        Group {
//                            if showTooltip {
//                                Text(icon.tooltip)
//                                    .font(.custom("PingFang SC", size: 12.0))
//                                    .padding(.horizontal, 6)
//                                    .padding(.vertical, 3)
//                                    .background(
//                                        colorScheme == .dark ?
//                                            Color(white: 0.2) :
//                                            Color(white: 0.85)
//                                    )
//                                    .foregroundColor(Color.primary)
//                                    .zIndex(40)
//                                    .cornerRadius(6)
//                                    .offset(y: 28)
//                                    .fixedSize(horizontal: true, vertical: false)
//                                    .transition(.opacity)
//                            }
//                        }
//                    )
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isHovered = hovering && !isDisabled
//                            showTooltip = hovering && !isDisabled
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
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
               return "Command"
           case .note:
               return "Recents"
           case .plus:
               return "New"
           }
       }
    
}

// MARK: - Toolbar State
class TitleBarToolbarState: ObservableObject {
    @Published var showSettingsList = false
    @Published var isSplitActive = false
    @Published var isListVisible = false
    @Published var showRecentNotes = false
    @Published var recentNotes: [RecentNote] = []
    @Published var isEmpty: Bool = true // Add isEmpty state

    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSave: (() -> Void)?
    var onAddNew: (() -> Void)?
    var onSelectNote: ((String) -> Void)?
    
    init() {
            refreshRecentNotes()
        }
        
    func refreshRecentNotes() {
        recentNotes =  FileManager.getRecentNotes()
    }
    
    func renameFile() {
           onRename?()
       }
       
   func deleteFile() {
       onDelete?()
   }
    
//
//    func scan() {
//        ScreenCaptureManager.shared.startCapture { text in
//                  NotificationCenter.default.post(
//                      name: .init("InsertCapturedText"),
//                      object: text
//                  )
//              }
//    }
    
    func openFileDictionary() {
           showRecentNotes = true
           refreshRecentNotes()
       }
   
    func openSettings() {
        WindowManager.shared.createSettingsWindow()
    }
    
    func addNew() {
        onSave?() // 保存当前文档
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
