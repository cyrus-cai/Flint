import SwiftUI
import SwiftUICore

// MARK: - TitleBar Related Views
struct TitleBarView: View {
    let title: String
    let isHovered: Bool
    let links: [String]
    @ObservedObject var toolbarState: TitleBarToolbarState
    let onNoteSelected: (String) -> Void  // 新增参数

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
                    title: title
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
                    switch event.charactersIgnoringModifiers {
                    case "f", "h":
                        toolbarState.openFileDictionary()
                        return nil
                    case "n", "k", "\r":
                        if !toolbarState.isEmpty {
                            toolbarState.addNew()
                            return nil
                        }
                    case "o":
                        if title != "Untitled" && !title.isEmpty,
                            let uri = generateObsidianURI(from: title),
                            let url = URL(string: uri)
                        {
                            NSWorkspace.shared.open(url)
                            return nil
                        }
                    case "]", "】":
                        toolbarState.navigateToPreviousNote()
                        return nil
                    case "[", "【":
                        toolbarState.navigateToNextNote()
                        return nil
                    default:
                        break
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
    let links: [String]  // Add links parameter
    let title: String

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
                    //                    onRename: state.renameFile,
                    //                    onDelete: state.deleteFile,
                    onSettings: state.openSettings,
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
    @Published var isEmpty: Bool = true  // Add isEmpty state
    private var currentNoteIndex: Int = 0

    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSave: (() -> Void)?
    var onAddNew: (() -> Void)?
    var onNoteSelected: ((String) -> Void)?

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

        let newIndex = max(currentNoteIndex - 1, 0)
        guard newIndex != currentNoteIndex else {
            showNavigationToast(message: "No more notes")
            return
        }
        currentNoteIndex = newIndex
        onNoteSelected?(recentNotes[currentNoteIndex].content)
    }

    func navigateToNextNote() {
        guard !recentNotes.isEmpty else { return }

        let newIndex = min(currentNoteIndex + 1, recentNotes.count - 1)
        guard newIndex != currentNoteIndex else {
            showNavigationToast(message: "No more notes")
            return
        }
        currentNoteIndex = newIndex
        onNoteSelected?(recentNotes[currentNoteIndex].content)
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

    var body: some View {
        if isShowing {
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: .green.opacity(0.5), radius: 4)

                Text(message)
                    .font(.system(size: 12))
            }
            .padding(10)
            .background(.thinMaterial)
            .cornerRadius(8)
            .transition(.opacity)
            .frame(maxWidth: .infinity, alignment: .bottom)
        }
    }
}
