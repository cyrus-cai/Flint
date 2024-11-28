import SwiftDown
import SwiftUI

struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
        print("window height changed",value)
      
    }
}

struct ContentView: View {
    @State private var text = ""
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme // 添加对当前颜色方案的引用
    @StateObject private var toolbarState = TitleBarToolbarState()
    
    @State private var lastSaveDate: Date?
    @State private var saveError: Error?
    
    private func saveDocument() {
           do {
               let fileURL = FileManager.shared.fileURL(for: title)
               try text.write(to: fileURL, atomically: true, encoding: .utf8)
               print("文件保存路径：\(FileManager.shared.notesDirectory.path)")
               lastSaveDate = Date()
//               toolbarState.refreshRecentNotes()
           } catch {
               saveError = error
               print("保存失败：\(error.localizedDescription)")
           }
       }
    
    private func loadNoteContent(_ content: String) {
          text = content
      }
    
    private let autoSaveTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    
    private var title: String {
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        if firstLine.isEmpty {
            return "Untitled"
        }
        return firstLine.count > 12 ? firstLine.prefix(12) + "..." : firstLine
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                TitleBarView(title: title, isHovered: isHovered, toolbarState: toolbarState,onNoteSelected: loadNoteContent)
//                    .zIndex(10)
                
                VStack(spacing: 0) {
                    EditorView(text: $text)
                    CharacterCountView(count: text.count)
                }
//                .zIndex(5)
             
            }
        }
        .onChange(of: text) { newValue in
                   toolbarState.isEmpty = newValue.isEmpty
               }
        .onAppear {
                  toolbarState.onAddNew = { text = "" }
                  toolbarState.isEmpty = text.isEmpty
              }
        .ignoresSafeArea()
        .listStyle(.sidebar)
        // 移除固定的深色模式设置，改为响应系统
        .onHover { hovering in
            isHovered = hovering
        }
        .onReceive(autoSaveTimer) { _ in
                   if !text.isEmpty {
                       saveDocument()
                       print("document saved")
                   }
               }
    }
}

struct EditorView: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isEditing: Bool
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    let linkColor = Color.purple
    @State private var isPlaceholderVisible = true

    
    @State private var lastHeight: CGFloat = 0
    @State private var debounceTimer: Timer?
    
    private func calculateHeight(for text: String, width: CGFloat) -> CGFloat {
            let storage = NSTextStorage(string: text)
            let container = NSTextContainer(size: CGSize(width: width - 36, height: .greatestFiniteMagnitude)) // 32为左右padding总和
            container.lineFragmentPadding = 0
            
            let manager = NSLayoutManager()
            manager.addTextContainer(container)
            storage.addLayoutManager(manager)
            
            // 设置文本属性
            let range = NSRange(location: 0, length: text.utf16.count)
            storage.addAttributes([
                .font: NSFont(name: "PingFang SC", size: 14.0) ?? NSFont.systemFont(ofSize: 14.0)
            ], range: range)
            
            // 计算实际需要的高度
            manager.ensureLayout(for: container)
            let height = manager.usedRect(for: container).height
            
            // 加上padding的高度
            return height + 92 // 80+12
        }
    
    struct KeyEventHandler: NSViewRepresentable {
        let onKeyDown: (NSEvent) -> Void
        
        func makeNSView(context: Context) -> NSView {
            let view = KeyView()
            view.onKeyDown = onKeyDown
            return view
        }
        
        func updateNSView(_ nsView: NSView, context: Context) {}
        
        class KeyView: NSView {
            var onKeyDown: ((NSEvent) -> Void)?
            
            override var acceptsFirstResponder: Bool { true }
            
            override func keyDown(with event: NSEvent) {
                onKeyDown?(event)
                super.keyDown(with: event)
            }
        }
    }

    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.custom("PingFang SC", size: 14.0))
                    .disableAutocorrection(true)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.automatic)
                //                       .scrollDisabled(true)
                    .background(Color.clear)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .focused($isEditing)
                //                       .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                                   // 确保视图出现后立即获取焦点
                                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                       isEditing = true
                                   }
                               }
                    .preference(
                        key: ContentHeightPreferenceKey.self,
                        //                           value: geometry.size.height
                        //                           value: debouncedHeightUpdate(for: text, width: geometry.size.width)
                        value: calculateHeight(for: text, width: geometry.size.width)
                    )
                    .tint(.purple)  // 设置光标颜色
                    .background(
                        KeyEventHandler { event in
                            if event.keyCode != 51 { // 51 是删除键的 keyCode
                                isPlaceholderVisible = false
                            }
                        }
                    )
                   .onChange(of: text) { newValue in
                       if newValue.isEmpty {
                           isPlaceholderVisible = true
                       }
                   }

                //                       .fixedSize(horizontal: false, vertical: true)
                
                if text.isEmpty {
                    Text("Start writing...")
                        .font(.custom("PingFang SC", size: 14.0))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .foregroundColor(.gray.opacity(0.2))
                }
            }
        }
    }
}

struct CharacterCountView: View {
    let count: Int
//    let icon: TitleBarIcon
//    let action: () -> Void
    @State private var showTooltip = false 
    
    var body: some View {
        HStack{
            Text("\(count) characters")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .center)
                .opacity(0.5)
        }
        
        
    }
}

#Preview {
    ContentView()
}

