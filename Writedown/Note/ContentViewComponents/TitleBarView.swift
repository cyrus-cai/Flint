import SwiftUI
import SwiftUICore

// MARK: - TitleBar Related Views
struct TitleBarView: View {
    let title: String
    let isHovered: Bool
    let links: [String]
    @ObservedObject var toolbarState: TitleBarToolbarState
    let onNoteSelected: (String, URL?) -> Void
    let onCopy: () -> Void  // 复制内容的回调
    let onShare: () -> Void  // 分享内容的回调
    @Environment(\.colorScheme) private var colorScheme
    @State private var isTitleHovered: Bool = false  // Add specific state for title hover
    @State private var isGeneratingTitle: Bool = false
    @State private var aiButtonScale: CGFloat = 1.0
    @State private var animationProgress: CGFloat = 0
    @State private var showLoadingPulse = false
    @State private var showLoadingText = false

    private func generateObsidianURI(from title: String) -> String? {
        // Get the Obsidian vault path from UserDefaults
        let vaultPath = UserDefaults.standard.string(forKey: "obsidianVaultPath") ?? ""
        guard !vaultPath.isEmpty else { return nil }

        // Extract vault name from the path
        let vaultName = (vaultPath as NSString).lastPathComponent

        // Sanitize the title for URL
        let sanitizedTitle =
            title
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") ?? title

        // Construct the URI
        return "obsidian://open?vault=\(vaultName)&file=\(sanitizedTitle).md"
    }

    var body: some View {
        ZStack {
            // 拖动区域
            DraggableView()
                .frame(height: 32)

            HStack {
                VStack {}.frame(width: 96.0)

                Spacer()
                // 居中标题
                titleSection
                Spacer()

                // 右侧工具栏

                TitleBarToolbar(
                    state: toolbarState,
                    isVisible: isHovered || toolbarState.showRecentNotes
                        || toolbarState.showSettingsList,
                    onNoteSelected: onNoteSelected,
                    links: links,  // Pass links to toolbar
                    title: title,
                    onCopy: onCopy,
                    onShare: onShare
                )
            }

            if toolbarState.showToast {
                NavigationToastView(
                    message: toolbarState.toastMessage,
                    isShowing: $toolbarState.showToast
                )
                .frame(maxWidth: .infinity, alignment: .bottom)
                .padding(.bottom, -4)
            }
        }.onAppear {
            // 在这里设置事件监听器
            let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
                if event.modifierFlags.contains(.command) {
                    if let key = event.charactersIgnoringModifiers?.lowercased() {
                        if key == "f" {
                            if event.modifierFlags.contains(.shift) {
                                // Command+Shift+F: 调用自定义的 openFileDictionary()
                                toolbarState.openFileDictionary()
                            } else {
                                // Command+F: 调用 macOS 自带的页面查找功能
                                NSApp.sendAction(
                                    #selector(NSTextView.performFindPanelAction(_:)), to: nil,
                                    from: nil)
                            }
                            return nil
                        }

                        switch key {
                        case "n", "k", "\r":
                            if !toolbarState.isEmpty {
                                toolbarState.addNew()
                                return nil
                            }
                        // case "]", "】":
                        //     toolbarState.navigateToPreviousNote()
                        //     return nil
                        // case "[", "【":
                        //     toolbarState.navigateToNextNote()
                        //     return nil
                        case ",":  // Command + ,
                            toolbarState.openSettings()
                            return nil
                        default:
                            break
                        }
                    }
                }
                return event
            }

            // 在视图消失时移除监听器
            //            onDisappear {
            //                if let monitor = monitor {
            //                    NSEvent.removeMonitor(monitor)
            //                }
            //            }
        }
    }

    private var titleSection: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .opacity(isHovered ? 0.85 : 0.25)

            // Edit icon that appears on hover
            if isTitleHovered {
                HStack(spacing: 6) {
                    // 编辑按钮 - 添加单独的悬停状态
                    EditButtonWithHover {
                        toolbarState.renameFile()
                    }

                    // AI按钮 - 添加单独的悬停状态
                    if toolbarState.noteContentLength >= 20 && !isGeneratingTitle {
                        SummarizeButtonWithHover {
                            generateTitleWithAI()
                        }
                        .scaleEffect(aiButtonScale)
                    } else if isGeneratingTitle {
                        // 使用与 summarize 相同的光环加载效果
                        ZStack {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.secondary.opacity(0.7), .secondary.opacity(0.5)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                                .frame(width: 16, height: 16)
                                .rotationEffect(Angle(degrees: animationProgress * 360))

                            Circle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 16, height: 16)
                                .scaleEffect(showLoadingPulse ? 1.5 : 1.0)
                                .opacity(showLoadingPulse ? 0 : 0.3)
                                .animation(
                                    Animation.easeInOut(duration: 1.2)
                                        .repeatForever(autoreverses: true),
                                    value: showLoadingPulse
                                )
                        }

                        if showLoadingText {
                            Text("Renaming...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.8))
                                .transition(.opacity)
                        }
                    } else {
                        EmptyView()
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isTitleHovered ?
                    (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)) :
                    Color.clear)
                .animation(.easeInOut(duration: 0.15), value: isTitleHovered)
        )
        .padding(.trailing, 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isTitleHovered = hovering
            }
        }
        .onTapGesture {
            // Add a subtle animation before triggering rename
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                // Optional scale effect could be added here if we had a wrapper view with state

                // Small delay to allow animation to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    toolbarState.renameFile()
                }
            }
        }
    }

    // 新增生成标题的方法
    private func generateTitleWithAI() {
        guard let noteContent = toolbarState.noteContent,
              !noteContent.isEmpty,
              noteContent.count >= 20 else {
            print("📝 AI重命名失败: 内容不足或为空, 长度: \(toolbarState.noteContent?.count ?? 0)")
            return
        }

        print("🔄 开始AI重命名流程, 内容长度: \(noteContent.count)")

        // 添加按钮动画效果
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            aiButtonScale = 0.9
        }

        // 恢复按钮大小
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                aiButtonScale = 1.0
            }
        }

        // 启动摘要动画
        withAnimation(.easeInOut(duration: 0.4)) {
            isGeneratingTitle = true
            showLoadingPulse = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 0.3)) {
                showLoadingText = true
            }
        }

        // 启动进度动画
        withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
            animationProgress = 1.0
        }

        // 创建AI请求处理器
        let streamHandler = TitleStreamHandler { newTitle in
            // 收到标题后更新UI并添加震动效果
            DispatchQueue.main.async {
                // 结束动画
                withAnimation(.easeInOut(duration: 0.4)) {
                    isGeneratingTitle = false
                    showLoadingPulse = false
                    showLoadingText = false
                    animationProgress = 0
                }

                print("✅ AI生成标题完成: \"\(newTitle)\"")

                if !newTitle.isEmpty {
                    // 添加完成时的震动效果
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic,
                                                                   performanceTime: .now)

                    // 记录调用重命名前的回调状态
                    print("🔍 重命名回调状态: \(self.toolbarState.onRenameWithTitle != nil ? "存在" : "不存在")")

                    toolbarState.setGeneratedTitle(newTitle)
                } else {
                    print("⚠️ AI生成的标题为空，取消重命名")
                }
            }
        }

        // 调用API生成标题
        print("🚀 调用API开始生成标题...")
        DoubaoAPI.shared.summarizeWithStream(text: noteContent, delegate: streamHandler)
    }
}

struct TitleBarToolbar: View {
    @ObservedObject var state: TitleBarToolbarState
    let isVisible: Bool
    let onNoteSelected: (String, URL?) -> Void
    let links: [String]  // Add links parameter
    let title: String
    let onCopy: () -> Void  // Add onCopy parameter
    let onShare: () -> Void  // 新增 onShare 参数

    private func openSingleLink() {
        if let url = URL(string: links[0]) {
            NSWorkspace.shared.open(url)
        }
    }

    private func generateObsidianURI(from title: String) -> String? {
        guard !title.isEmpty else { return nil }
        let weekFolder = FileManager.shared.currentWeekDirectory?.lastPathComponent ?? ""
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return "obsidian://open?vault=obsidian&file=Float%2F\(weekFolder)%2F\(encodedTitle)"
    }

    var body: some View {
        HStack(spacing: 4) {

            if !links.isEmpty {
                if links.count == 1 {
                    // Single link - direct button
                    TitleBarButton(
                        icon: .paperclip,
                        action: openSingleLink
                    )
                } else {
                    // Multiple links - show popover
                    TitleBarButton(
                        icon: .paperclip,
                        badgeCount: links.count,  // Pass the count here
                        action: { state.showAttachments = true }
                    )
                    .popover(isPresented: $state.showAttachments) {
                        LinkListView(links: links)
                    }
                }
            }

            TitleBarButton(
                icon: .command,
                action: { state.showSettingsList = true }
            )
            .popover(isPresented: $state.showSettingsList) {
                SettingsListView(
                    onSettings: state.openSettings,
                    onCopy: onCopy,  // Pass onCopy callback
                    onShare: onShare,  // Pass onShare callback
                    title: title
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
                isDisabled: state.isEmpty,  // Add disabled state
                action: { state.addNew() }
            )
        }
        .padding(.horizontal, 8)
        .opacity(isVisible ? 1 : 0)
    }
}

// MARK: - Link List View
struct LinkListView: View {
    let links: [String]
    //    let onSelectLink: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("Attachments")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
                    .padding(.vertical, 8)
                Text("\(links.count)")
                    .font(.system(size: 10, weight: .medium))
                    //                    .foregroundColor(Color.purple)  修改文字颜色为紫色
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(.thinMaterial)  // 使用系统材质实现毛玻璃效果
                            .overlay(
                                Capsule()
                                    .fill(Color.primary.opacity(0.02))  // 叠加浅紫色
                            )
                            .overlay(  // 添加描边
                                Capsule()
                                    .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .frame(minWidth: 12)
            }

            Divider()

            if links.isEmpty {
                Text("No attachments")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(links, id: \.self) { link in
                            LinkItemView(link: link)
                            if link != links.last {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Link Item View
struct LinkItemView: View {
    let link: String
    //    let onSelect: (String) -> Void
    @State private var isHovered = false

    private func openLink() {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    var body: some View {
        Button(action: openLink) {
            HStack {
                Image(systemName: "link")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Text(link)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct BadgeView: View {
    let count: Int

    var displayText: String {
        if count > 99 {
            return "99+"
        }
        return "\(count)"
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: 8, weight: .medium))
            .foregroundColor(Color.purple)  // 修改文字颜色为紫色
            .padding(.horizontal, 3)
            .padding(.vertical, 0.5)
            .background(
                Capsule()
                    .fill(.thinMaterial)  // 使用系统材质实现毛玻璃效果
                    .overlay(
                        Capsule()
                            .fill(Color.purple.opacity(0.02))  // 叠加浅紫色
                    )
                    .overlay(  // 添加描边
                        Capsule()
                            .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1)
                    )
            )
            .frame(minWidth: 12)
    }
}

// MARK: - TitleBar Button
struct TitleBarButton: View {
    let icon: TitleBarIcon
    let action: () -> Void
    let isDisabled: Bool
    let badgeCount: Int?
    @State private var isHovered = false  // 新增状态追踪悬停
    //    @State private var showTooltip = false
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    init(
        icon: TitleBarIcon, isDisabled: Bool = false, badgeCount: Int? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.isDisabled = isDisabled
        self.badgeCount = badgeCount
        self.action = action
    }

    var body: some View {
        ZStack {
            Button(action: action) {
                Image(systemName: icon.systemName)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(iconColor)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(backgroundColor)
                    )
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isHovered = hovering && !isDisabled
                            //                            showTooltip = hovering && !isDisabled
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)

            if let count = badgeCount, count >= 2 {
                BadgeView(count: count)
                    .offset(x: 8, y: -4)
            }
        }
    }

    private var iconColor: Color {
        if isDisabled {
            return .secondary.opacity(0.6)
        }
        // paperclip 图标使用紫色
        if icon == .paperclip {
            return .purple
        }
        return .secondary
    }

    // hover 颜色
    private var backgroundColor: Color {
        if !isHovered {
            return .clear
        }

        if icon == .paperclip {
            //           return .purple.opacity(0.1)  // 紫色半透明背景
            return colorScheme == .dark ? .purple.opacity(0.2) : .purple.opacity(0.1)
        }

        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }
}

// MARK: - TitleBar Icon Enum
enum TitleBarIcon {
    case paperclip
    case command
    case note
    case plus

    var systemName: String {
        switch self {
        case .paperclip:
            return "paperclip"
        case .command:
            return "command"
        case .note:
            return "clock"
        case .plus:
            return "plus"
        }
    }
}

// MARK: - Title Stream Handler
class TitleStreamHandler: SummarizeStreamDelegate {
    var accumulator = ""
    let completion: (String) -> Void

    init(completion: @escaping (String) -> Void) {
        self.completion = completion
    }

    // 更改方法名以匹配协议
    func receivedPartialContent(_ content: String) {
        accumulator += content
    }

    func completed() {
        // 提取不超过30字的摘要作为标题
        let title = String(accumulator.prefix(30)).trimmingCharacters(in: .whitespacesAndNewlines)
        completion(title)
    }

    func failed(with error: Error) {
        print("Title generation failed: \(error.localizedDescription)")
        completion("")
    }
}

// MARK: - Toolbar State Extension
extension TitleBarToolbarState {
    // 笔记内容的长度 - 用于决定是否显示AI按钮
    var noteContentLength: Int {
        return noteContent?.count ?? 0
    }

    // 笔记的当前内容
    var noteContent: String? {
        // 从文件中获取或使用缓存的内容
        return currentNoteContent
    }

    // 应用生成的标题
    func setGeneratedTitle(_ title: String) {
        print("📣 尝试应用标题: \"\(title)\"")

        if let onRenameWithTitle = onRenameWithTitle {
            print("✅ 找到重命名回调，开始执行...")
            onRenameWithTitle(title)
        } else {
            print("⚠️ 重命名回调不存在，无法应用标题")
        }
    }
}

// MARK: - Toolbar State
class TitleBarToolbarState: ObservableObject {
    @Published var showSettingsList = false
    @Published var showAttachments = false
    @Published var isSplitActive = false
    @Published var isListVisible = false
    @Published var showRecentNotes = false
    @Published var showToast = false
    @Published var toastMessage = ""
    @Published var recentNotes: [RecentNote] = []
    @Published var isEmpty: Bool = true
    @Published var currentNoteContent: String? = nil  // 添加当前笔记内容
    private var currentNoteIndex: Int = 0

    var onRename: (() -> Void)?
    var onRenameWithTitle: ((String) -> Void)?  // 添加带有标题参数的重命名回调
    var onDelete: (() -> Void)?
    var onSave: (() -> Void)?
    var onAddNew: (() -> Void)?
    var onNoteSelected: ((String, URL?) -> Void)?

    init() {
        refreshRecentNotes()
    }

    func refreshRecentNotes() {
        recentNotes = FileManager.getRecentNotes()
    }

    func renameFile() {
        onRename?()
    }

    func deleteFile() {
        onDelete?()
    }

    func openFileDictionary() {
        showRecentNotes = true
        refreshRecentNotes()
    }

    func openSettings() {
        WindowManager.shared.createSettingsWindow()
    }

    func addNew() {
        onSave?()  // 保存当前文档
        onAddNew?()
    }

    func navigateToPreviousNote() {
        guard !recentNotes.isEmpty else { return }

        if currentNoteIndex > 0 {
            currentNoteIndex -= 1
            onNoteSelected?(recentNotes[currentNoteIndex].content, recentNotes[currentNoteIndex].fileURL)
        } else {
            showNavigationToast(message: "No more notes")
        }
    }

    func navigateToNextNote() {
        guard !recentNotes.isEmpty else { return }

        if currentNoteIndex < recentNotes.count - 1 {
            currentNoteIndex += 1
            onNoteSelected?(recentNotes[currentNoteIndex].content, recentNotes[currentNoteIndex].fileURL)
        } else {
            showNavigationToast(message: "No more notes")
        }
    }

    private func showNavigationToast(message: String) {
        toastMessage = message
        showToast = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                self.showToast = false
            }
        }
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

struct NavigationToastView: View {
    let message: String
    @Binding var isShowing: Bool

    private var isWarning: Bool {
        message == "No more notes"
    }

    var body: some View {
        if isShowing {
            HStack {
                Circle()
                    .fill(isWarning ? Color.yellow : Color.green)
                    .frame(width: 8, height: 8)
                    .shadow(
                        color: isWarning ? .yellow.opacity(0.5) : .green.opacity(0.5), radius: 4)

                Text(message)
                    .font(.system(size: 12))
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
            .transition(.opacity)
            .frame(maxWidth: .infinity, alignment: .bottom)
        }
    }
}

// 新增编辑按钮组件
struct EditButtonWithHover: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "pencil")
            .font(.system(size: 10))
            .foregroundColor(isHovered ? .primary : .secondary)
            .opacity(isHovered ? 1.0 : 0.8)
            .shadow(color: isHovered ? .secondary.opacity(0.8) : .clear, radius: isHovered ? 3 : 0)
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .transition(.opacity.combined(with: .scale))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
            .onTapGesture {
                action()
            }
    }
}

// 新增摘要按钮组件
struct SummarizeButtonWithHover: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 10))
                .foregroundColor(isHovered ? .primary : .secondary)
                .opacity(isHovered ? 1.0 : 0.8)
                .shadow(color: isHovered ? .secondary.opacity(0.8) : .clear, radius: isHovered ? 3 : 0)
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .transition(.opacity.combined(with: .scale))
                .padding(2) // 添加内边距来扩大点击区域
        }
        .buttonStyle(PlainButtonStyle()) // 使用PlainButtonStyle避免按钮默认样式
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
