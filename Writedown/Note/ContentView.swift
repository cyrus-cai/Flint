import Combine
//import SwiftDown
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
            // 匹配完整的 URL（包含或不包含 www.）
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
    // @State private var isStorageConfigured = LocalFileManager.shared.isPathConfigured
    @State private var fileMonitor: DispatchSourceFileSystemObject?
    @AppStorage(AppStorageKeys.autoSaveInterval) private var autoSaveInterval: TimeInterval = AppDefaults.autoSaveInterval
    @State private var autoSaveTimer: AnyCancellable?
    @State private var keyboardMonitor: Any?
    @State private var showCopyToast = false
    @State private var showCopiedStatus = false

    static let loadNoteNotification = Notification.Name("LoadNoteNotification")

    // New states for title editing
    @State private var isEditingTitle = false
    @State private var editedTitle = ""

    // Add a new state variable to track the custom title
    @State private var customTitle: String?

    // Add a focus state to track and control text field focus
    @FocusState private var isTitleFieldFocused: Bool

    // Add this property to track content hash
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
        stopMonitoringFile()  // 先停止之前的监听

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
        guard !text.isEmpty else { return }

        print("Saving document with trigger: \(trigger)")

        do {
            // Case 1: We have an existing note (currentNoteId exists)
            if let currentId = currentNoteId,
               let fileURL = LocalFileManager.shared.fileURL(for: currentId) {

                // For title edit, we already handled the file renaming in saveTitleEdit()
                if trigger == .titleEdit {
                    // Do nothing here - file was already renamed
                    return
                } else {
                    // Always update the existing file for the same note
                    print("Updating existing note at \(fileURL.path)")
                    try text.write(to: fileURL, atomically: true, encoding: .utf8)
                    lastSaveDate = Date()
                    startMonitoringFile()
                }
            }
            // Case 2: This is a new note (no currentNoteId)
            else {
                let documentTitle = title  // Calculate title for new note

                guard let fileURL = LocalFileManager.shared.fileURL(for: documentTitle) else {
                    throw NSError(
                        domain: "FileError", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid file URL"])
                }

                // Check if a file with this title already exists
                if Foundation.FileManager.default.fileExists(atPath: fileURL.path) {
                    // Generate a unique title by adding a timestamp
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

            // Show error toast for title edit failures
            // if trigger == .titleEdit {
            //     withAnimation {
            //         showToast = true
            //     }
            //     DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            //         withAnimation {
            //             showToast = false
            //         }
            //     }
            // }
        }
    }

    func loadNoteContent(_ content: String, fileURL: URL? = nil) {
        // Save current content before loading new note
        if !text.isEmpty {
            saveDocument(trigger: .addNew)
        }

        text = content

        // If a fileURL is provided (from history list), use it to set currentNoteId
        if let url = fileURL {
            // Extract the filename without extension to use as currentNoteId
            let filename = url.deletingPathExtension().lastPathComponent
            currentNoteId = filename

            // Set the custom title to the filename
            customTitle = filename

            do {
                let attributes = try Foundation.FileManager.default.attributesOfItem(
                    atPath: url.path)
                lastSaveDate = attributes[.modificationDate] as? Date
                // Start monitoring the loaded file
                startMonitoringFile()
            } catch {
                print("Failed to get file modification time: \(error.localizedDescription)")
            }
        }
        // If no fileURL is provided but we have a currentNoteId, try to use that
        else if let currentId = currentNoteId,
            let fileURL = LocalFileManager.shared.fileURL(for: currentId)
        {
            // Set the custom title to the currentNoteId
            customTitle = currentId

            do {
                let attributes = try Foundation.FileManager.default.attributesOfItem(
                    atPath: fileURL.path)
                lastSaveDate = attributes[.modificationDate] as? Date
                // Start monitoring the loaded file
                startMonitoringFile()
            } catch {
                print("Failed to get file modification time: \(error.localizedDescription)")
            }
        }
        // If neither fileURL nor currentNoteId is available, treat as new note
        else {
            currentNoteId = nil
            customTitle = nil
        }

        // Set content hash to prevent auto-renaming of existing notes
        if !content.isEmpty {
            contentHashForAIRename = content.prefix(100).hashValue
        }
    }

    private func createNewNote() {
        stopMonitoringFile()  // 停止监听当前文件
        text = ""
        currentNoteId = nil
        customTitle = nil
        contentHashForAIRename = 0  // Reset the content hash for new notes
    }

    private func setupAutoSaveTimer() {
        print("Setting up auto-save timer with interval: \(autoSaveInterval)")
        autoSaveTimer?.cancel()

        autoSaveTimer = Timer.publish(every: autoSaveInterval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if !text.isEmpty {
                    saveDocument(trigger: .timer)
                    print("document saved with interval: \(autoSaveInterval)s")

                    // Check if text just exceeded 20 characters and AI rename is enabled
                    if text.count >= 20 && UserDefaults.standard.bool(forKey: "enableAIRename") {
                        // Generate a content fingerprint to track this note regardless of title changes
                        let currentContentHash = text.prefix(100).hashValue

                        // Only trigger AI rename if we haven't renamed this specific content yet
                        // AND the hash is different from our tracked hash (prevents multiple renames after editing)
                        if contentHashForAIRename == 0 {
                            // First time seeing content over 20 chars - track this and rename
                            contentHashForAIRename = currentContentHash

                            // Trigger AI rename after a short delay
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
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    // Title bar with editable title
                    if isEditingTitle {
                        // Editable title field
                        HStack {
                            Spacer()
                            TextField("Enter title", text: $editedTitle, onCommit: saveTitleEdit)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 200)
                                .padding(.vertical, 4)
                                .onExitCommand {
                                    isEditingTitle = false
                                }
                                .focused($isTitleFieldFocused)
                                .onChange(of: editedTitle) { newValue in
                                    // 限制标题最大长度为25个字符
                                    if newValue.count > 30 {
                                        editedTitle = String(newValue.prefix(30))
                                    }
                                }
                            Spacer()
                        }
                        .frame(height: 32)
                        .background(Color.clear)
                    } else {
                        // Regular title bar
                        TitleBarView(
                            title: title,
                            isHovered: isHovered,
                            links: links,
                            toolbarState: toolbarState,
                            onNoteSelected: { content, fileURL in
                                loadNoteContent(content, fileURL: fileURL)
                            },
                            onCopy: copyFullContent,
                            onShare: shareFullContent)
                            .onTapGesture(count: 2) {
                                handleTitleDoubleClick()
                            }
                    }

                    EditorView(text: $text)
                    DownFunctionView(count: text.count, links: links, showCopied: showCopiedStatus)
                }

                if showToast {
                    ToastView(message: saveError == nil ? "Auto Saved" : "Error: \(saveError?.localizedDescription ?? "Unknown error")", isShowing: $showToast)
                        .padding(.bottom, 12)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .background(Color.clear) // 确保内部视图背景透明
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
                if !text.isEmpty {
                    saveDocument(trigger: .addNew)
                }
                createNewNote()
            }
            toolbarState.isEmpty = text.isEmpty
            toolbarState.onSave = {
                if !text.isEmpty {
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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
            _ in
            if !text.isEmpty {
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
                    Text("Start writing...")
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
    let count: Int
    let links: [String]
    let showCopied: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(
                showCopied
                    ? "Contents Copied" : "\(count) Character\(count != 0 && count != 1 ? "s" : "")"
            )
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
            .opacity(0.5)
            .animation(.easeInOut(duration: 0.3), value: showCopied)
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

#Preview {
    ContentView()
}
