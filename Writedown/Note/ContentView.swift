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
    // @State private var isStorageConfigured = FileManager.shared.isPathConfigured
    @State private var fileMonitor: DispatchSourceFileSystemObject?
    @AppStorage("autoSaveInterval") private var autoSaveInterval: TimeInterval = 10
    @State private var autoSaveTimer: AnyCancellable?
    @State private var keyboardMonitor: Any?
    @State private var showCopyToast = false
    @State private var showCopiedStatus = false

    enum SaveTrigger {
        case timer
        case focusLost
        case addNew
    }

    private func startMonitoringFile() {
        stopMonitoringFile()  // 先停止之前的监听

        guard let currentId = currentNoteId,
            let fileURL = FileManager.shared.fileURL(for: currentId)
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
        let documentTitle = title  // 计算标题，只处理一次

        do {
            // 如果已存在当前笔记，则直接覆盖写入，而不是删除原文件
            if let currentId = currentNoteId,
                let fileURL = FileManager.shared.fileURL(for: currentId)
            {
                print("Overwriting existing file at \(fileURL.path)")
            }

            guard let fileURL = FileManager.shared.fileURL(for: documentTitle) else {
                throw NSError(
                    domain: "FileError", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid file URL"])
            }

            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            currentNoteId = documentTitle
            lastSaveDate = Date()
            startMonitoringFile()

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

    func loadNoteContent(_ content: String) {
        text = content
        if let currentId = currentNoteId,
            let fileURL = FileManager.shared.fileURL(for: currentId)
        {
            do {
                let attributes = try Foundation.FileManager.default.attributesOfItem(
                    atPath: fileURL.path)
                lastSaveDate = attributes[.modificationDate] as? Date
                // 开始监听新加载的文件
                startMonitoringFile()
            } catch {
                print("获取文件修改时间失败：\(error.localizedDescription)")
            }
        }
    }

    private func createNewNote() {
        stopMonitoringFile()  // 停止监听当前文件
        text = ""
        currentNoteId = nil
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
                }
            }
    }

    private var title: String {
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        if firstLine.isEmpty {
            return "Untitled"
        }
        return firstLine.count > 12 ? firstLine.prefix(12) + "..." : firstLine
    }

    var body: some View {
        ZStack(alignment: .top) {
            // if isStorageConfigured {
            VStack(spacing: 0) {
                TitleBarView(
                    title: title,
                    isHovered: isHovered,
                    links: links,
                    toolbarState: toolbarState,
                    onNoteSelected: loadNoteContent,
                    onCopy: copyFullContent)
                EditorView(text: $text)
                DownFunctionView(count: text.count, links: links, showCopied: showCopiedStatus)
            }

            if showToast {
                ToastView(message: "Auto Saved", isShowing: $showToast)
                    .padding(.bottom, 12)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .onChange(of: text) {
            links = LinkDetector.findLinks(in: text)
            toolbarState.isEmpty = text.isEmpty
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
            toolbarState.onNoteSelected = { content in
                loadNoteContent(content)
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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
            _ in
            if !text.isEmpty {
                saveDocument(trigger: .focusLost)
                print("document saved by losing focus")
            }
        }
        // .onReceive(NotificationCenter.default.publisher(for: .storageLocationDidChange)) { _ in
        //     isStorageConfigured = FileManager.shared.isPathConfigured
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
    }

    private func setupKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Handle ESC key
            if event.keyCode == 53 {
                if let window = NSApp.keyWindow {
                    window.orderOut(nil)
                    return nil
                }
            }

            // Handle Command+Shift+C
            if event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) {
                if let key = event.charactersIgnoringModifiers?.lowercased(), key == "c" {
                    copyFullContent()
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
                .background(.gray.opacity(0.15))
                .background(.thickMaterial)
                .foregroundColor(.primary)
                .cornerRadius(40)
                .transition(.opacity)
                .padding(.bottom, 28)
            }
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

    private func calculateHeight(for text: String, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(string: text)
        let container = NSTextContainer(
            size: CGSize(width: width - 36, height: .greatestFiniteMagnitude))  // 32为左右padding总和
        container.lineFragmentPadding = 0

        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)

        // 设置文本属性
        let range = NSRange(location: 0, length: text.utf16.count)
        storage.addAttributes(
            [
                .font: NSFont(name: "PingFang SC", size: 14.0) ?? NSFont.systemFont(ofSize: 14.0)
            ], range: range)

        // 计算实际需要高度
        manager.ensureLayout(for: container)
        let height = manager.usedRect(for: container).height

        // 加上padding的高度
        return height + 92  // 80+12
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
                    .background(Color.clear)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .focused($isEditing)
                    .onAppear {
                        //                        print("确保视图出现后立即获取焦点")
                        // 确保视图出现后立即获取焦点
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isEditing = true
                        }
                    }
                    .onHover { _ in
                        //                        print("确保 hover 后立即获取焦点")
                        // 确保视图出现后立即获取焦点
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isEditing = true
                        }
                    }

                    .preference(
                        key: ContentHeightPreferenceKey.self,
                        value: calculateHeight(for: text, width: geometry.size.width)
                    )
                    .tint(.purple)  // 设置光标颜色
                    .background(
                        KeyEventHandler { event in
                            if event.keyCode != 51 {  // 51 是删除键的 keyCode
                                isPlaceholderVisible = false
                            }
                        }
                    )
                    .onChange(of: text) {
                        if text.isEmpty {
                            isPlaceholderVisible = true
                        }
                    }
                    .onReceive(
                        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
                    ) { _ in
                        print("receive focus change")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isEditing = true
                        }
                    }

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


struct DownFunctionView: View {
    let count: Int
    let links: [String]
    let showCopied: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(showCopied ? "Contents Copied" : "\(count) Character\(count != 0 && count != 1 ? "s" : "")")
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

#Preview {
    ContentView()
}
