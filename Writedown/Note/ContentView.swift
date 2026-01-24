import Combine
import SwiftUI

struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 106
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
        // print("window height changed", value)

    }
}

struct LinkDetector {
    static func findLinks(in text: String) -> [String] {
        let patterns = [
            "(?:@)?(?:https?://)?(?:www\\.)?[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\\.[^\\s]{2,}"
        ]

        var linkMatches: [(link: String, position: Int)] = []

        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let matches = regex.matches(
                    in: text, options: [], range: NSRange(location: 0, length: text.count))

                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let link = String(text[range])
                        // 如果链接以 @ 开头保留完整形式
                        // 否则，去除可能的 @ 前缀
                        let cleanLink =
                            link.hasPrefix("@") ? link : String(link.drop(while: { $0 == "@" }))
                        linkMatches.append((link: cleanLink, position: match.range.location))
                    }
                }
            } catch {
                print("正则表达式错误: \(error)")
            }
        }

        // 由于现在只使用一个正则表达式，不需要去重
        // 但我们仍然按位置排序以保持顺序
        linkMatches.sort { $0.position < $1.position }

        return linkMatches.map { $0.link }
    }
}

struct ContentView: View {
    @State private var text = ""
    @State private var currentNoteId: String?
    @State private var links: [String] = []
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var toolbarState = TitleBarToolbarState()
    @State private var showToast = false
    @State private var lastSaveDate: Date?
    @State private var saveError: Error?
    @State private var fileMonitor: DispatchSourceFileSystemObject?
    @AppStorage(AppStorageKeys.autoSaveInterval) private var autoSaveInterval: TimeInterval = AppDefaults.autoSaveInterval
    @State private var autoSaveTimer: AnyCancellable?
    @State private var keyboardMonitor: Any?
    @State private var showCopyToast = false
    @State private var showCopiedStatus = false
    @State private var showClaudeCodePanel = false

    static let loadNoteNotification = Notification.Name("LoadNoteNotification")
    static let showRecentNotesNotification = Notification.Name("ShowRecentNotesNotification")

    @State private var isEditingTitle = false
    @State private var editedTitle = ""

    @State private var customTitle: String?

    @FocusState private var isTitleFieldFocused: Bool

    @State private var contentHashForAIRename: Int = 0

    @AppStorage(AppStorageKeys.editorFont) private var editorFont: String = AppDefaults.editorFont

    enum SaveTrigger {
        case timer
        case focusLost
        case addNew
        case titleEdit
        case titleChanged
    }

    private func startMonitoringFile() {
        stopMonitoringFile()

        guard let currentId = currentNoteId,
            let fileURL = LocalFileManager.shared.fileURL(for: currentId)
        else {
            return
        }

        let fileDescriptor = open(fileURL.path, O_EVTONLY)
        if fileDescriptor < 0 {
            print("无法监听文件：\(fileURL.path)")
            return
        }

        let monitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        monitor.setEventHandler {
            do {
                let newContent = try String(contentsOf: fileURL, encoding: .utf8)
                if newContent != text {
                    text = newContent
                    let attributes = try Foundation.FileManager.default.attributesOfItem(
                        atPath: fileURL.path)
                    lastSaveDate = attributes[.modificationDate] as? Date
                }
            } catch {
                print("读取文件失败：\(error.localizedDescription)")
            }
        }

        monitor.setCancelHandler {
            close(fileDescriptor)
        }

        monitor.resume()
        fileMonitor = monitor
    }

    private func stopMonitoringFile() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    private func saveDocument(trigger: SaveTrigger) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        print("Saving document with trigger: \(trigger)")

        do {
            if let currentId = currentNoteId,
               let fileURL = LocalFileManager.shared.fileURL(for: currentId) {

                if trigger == .titleEdit {
                    return
                } else {
                    print("Updating existing note at \(fileURL.path)")
                    try text.write(to: fileURL, atomically: true, encoding: .utf8)
                    lastSaveDate = Date()
                    startMonitoringFile()
                }
            }
            else {
                let documentTitle = title

                guard let fileURL = LocalFileManager.shared.fileURL(for: documentTitle) else {
                    throw NSError(
                        domain: "FileError", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid file URL"])
                }

                if Foundation.FileManager.default.fileExists(atPath: fileURL.path) {
                    let uniqueTitle = "\(documentTitle)_\(Int(Date().timeIntervalSince1970))"
                    guard let uniqueFileURL = LocalFileManager.shared.fileURL(for: uniqueTitle) else {
                        throw NSError(
                            domain: "FileError", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid file URL"])
                    }

                    try text.write(to: uniqueFileURL, atomically: true, encoding: .utf8)
                    currentNoteId = uniqueTitle
                } else {
                    try text.write(to: fileURL, atomically: true, encoding: .utf8)
                    currentNoteId = documentTitle
                }

                lastSaveDate = Date()
                startMonitoringFile()
            }

            if trigger == .addNew {
                withAnimation {
                    showToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showToast = false
                    }
                }
            }
        } catch {
            saveError = error
            print("Save failed:", error.localizedDescription)
        }
    }

    func loadNoteContent(_ content: String, fileURL: URL? = nil) {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveDocument(trigger: .addNew)
        }

        text = content

        if let url = fileURL {
            let filename = url.deletingPathExtension().lastPathComponent
            currentNoteId = filename

            customTitle = filename

            do {
                let attributes = try Foundation.FileManager.default.attributesOfItem(
                    atPath: url.path)
                lastSaveDate = attributes[.modificationDate] as? Date
                startMonitoringFile()
            } catch {
                print("Failed to get file modification time: \(error.localizedDescription)")
            }
        }
        else if let currentId = currentNoteId,
            let fileURL = LocalFileManager.shared.fileURL(for: currentId)
        {
            customTitle = currentId

            do {
                let attributes = try Foundation.FileManager.default.attributesOfItem(
                    atPath: fileURL.path)
                lastSaveDate = attributes[.modificationDate] as? Date
                startMonitoringFile()
            } catch {
                print("Failed to get file modification time: \(error.localizedDescription)")
            }
        }
        else {
            currentNoteId = nil
            customTitle = nil
        }

        if !content.isEmpty {
            contentHashForAIRename = content.prefix(100).hashValue
        }
    }

    private func createNewNote() {
        stopMonitoringFile()
        text = ""
        currentNoteId = nil
        customTitle = nil
        contentHashForAIRename = 0
    }

    private func setupAutoSaveTimer() {
        print("Setting up auto-save timer with interval: \(autoSaveInterval)")
        autoSaveTimer?.cancel()

        autoSaveTimer = Timer.publish(every: autoSaveInterval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    saveDocument(trigger: .timer)
                    print("document saved with interval: \(autoSaveInterval)s")

                    if text.count >= 20 && UserDefaults.standard.bool(forKey: "enableAIRename") {
                        let currentContentHash = text.prefix(100).hashValue

                        if contentHashForAIRename == 0 {
                            contentHashForAIRename = currentContentHash

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.triggerAIRename(content: self.text)
                            }
                        }
                    }
                }
            }
    }

    // Add new method to trigger AI rename
    private func triggerAIRename(content: String) {
        print("Auto-triggering AI rename for note: \(currentNoteId ?? "untitled")")

        if content.count >= 20 {
            // Pass the content directly to the API
            DoubaoAPI.shared.summarizeWithStream(
                text: content,
                delegate: TitleStreamHandler { newTitle in
                    DispatchQueue.main.async {
                        if !newTitle.isEmpty {
                            print("✅ Auto AI rename generated title: \"\(newTitle)\"")
                            self.toolbarState.onRenameWithTitle?(newTitle)
                        }
                    }
                },
                type: .title // Make sure to specify title generation type
            )
        }
    }

    private var title: String {
        // If we have a custom title, use it
        if let customTitle = customTitle, !customTitle.isEmpty {
            return customTitle
        }

        // Otherwise fall back to the first line of content
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        if firstLine.isEmpty {
            return "Untitled"
        }
        return firstLine.count > 12 ? firstLine.prefix(12) + "..." : firstLine
    }

    private func deleteCurrentNote() {
        guard let currentId = currentNoteId,
              let fileURL = LocalFileManager.shared.fileURL(for: currentId) else {
            return
        }

        do {
            stopMonitoringFile()
            
            try Foundation.FileManager.default.removeItem(at: fileURL)
            print("Deleted note at \(fileURL.path)")
            
            createNewNote()
            
        } catch {
            print("Error deleting note: \(error)")
            if currentNoteId == currentId {
                startMonitoringFile()
            }
        }
    }

    // Function to handle title double-click
    private func handleTitleDoubleClick() {
        // Start with the current title (custom or derived)
        editedTitle = customTitle ?? text.components(separatedBy: .newlines).first ?? ""
        isEditingTitle = true
        // Set focus to the title field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTitleFieldFocused = true
        }
    }

    // Function to save the edited title
    private func saveTitleEdit() {
        if !editedTitle.isEmpty {
            // Store the custom title
            customTitle = editedTitle

            // Rename the file if we have an existing note
            if let currentId = currentNoteId,
               let oldFileURL = LocalFileManager.shared.fileURL(for: currentId),
               let newFileURL = LocalFileManager.shared.fileURL(for: editedTitle) {

                do {
                    // Check if a file with this title already exists
                    if Foundation.FileManager.default.fileExists(atPath: newFileURL.path) {
                        throw NSError(
                            domain: "FileError", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "A file with this name already exists"])
                    }

                    // Rename the file without changing its content
                    try Foundation.FileManager.default.moveItem(at: oldFileURL, to: newFileURL)

                    // Update currentNoteId to the new title
                    currentNoteId = editedTitle

                    // Start monitoring the new file
                    startMonitoringFile()
                } catch {
                    saveError = error
                    print("Title edit failed:", error.localizedDescription)

                    // withAnimation {
                    //     showToast = true
                    // }
                    // DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    //     withAnimation {
                    //         showToast = false
                    //     }
                    // }
                }
            }
        }

        // Exit editing mode
        isEditingTitle = false
    }

    var body: some View {
        ZStack {
            // macOS 26+ Liquid Glass 适配: 使用自适应背景
            // 在最底部加上背景效果
            if #available(macOS 26.0, *) {
                // macOS 26+: 系统会自动处理 Liquid Glass 效果
                // 使用更轻量的背景让玻璃效果更突出
                Color.clear
                    .edgesIgnoringSafeArea(.all)
            } else {
                // macOS 15-25: 使用传统毛玻璃效果
                VisualEffectBlur(material: .sidebar)
                    .edgesIgnoringSafeArea(.all)
            }

            // 你笔记窗口的主要内容
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        // Title bar with editable title
                        TitleBarView(
                            title: title,
                            isHovered: isHovered,
                            links: links,
                            toolbarState: toolbarState,
                            onNoteSelected: { content, fileURL in
                                loadNoteContent(content, fileURL: fileURL)
                            },
                            onCopy: copyFullContent,
                            onShare: shareFullContent,
                            isEditing: $isEditingTitle,
                            editableTitle: $editedTitle,
                            onTitleCommit: saveTitleEdit
                        )
                        .onTapGesture(count: 2) {
                            handleTitleDoubleClick()
                        }

                        EditorView(text: $text)
                        DownFunctionView(
                            text: text,
                            showCopied: showCopiedStatus,
                            onToggleClaudePanel: {
                                withAnimation {
                                    showClaudeCodePanel.toggle()
                                }
                            }
                        )
                    }

                    if showToast {
                        ToastView(message: saveError == nil ? "Auto Saved" : "Error: \(saveError?.localizedDescription ?? "Unknown error")", isShowing: $showToast)
                            .padding(.bottom, 12)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }

                    // AI Processing Indicator
                    if toolbarState.aiAgentState.isProcessing {
                        AIProcessingIndicator()
                            .padding(.top, 50)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .transition(.opacity.combined(with: .scale))
                            .animation(.easeInOut(duration: 0.3), value: toolbarState.aiAgentState.isProcessing)
                    }
                }
                .background(colorScheme == .light ? Color.white.opacity(0.5) : Color.clear)

                // Claude Code 嵌入式输出面板
                if showClaudeCodePanel {
                    Divider()
                    EmbeddedClaudeCodePanel(
                        isExpanded: $showClaudeCodePanel
                    )
                    .frame(height: 200)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showClaudeCodePanel)
            // AI Confirmation Dialog
            .sheet(isPresented: $toolbarState.showAIConfirmation) {
                if let response = toolbarState.currentIntentResponse {
                    AIConfirmationView(
                        intentResponse: response,
                        onConfirm: { date in
                            toolbarState.confirmAIIntent(updatedDate: date)
                        },
                        onCancel: {
                            toolbarState.cancelAIIntent()
                        }
                    )
                }
            }
        }
        .onChange(of: text) {
            links = LinkDetector.findLinks(in: text)
            toolbarState.isEmpty = text.isEmpty
            toolbarState.currentNoteContent = text
        }
        .onAppear {
            setupAutoSaveTimer()
            setupKeyboardMonitor()
            toolbarState.onAddNew = {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    saveDocument(trigger: .addNew)
                }
                createNewNote()
            }
            toolbarState.isEmpty = text.isEmpty
            toolbarState.onSave = {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    saveDocument(trigger: .addNew)
                    print("document saved before adding new")
                }
            }
            toolbarState.onNoteSelected = { content, fileURL in
                loadNoteContent(content, fileURL: fileURL)
            }
            toolbarState.onRename = {
                handleTitleDoubleClick()
            }
            toolbarState.onDelete = {
                deleteCurrentNote()
            }
            toolbarState.onRenameWithTitle = { newTitle in
                // 确保 currentNoteId 不为 nil
                guard let currentId = currentNoteId,
                      let oldFileURL = LocalFileManager.shared.fileURL(for: currentId),
                      let newFileURL = LocalFileManager.shared.fileURL(for: newTitle) else { return }

                do {
                    try Foundation.FileManager.default.moveItem(at: oldFileURL, to: newFileURL)
                    currentNoteId = newTitle
                    customTitle = newTitle  // 更新自定义标题
                    startMonitoringFile()  // 重新开始监控文件
                } catch {
                    print("Error renaming file: \(error)")
                }
            }
            // AI Agent completion callback - clear note after successful action
            toolbarState.onAIAgentComplete = {
                createNewNote()
            }
            // Claude Code output window callback
            toolbarState.onShowClaudeCodeOutput = {
                withAnimation {
                    showClaudeCodePanel = true
                }
            }
        }
        .ignoresSafeArea()
        .listStyle(.sidebar)
        .onHover { hovering in
            isHovered = hovering
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("autoSaveIntervalDidChange"))
        ) { _ in
            setupAutoSaveTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: ContentView.loadNoteNotification)) { notification in
            if let userInfo = notification.userInfo,
               let content = userInfo["content"] as? String,
               let fileURL = userInfo["fileURL"] as? URL {
                loadNoteContent(content, fileURL: fileURL)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ContentView.showRecentNotesNotification)) { _ in
            toolbarState.openFileDictionary()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
            _ in
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                saveDocument(trigger: .focusLost)
                print("document saved by losing focus")
            }

            // Also exit title editing mode if active
            if isEditingTitle {
                saveTitleEdit()
            }
        }
        // .onReceive(NotificationCenter.default.publisher(for: .storageLocationDidChange)) { _ in
        //     isStorageConfigured = LocalFileManager.shared.isPathConfigured
        // }
        .onDisappear {
            removeKeyboardMonitor()
            stopMonitoringFile()  // 视图消失时停止监听
        }
        .onChange(of: autoSaveInterval) {
            print("Auto-save interval changed to: \(autoSaveInterval)")
            NotificationCenter.default.post(
                name: Notification.Name("autoSaveIntervalDidChange"),
                object: nil
            )
        }
        .onChange(of: toolbarState.showRecentNotes) { newValue in
            if newValue == false {
                NotificationCenter.default.post(
                    name: Notification.Name("RestoreFocusNotification"), object: nil)
            }
        }
        .onChange(of: showClaudeCodePanel) { newValue in
            // 通知窗口控制器更新高度
            let panelHeight: CGFloat = newValue ? 201 : 0
            NotificationCenter.default.post(
                name: Notification.Name("ClaudeCodePanelHeightDidChange"),
                object: nil,
                userInfo: ["height": panelHeight]
            )
        }
    }

    private func setupKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 检查是否按下 Esc 键（keyCode == 53）
            if event.keyCode == 53 {
                if toolbarState.showRecentNotes {
                    toolbarState.showRecentNotes = false
                    return nil
                } else if isEditingTitle {
                    // Cancel title editing on Escape
                    isEditingTitle = false
                    return nil
                } else {
                    NSApp.keyWindow?.performClose(nil)
                    return nil
                }
            }

            // 处理 Command+Shift 组合键
            if event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) {
                if let key = event.charactersIgnoringModifiers?.lowercased() {
                    switch key {
                    case "c":  // Command+Shift+C: 复制全文
                        copyFullContent()
                        return nil
                    case "s":  // Command+Shift+S: 分享全文
                        shareFullContent()
                        return nil
                    case "r":  // Command+Shift+R: 重命名标题
                        handleTitleDoubleClick()
                        return nil
                    default:
                        break
                    }
                }
            }

            if event.modifierFlags.contains(.control) {
                if let key = event.charactersIgnoringModifiers?.lowercased(), key == "b" {
                    withAnimation {
                        showClaudeCodePanel.toggle()
                    }
                    return nil
                }
            }

            return event
        }
    }

    private func copyFullContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation {
            showCopiedStatus = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedStatus = false
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    private func shareFullContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        if let window = NSApp.keyWindow, let contentView = window.contentView {
            let items: [Any] = [text]
            let sharingPicker = NSSharingServicePicker(items: items)
            sharingPicker.show(
                relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }
}

struct ToastView: View {
    let message: String
    @Binding var isShowing: Bool

    var body: some View {
        if isShowing {
            VStack {
                Spacer()
                HStack {
                    // 绿色发光点
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green.opacity(0.5), radius: 4)

                    Text(message)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                // macOS 26+ Liquid Glass 适配: 使用原生 glassEffect
                .modifier(ToastBackgroundModifier())
                .foregroundColor(.primary)
                .transition(.opacity)
                .padding(.bottom, 28)
            }
        }
    }
}

/// Background modifier for ToastView that uses native glassEffect on macOS 26+
private struct ToastBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: 使用原生 Liquid Glass 效果
            content
                .glassEffect(in: .capsule)
        } else {
            // macOS 15-25: 使用传统厚材质
            content
                .background(
                    RoundedRectangle(cornerRadius: 40)
                        .fill(.thickMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 40)
                                .fill(Color.gray.opacity(0.15))
                        )
                )
                .cornerRadius(40)
        }
    }
}

//swiftui textview
struct EditorView: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isEditing: Bool
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    let linkColor = Color.purple
    @State private var isPlaceholderVisible = true
    @State private var lastHeight: CGFloat = 0
    @State private var debounceTimer: Timer?
    @AppStorage("editorFont") private var editorFont: String = "System"

    // 当 editorFont 为 "System" 时，返回自定义 PingFang SC 字体
    private func getEditorFont() -> Font {
        switch editorFont {
        case "Mono":
            return Font.system(size: 14, design: .monospaced)
        case "Heiti":
             return Font.custom("Heiti SC", size: 14)
        case "Serif":
             return Font.custom("Songti SC", size: 14)
        default: // 默认 "System" 或未匹配的值
            return Font.custom("PingFang SC", size: 14.0)
        }
    }

    private func calculateHeight(for text: String, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(string: text)
        let container = NSTextContainer(
            size: CGSize(width: width - 36, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0

        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)

        let range = NSRange(location: 0, length: text.utf16.count)
        storage.addAttributes(
            [
                .font: NSFont(name: "PingFang SC", size: 14.0) ?? NSFont.systemFont(ofSize: 14.0)
            ], range: range)

        manager.ensureLayout(for: container)
        let height = manager.usedRect(for: container).height
        return height + 92  // 80+12 的 padding
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
                    .font(getEditorFont())
                    .disableAutocorrection(true)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.automatic)
                    .background(Color.clear)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .focused($isEditing)
                    .onAppear {
                        // 初始时确保获得焦点
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isEditing = true
                        }
                    }
                    // 当接收到 RestoreFocusNotification 通知时恢复焦点
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: Notification.Name("RestoreFocusNotification"))
                    ) { _ in
                        isEditing = true
                    }
                    .preference(
                        key: ContentHeightPreferenceKey.self,
                        value: calculateHeight(for: text, width: geometry.size.width)
                    )
                    .tint(.purple)
                    .background(
                        KeyEventHandler { event in
                            if event.keyCode != 51 {
                                isPlaceholderVisible = false
                            }
                        }
                    )

                if text.isEmpty {
                    Text(L("Start writing..."))
                        .font(getEditorFont())
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .foregroundColor(.gray.opacity(0.2))
                }
            }
        }
    }
}

struct DownFunctionView: View {
    let text: String
    let showCopied: Bool
    let onToggleClaudePanel: () -> Void
    @AppStorage(AppStorageKeys.showWordCount) private var showWordCount: Bool = AppDefaults.showWordCount
    @ObservedObject private var claudeService = ClaudeCodeService.shared

    private var displayText: String {
        if showCopied {
            return L("Contents Copied")
        } else {
            let count = showWordCount ? TextMetrics.countWords(in: text) : text.count
            let unitKey = showWordCount ? (count != 1 ? "%d Words" : "%d Word") : (count != 0 && count != 1 ? "%d Characters" : "%d Character")
            return String(format: L(unitKey), count)
        }
    }

    private var bgTaskText: String? {
        switch claudeService.state {
        case .running, .preparing:
            return "1 bg-task running..."
        case .waitingForPermission:
            return "1 bg-task waiting..."
        default:
            return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(displayText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .opacity(0.5)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.3), value: showWordCount)
                    .animation(.easeInOut(duration: 0.3), value: showCopied)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !showCopied {
                    withAnimation(.snappy(duration: 0.3)) {
                        showWordCount.toggle()
                    }
                }
            }

            if let taskText = bgTaskText {
                Button(action: onToggleClaudePanel) {
                    HStack(spacing: 4) {
                        if claudeService.state == .waitingForPermission {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        } else {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 8, height: 8)
                        }
                        
                        Text(taskText)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .opacity(0.8)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .center) 
    }
}

struct LinksPopoverView: View {
    let links: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(links, id: \.self) { link in
                Button(action: {
                    if let url = URL(string: link) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text(link)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
}

// struct VisualEffectBlur: NSViewRepresentable {
//     var material: NSVisualEffectView.Material
//     var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
//     var state: NSVisualEffectView.State = .active

//     func makeNSView(context: Context) -> NSVisualEffectView {
//         let view = NSVisualEffectView()
//         view.material = material
//         view.blendingMode = blendingMode
//         view.state = state
//         return view
//     }

//     func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
//         nsView.material = material
//         nsView.blendingMode = blendingMode
//         nsView.state = state
//     }
// }

// MARK: - Embedded Claude Code Panel

/// 嵌入式 Claude Code 输出面板，显示在主窗口下方
struct EmbeddedClaudeCodePanel: View {
    @Binding var isExpanded: Bool
    @ObservedObject var service = ClaudeCodeService.shared
    @State private var showCopiedToast = false

    var body: some View {
        VStack(spacing: 0) {
            // Header bar with collapse/expand button
            panelHeader

            // Output area
            outputArea
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            // Terminal icon and title
            Image(systemName: "terminal")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text("Claude Code")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)

            // State indicator
            stateIndicator

            Spacer()

            // Action buttons
            HStack(spacing: 4) {
                // Copy button
                Button {
                    copyAllOutput()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(service.outputLines.isEmpty)
                .help("Copy output")

                // Clear button
                Button {
                    service.clearOutput()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(service.outputLines.isEmpty || service.state == .running)
                .help("Clear output")

                // Cancel button (only when running)
                if service.state == .running {
                    Button {
                        service.cancel()
                    } label: {
                        Image(systemName: "stop.circle")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.orange)
                    .help("Cancel execution")
                }

                // Close button
                Button {
                    withAnimation {
                        isExpanded = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Close panel")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        .overlay(
            Group {
                if showCopiedToast {
                    Text("Copied")
                        .font(.system(size: 10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    showCopiedToast = false
                                }
                            }
                        }
                }
            }
        )
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        switch service.state {
        case .idle:
            EmptyView()

        case .preparing:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                Text("Preparing...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

        case .running:
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Running")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

        case .waitingForPermission:
            HStack(spacing: 4) {
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 10))
                Text("Waiting for approval")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
            }

        case .completed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 10))
                Text("Done")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

        case .failed(let reason):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 10))
                Text(reason.prefix(20) + (reason.count > 20 ? "..." : ""))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Output Area

    private var outputArea: some View {
        VStack(spacing: 0) {
            // Permission request banner (if any)
            if let permission = service.pendingPermission {
                permissionBanner(for: permission)
            }

            // Scrollable output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if service.outputLines.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(service.outputLines) { line in
                                CompactOutputLineView(line: line)
                                    .id(line.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .background(Color(NSColor.textBackgroundColor).opacity(0.8))
                .onChange(of: service.outputLines.count) { _ in
                    if let last = service.outputLines.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Permission Banner

    private func permissionBanner(for request: ClaudeCodeService.PermissionRequest) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text("Permission Required")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.primary)

                Text(request.displayDescription)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Deny button
            Button {
                service.respondToPermission(allow: false, message: "User denied")
            } label: {
                Text("Deny")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)

            // Allow button
            Button {
                service.respondToPermission(allow: true)
            } label: {
                Text("Allow")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.15))
        .overlay(
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 3),
            alignment: .leading
        )
    }

    private var emptyStateView: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 16))
                .foregroundColor(.secondary.opacity(0.4))

            Text("Output will appear here")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: - Actions

    private func copyAllOutput() {
        let fullOutput = service.outputLines
            .map { $0.content }
            .joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullOutput, forType: .string)

        withAnimation {
            showCopiedToast = true
        }
    }
}

// MARK: - Compact Output Line View

/// 紧凑版输出行视图，适合嵌入式面板
struct CompactOutputLineView: View {
    let line: ClaudeCodeService.OutputLine

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // Type indicator icon
            iconForType(line.type)
                .frame(width: 12, height: 12)
                .padding(.top, 2)

            // Content
            Text(line.content)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(colorForType(line.type))
                .textSelection(.enabled)
                .lineLimit(nil)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .background(backgroundForType(line.type))
        .cornerRadius(2)
    }

    @ViewBuilder
    private func iconForType(_ type: ClaudeCodeService.StreamType) -> some View {
        switch type {
        case .stdout:
            Circle()
                .fill(Color.blue.opacity(0.6))
                .frame(width: 4, height: 4)
        case .stderr:
            Circle()
                .fill(Color.orange.opacity(0.6))
                .frame(width: 4, height: 4)
        case .system:
            Image(systemName: "info.circle.fill")
                .font(.system(size: 8))
                .foregroundColor(.purple.opacity(0.7))
        case .thinking:
            Image(systemName: "brain")
                .font(.system(size: 8))
                .foregroundColor(.cyan.opacity(0.8))
        case .toolUse:
            Image(systemName: "wrench.fill")
                .font(.system(size: 8))
                .foregroundColor(.orange.opacity(0.8))
        case .toolResult:
            Image(systemName: "doc.text.fill")
                .font(.system(size: 8))
                .foregroundColor(.green.opacity(0.8))
        case .assistant:
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 8))
                .foregroundColor(.blue.opacity(0.8))
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
                .foregroundColor(.red.opacity(0.8))
        }
    }

    private func colorForType(_ type: ClaudeCodeService.StreamType) -> Color {
        switch type {
        case .stdout:
            return Color.primary
        case .stderr:
            return Color.orange
        case .system:
            return Color.purple
        case .thinking:
            return Color.cyan.opacity(0.9)
        case .toolUse:
            return Color.orange
        case .toolResult:
            return Color.green.opacity(0.9)
        case .assistant:
            return Color.primary
        case .error:
            return Color.red
        }
    }

    private func backgroundForType(_ type: ClaudeCodeService.StreamType) -> Color {
        switch type {
        case .thinking:
            return Color.cyan.opacity(0.05)
        case .toolUse:
            return Color.orange.opacity(0.05)
        case .toolResult:
            return Color.green.opacity(0.05)
        case .error:
            return Color.red.opacity(0.08)
        default:
            return Color.clear
        }
    }
}

#Preview {
    ContentView()
}

// MARK: - Claude Code Floating Status View
struct ClaudeCodeFloatingStatusView: View {
    @ObservedObject var service = ClaudeCodeService.shared
    let onTap: () -> Void

    private var shouldShow: Bool {
        switch service.state {
        case .running, .preparing, .waitingForPermission:
            return true
        default:
            return false
        }
    }

    private var statusText: String {
        switch service.state {
        case .preparing:
            return "Preparing..."
        case .running:
            return "Running..."
        case .waitingForPermission:
            return "Needs approval"
        default:
            return ""
        }
    }

    private var statusColor: Color {
        switch service.state {
        case .waitingForPermission:
            return .yellow
        default:
            return .green
        }
    }

    var body: some View {
        if shouldShow {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    if service.state == .preparing {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                    } else if service.state == .waitingForPermission {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                    } else {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: statusColor.opacity(0.5), radius: 2)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Claude Code")
                            .font(.system(size: 11, weight: .semibold))
                        Text(statusText)
                            .font(.system(size: 10))
                            .opacity(0.8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(service.state == .waitingForPermission ? Color.yellow.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .padding(20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
