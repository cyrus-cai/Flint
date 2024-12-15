import SwiftDown
import SwiftUI

struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 106
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
        print("window height changed", value)

    }
}

struct LinkDetector {
    static func findLinks(in text: String) -> [String] {
        let patterns = [
            "(https?://(?:www\\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\\.[^\\s]{2,})",
            "(www\\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\\.[^\\s]{2,})",
            "(https?://(?:www\\.|(?!www))[a-zA-Z0-9]+\\.[^\\s]{2,})",
            "(www\\.[a-zA-Z0-9]+\\.[^\\s]{2,})",
        ]

        // Use an array to store matches with their positions
        var linkMatches: [(link: String, position: Int)] = []

        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let matches = regex.matches(
                    in: text, options: [], range: NSRange(location: 0, length: text.count))

                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let link = String(text[range])
                        // Store both the link and its position in the text
                        linkMatches.append((link: link, position: match.range.location))
                    }
                }
            } catch {
                print("正则表达式错误: \(error)")
            }
        }

        // Remove duplicates while preserving the earliest occurrence of each link
        var seenLinks = Set<String>()
        var orderedLinks: [(link: String, position: Int)] = []

        for match in linkMatches {
            if !seenLinks.contains(match.link) {
                seenLinks.insert(match.link)
                orderedLinks.append(match)
            }
        }

        // Sort by position in the original text
        orderedLinks.sort { $0.position < $1.position }

        // Return just the links in their sorted order
        return orderedLinks.map { $0.link }
    }
}

struct ContentView: View {
    @State private var text = ""
    @State private var links: [String] = []
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme  // 添加对当前颜色方案的引用
    @StateObject private var toolbarState = TitleBarToolbarState()
    @State private var showToast = false

    @State private var lastSaveDate: Date?
    @State private var saveError: Error?

    enum SaveTrigger {
        case timer
        case focusLost
        case addNew
    }

    private func saveDocument(trigger: SaveTrigger) {
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

        if trigger == .addNew {
            withAnimation {
                showToast = true
            }
            // 3秒后自动隐藏
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    showToast = false
                }
            }
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

                //                VStack(spacing: 0) {
                TitleBarView(
                    title: title, isHovered: isHovered, links: links, toolbarState: toolbarState,
                    onNoteSelected: loadNoteContent)
                EditorView(text: $text)

                DownFunctionView(count: text.count, links: links)
                //                    .frame(height: 32)
                //                }

            }
            if showToast {
                VStack {
                    Spacer()
                    ToastView(message: "Auto Saved", isShowing: $showToast)
                        .padding(.bottom, 12)
                }
                .transition(.opacity)
            }
        }
        .onChange(of: text) {
            links = LinkDetector.findLinks(in: text)
            toolbarState.isEmpty = text.isEmpty
        }
        .onAppear {
            toolbarState.onAddNew = { text = "" }
            toolbarState.isEmpty = text.isEmpty
            toolbarState.onSave = {
                if !text.isEmpty {
                    saveDocument(trigger: .addNew)
                    print("document saved before adding new")
                }
            }
        }
        .ignoresSafeArea()
        .listStyle(.sidebar)
        .onHover { hovering in
            isHovered = hovering
        }
        .onReceive(autoSaveTimer) { _ in
            if !text.isEmpty {
                saveDocument(trigger: .timer)
                print("document saved")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
            _ in
            if !text.isEmpty {
                saveDocument(trigger: .focusLost)
                print("document saved by losing focus")
            }
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

        // 计算实际需要的高度
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
                        print("确保视图出现后立即获取焦点")
                        // 确保视图出现后立即获取焦点
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isEditing = true
                        }
                    }
                    .onHover { _ in
                        print("确保 hover 后立即获取焦点")
                        // 确保视图出现后立即获取焦点
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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

//struct EditorView: View {
//    @Binding var text: String
//    @Environment(\.colorScheme) private var colorScheme
//    @FocusState private var isEditing: Bool
//    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
//    let linkColor = Color.purple
//    @State private var isPlaceholderVisible = true
//    @State private var lastHeight: CGFloat = 0
//    @State private var debounceTimer: Timer?
//    @State private var attributedText: NSAttributedString = NSAttributedString()
//
//    private func calculateHeight(for text: String, width: CGFloat) -> CGFloat {
//        let storage = NSTextStorage(string: text)
//        let container = NSTextContainer(size: CGSize(width: width - 36, height: .greatestFiniteMagnitude))
//        container.lineFragmentPadding = 0
//
//        let manager = NSLayoutManager()
//        manager.addTextContainer(container)
//        storage.addLayoutManager(manager)
//
//        let range = NSRange(location: 0, length: text.utf16.count)
//        storage.addAttributes([
//            .font: NSFont(name: "PingFang SC", size: 14.0) ?? NSFont.systemFont(ofSize: 14.0)
//        ], range: range)
//
//        manager.ensureLayout(for: container)
//        let height = manager.usedRect(for: container).height
//
//        return height + 92
//    }
//
//    private func updateAttributedText(_ text: String) {
//        let attributedString = NSMutableAttributedString(string: text)
//
//        // 基本文本样式
//        let baseAttributes: [NSAttributedString.Key: Any] = [
//            .font: NSFont(name: "PingFang SC", size: 14.0) ?? NSFont.systemFont(ofSize: 14.0),
//            .foregroundColor: colorScheme == .dark ? NSColor.white : NSColor.black
//        ]
//        attributedString.addAttributes(baseAttributes, range: NSRange(location: 0, length: text.count))
//
//        // 链接匹配模式
//        let patterns = [
//            "(https?://(?:www\\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\\.[^\\s]{2,})",
//            "(www\\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\\.[^\\s]{2,})",
//            "(https?://(?:www\\.|(?!www))[a-zA-Z0-9]+\\.[^\\s]{2,})",
//            "(www\\.[a-zA-Z0-9]+\\.[^\\s]{2,})"
//        ]
//
//        for pattern in patterns {
//            do {
//                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
//                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
//
//                for match in matches {
//                    // 链接样式
//                    let urlString = text[Range(match.range, in: text)!]
//                    attributedString.addAttributes([
//                        .foregroundColor: NSColor(linkColor),
//                        .underlineStyle: NSUnderlineStyle.single.rawValue,
//                        .link: urlString,
//                        .cursor: NSCursor.pointingHand
//                    ], range: match.range)
//                }
//            } catch {
//                print("正则表达式错误: \(error)")
//            }
//        }
//
//        self.attributedText = attributedString
//    }
//
//    struct KeyEventHandler: NSViewRepresentable {
//        let onKeyDown: (NSEvent) -> Void
//
//        func makeNSView(context: Context) -> NSView {
//            let view = KeyView()
//            view.onKeyDown = onKeyDown
//            return view
//        }
//
//        func updateNSView(_ nsView: NSView, context: Context) {}
//
//        class KeyView: NSView {
//            var onKeyDown: ((NSEvent) -> Void)?
//
//            override var acceptsFirstResponder: Bool { true }
//
//            override func keyDown(with event: NSEvent) {
//                onKeyDown?(event)
//                super.keyDown(with: event)
//            }
//        }
//    }
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .topLeading) {
//                CustomTextEditor(text: $text,
//                               isEditing: isEditing,
//                               attributedText: attributedText)
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
//                    .scrollContentBackground(.hidden)
//                    .scrollIndicators(.automatic)
//                    .background(Color.clear)
//                    .padding(.horizontal, 16)
//                    .padding(.top, 8)
//                    .focused($isEditing)
//                    .onAppear {
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                            print("isEditing = true1")
//                            isEditing = true
//                            updateAttributedText(text)
//                        }
//                    }
//                    .preference(
//                        key: ContentHeightPreferenceKey.self,
//                        value: calculateHeight(for: text, width: geometry.size.width)
//                    )
//                    .tint(.purple)
//                    .background(
//                        KeyEventHandler { event in
//                            if event.keyCode != 51 {
//                                isPlaceholderVisible = false
//                            }
//                        }
//                    )
//                    .onChange(of: text) {
//                        if text.isEmpty {
//                            isPlaceholderVisible = true
//                        }
//                        updateAttributedText(text)
//                    }
//                    .onHover { hovering in
//                        if hovering {
//                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                                print("isEditing = true")
//                                isEditing = true
//                            }
//                        }
//                    }
//
//                if text.isEmpty {
//                    Text("Start writing...")
//                        .font(.custom("PingFang SC", size: 14.0))
//                        .padding(.horizontal, 20)
//                        .padding(.top, 8)
//                        .foregroundColor(.gray.opacity(0.2))
//                }
//            }
//        }
//    }
//}

// CustomTextEditor Implementation
// 自定义的 NSTextView 子类，用于处理链接点击
//class ClickableTextView: NSTextView {
//    override func mouseDown(with event: NSEvent) {
//        let point = convert(event.locationInWindow, from: nil)
//        let index = characterIndex(for: point)
//
//        // 检查索引是否有效
//        guard index < attributedString().length else {
//            super.mouseDown(with: event)
//            return
//        }
//
//        // 检查点击位置是否有链接
//        if let attr = attributedString().attribute(.link, at: index, effectiveRange: nil) as? String {
//            if let url = URL(string: attr) {
//                print("url is", url)
//                NSWorkspace.shared.open(url)
//                return
//            }
//        }
//
//        super.mouseDown(with: event)
//    }
//}

//struct CustomTextEditor: NSViewRepresentable {
//    @Binding var text: String
//    var isEditing: Bool
//    var attributedText: NSAttributedString
//
//    func makeNSView(context: Context) -> NSTextView {
//        let textView = ClickableTextView()
////        textView.isRichText = true
//        textView.allowsUndo = true
//        textView.font = .init(name: "PingFang SC", size: 14)
//        textView.delegate = context.coordinator
//        textView.backgroundColor = .clear
//        textView.isEditable = true
//        textView.drawsBackground = false
//
//        // 启用链接点击
//        textView.isSelectable = true
//        textView.linkTextAttributes = [
//            .foregroundColor: NSColor(Color.purple),
//            .underlineStyle: NSUnderlineStyle.single.rawValue,
//            .cursor: NSCursor.pointingHand
//        ]
//
//        // 设置自动布局
//        textView.translatesAutoresizingMaskIntoConstraints = false
//        textView.autoresizingMask = [.width, .height]
//
//        // Set insertion point color
//        textView.insertionPointColor = NSColor(Color.purple)
//
//      // Set selection color
//      textView.selectedTextAttributes = [
//          .backgroundColor: NSColor(Color.purple).withAlphaComponent(0.2)
//      ]
//
//        return textView
//    }
//
//    func updateNSView(_ nsView: NSTextView, context: Context) {
//           if nsView.attributedString() != attributedText {
//               nsView.textStorage?.setAttributedString(attributedText)
//           }
//       }
//
//
//    func makeCoordinator() -> Coordinator {
//        Coordinator(self)
//    }
//
//    class Coordinator: NSObject, NSTextViewDelegate {
//        var parent: CustomTextEditor
//
//        init(_ parent: CustomTextEditor) {
//            self.parent = parent
//        }
//
//        func textDidChange(_ notification: Notification) {
//            guard let textView = notification.object as? NSTextView else { return }
//            parent.text = textView.string
//        }
//    }
//}

//struct CustomTextEditor: NSViewRepresentable {
//    @Binding var text: String
//    var isEditing: Bool
//    var attributedText: NSAttributedString
//
//    class Coordinator: NSObject, NSTextViewDelegate {
//        var parent: CustomTextEditor
//        private var updateWorkItem: DispatchWorkItem?
//
//        init(_ parent: CustomTextEditor) {
//            self.parent = parent
//        }
//
//        func textDidChange(_ notification: Notification) {
//            guard let textView = notification.object as? NSTextView else { return }
//            // 立即更新纯文本
//            parent.text = textView.string
//
//            // 取消之前的延迟更新
//            updateWorkItem?.cancel()
//
//            // 创建新的延迟更新
//            let workItem = DispatchWorkItem { [weak self, weak textView] in
//                guard let textView = textView else { return }
//                let selectedRanges = textView.selectedRanges
//
//                // 在主线程更新
//                DispatchQueue.main.async {
//                    // 如果文本视图正在编辑，不更新
//                    guard textView.window?.firstResponder != textView else { return }
//
//                    // 更新富文本内容
//                    textView.textStorage?.setAttributedString(self?.parent.attributedText ?? NSAttributedString())
//
//                    // 恢复光标位置
//                    if let firstRange = selectedRanges.first?.rangeValue,
//                       firstRange.location <= textView.string.count {
//                        textView.setSelectedRanges(selectedRanges,
//                                                 affinity: .downstream,
//                                                 stillSelecting: false)
//                    }
//                }
//            }
//
//            updateWorkItem = workItem
//
//            // 延迟0.5秒执行更新
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
//        }
//    }
//
//    func makeCoordinator() -> Coordinator {
//        Coordinator(self)
//    }
//
//    func makeNSView(context: Context) -> NSTextView {
//        let textView = ClickableTextView()
//        textView.allowsUndo = true
//        textView.font = .init(name: "PingFang SC", size: 14)
//        textView.delegate = context.coordinator
//        textView.backgroundColor = .clear
//        textView.isEditable = true
//        textView.drawsBackground = false
//        textView.isSelectable = true
//
//        textView.linkTextAttributes = [
//            .foregroundColor: NSColor(Color.purple),
//            .underlineStyle: NSUnderlineStyle.single.rawValue,
//            .cursor: NSCursor.pointingHand
//        ]
//
//        textView.insertionPointColor = NSColor(Color.purple)
//        textView.selectedTextAttributes = [
//            .backgroundColor: NSColor(Color.purple).withAlphaComponent(0.2)
//        ]
//
//        return textView
//    }
//
//    func updateNSView(_ nsView: NSTextView, context: Context) {
//        // 只在文本视图未获得焦点时更新
//        if nsView.window?.firstResponder != nsView {
//            let selectedRanges = nsView.selectedRanges
//            nsView.textStorage?.setAttributedString(attributedText)
//
//            // 恢复选择范围
//            if let firstRange = selectedRanges.first?.rangeValue,
//               firstRange.location <= attributedText.length {
//                nsView.setSelectedRanges(selectedRanges,
//                                       affinity: .downstream,
//                                       stillSelecting: false)
//            }
//        }
//    }
//}

struct DownFunctionView: View {
    let count: Int
    let links: [String]
    @State private var showTooltip = false
    @State private var showLinksPopover = false

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count) character\(count != 0 && count != 1 ? "s" : "")")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
                .opacity(0.5)
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
