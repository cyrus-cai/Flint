import Foundation
import SwiftUI

//// MARK: - File Manager Extension
extension FileManager {
    static func getRecentNotes() -> [RecentNote] {
        do {
            let notes = FileManager.shared.getAllNotes()
            let resourceKeys = Set([URLResourceKey.contentModificationDateKey])

            var notesWithDates: [(URL, Date)] = []
            for url in notes {
                let resourceValues = try url.resourceValues(forKeys: resourceKeys)
                if let modificationDate = resourceValues.contentModificationDate {
                    notesWithDates.append((url, modificationDate))
                }
            }

            // Sort and limit
            notesWithDates.sort { $0.1 > $1.1 }
            let recentURLs = notesWithDates

            // Convert to RecentNote objects
            var recentNotes: [RecentNote] = []
            for (url, date) in recentURLs {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    let lines = content.components(separatedBy: .newlines)
                    let title = lines.first?.isEmpty ?? true ? "Untitled" : lines[0]

                    let note = RecentNote(
                        title: title,
                        content: content,
                        lastModified: date,
                        fileURL: url
                    )
                    recentNotes.append(note)
                }
            }

            return recentNotes
        } catch {
            print("Error getting recent notes: \(error)")
            return []
        }
    }
}

// MARK: - Recent Note Model
struct RecentNote: Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let lastModified: Date
    let fileURL: URL
}

enum TimeGroup: String {
    case last15Min = "⌛️ Last 15 min"
    case last1Hour = "🕛 Last 1 hour"
    case thisMorning = "🌞 This morning"
    case thisAfternoon = "🌆 This afternoon"
    case yesterday = "1️⃣ Yesterday"
    case thisWeek = "◀️ This Week"
    case older = "⏪️ Earlier"
}

struct GroupedNotes {
    let group: TimeGroup
    let notes: [RecentNote]
}

class RecentNotesViewModel: ObservableObject {
    @Published var notes: [RecentNote] = []
    @Published var searchText: String = ""
    @Published var selectedNoteIndex: Int? = nil
    @Published var hoveredNoteIndex: Int? = nil
    @Published var currentNoteIndex: Int? = nil
    @Published private var isHoverEnabled = true
    @Published var showArchiveToast = false
    @Published var groupSummaries: [TimeGroup: String] = [:] {
        didSet {
            print("📊 GroupSummaries updated: \(groupSummaries)")
            // 强制触发 UI 更新
            objectWillChange.send()
        }
    }
    @Published var showingSummaries: [TimeGroup: Bool] = [:]
    @Published var archivedNotes: [RecentNote] = []
    @Published var showUndoArchiveToast = false
    @Published var archivedNotesCount = 0

    init() {
        notes = FileManager.getRecentNotes()
        if !notes.isEmpty {
            currentNoteIndex = 0
        }
    }

    var filteredNotes: [RecentNote] {
        if searchText.isEmpty {
            return notes
        }
        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(searchText)
                || note.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    func deleteNote(_ note: RecentNote) {
        do {
            // 1. 首先确保我们要删除的是正确的文件
            let fileToDelete = note.fileURL
            print("Attempting to delete file at: \(fileToDelete.path)")

            // 2. 验证文件仍然存在
            let fileManager = Foundation.FileManager.default
            guard fileManager.fileExists(atPath: fileToDelete.path) else {
                print("File does not exist at path: \(fileToDelete.path)")
                return
            }

            // 3. 删除文件
            try fileManager.removeItem(at: fileToDelete)

            // 4. 从内存中移除
            notes.removeAll { $0.fileURL == note.fileURL }

            // 5. 更新选择状态
            updateSelectionAfterDeletion()

        } catch {
            print("Error deleting note: \(error)")
            print("File path: \(note.fileURL.path)")
            print("Error details: \(error.localizedDescription)")
        }
    }

    func archiveNote(_ note: RecentNote) {
        do {
            let fileToArchive = note.fileURL
            print("Attempting to archive file at: \(fileToArchive.path)")

            // Verify file exists
            let fileManager = FileManager.shared
            guard fileManager.fm.fileExists(atPath: fileToArchive.path) else {
                print("File does not exist at path: \(fileToArchive.path)")
                return
            }

            // Archive the file
            try fileManager.archiveNote(at: fileToArchive)

            withAnimation(.easeOut(duration: 0.0)) {
                // Remove from memory
                notes.removeAll { $0.fileURL == note.fileURL }

                // Update selection state
                updateSelectionAfterDeletion()

                // Refresh notes list
                notes = FileManager.getRecentNotes()
            }

            // Show archive toast
            withAnimation(.easeIn(duration: 0.2)) {
                showArchiveToast = true
            }

            // Hide toast after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.showArchiveToast = false
                }
            }

        } catch {
            print("Error archiving note: \(error)")
            print("File path: \(note.fileURL.path)")
            print("Error details: \(error.localizedDescription)")
        }
    }

    private func updateSelectionAfterDeletion() {
        // 如果过滤后的列表为空，重置选择
        if filteredNotes.isEmpty {
            currentNoteIndex = nil
            return
        }

        // 否则确保有效范围内
        if let current = currentNoteIndex {
            currentNoteIndex = min(current, filteredNotes.count - 1)
        }
    }

    // 键盘导航：保持单一职责，只处理选中状态
    func selectNextNote() {
        guard !filteredNotes.isEmpty else { return }

        // 暂时禁用悬停效果
        isHoverEnabled = false

        // 延迟重新启用悬停效果
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isHoverEnabled = true
        }

        if let current = currentNoteIndex {
            currentNoteIndex = min(current + 1, filteredNotes.count - 1)
        } else {
            currentNoteIndex = 0
        }
    }

    func selectPreviousNote() {
        guard !filteredNotes.isEmpty else { return }

        // 暂时禁用悬停效果
        isHoverEnabled = false

        // 延迟重新启用悬停效果
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isHoverEnabled = true
        }

        if let current = currentNoteIndex {
            currentNoteIndex = max(current - 1, 0)
        } else {
            currentNoteIndex = filteredNotes.count - 1
        }
    }

    func setHoveredNote(_ index: Int?) {
        // 只在允许悬停时更新状态
        if isHoverEnabled {
            currentNoteIndex = index
        }
    }

    // 点击选择：同时更新选中状态并清除悬停状态
    func selectNote(_ index: Int) {
        currentNoteIndex = index
        //        hoveredNoteIndex = nil

        // 暂时禁用悬停效果
        isHoverEnabled = false

        // 延迟重新启用悬停效果
        DispatchQueue.main.asyncAfter(deadline: .now() + 0) { [weak self] in
            self?.isHoverEnabled = true
        }
    }

    // 重置选择：清除所有状态
    func resetSelection() {
        if !filteredNotes.isEmpty {
            currentNoteIndex = 0
        } else {
            currentNoteIndex = nil
        }
        currentNoteIndex = nil
    }

    var hoverEnabled: Bool {
        isHoverEnabled
    }

    var groupedFilteredNotes: [GroupedNotes] {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let weekStart = calendar.date(byAdding: .day, value: -7, to: todayStart)!

        // Containers for non‐today groups and today's sub‐groups
        var nonTodayGroups: [TimeGroup: [RecentNote]] = [:]
        var todayGroups: [TimeGroup: [RecentNote]] = [:]

        // Define thresholds for today
        let fifteenMinutes: TimeInterval = 15 * 60
        let oneHour: TimeInterval = 60 * 60
        let noonToday =
            calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)
            ?? todayStart.addingTimeInterval(12 * 3600)

        // Enable sub–groups only if enough time has passed today
        let enableLast15 = now.timeIntervalSince(todayStart) >= fifteenMinutes
        let enableLast1 = now.timeIntervalSince(todayStart) >= oneHour
        let enableAfternoon = now >= noonToday

        if enableLast15 {
            todayGroups[.last15Min] = []
        }
        if enableLast1 {
            todayGroups[.last1Hour] = []
        }
        // Always add a "This morning" group (even if it is the only one)
        todayGroups[.thisMorning] = []
        if enableAfternoon {
            todayGroups[.thisAfternoon] = []
        }

        // Loop through filteredNotes and assign groups
        for note in filteredNotes {
            let noteDate = note.lastModified
            if calendar.isDate(noteDate, inSameDayAs: now) {
                // For today, use relative thresholds
                if enableLast15 && noteDate >= now.addingTimeInterval(-fifteenMinutes) {
                    todayGroups[.last15Min]?.append(note)
                } else if enableLast1 && noteDate >= now.addingTimeInterval(-oneHour) {
                    todayGroups[.last1Hour]?.append(note)
                } else {
                    // For notes older than one hour, choose morning vs. afternoon if applicable
                    if enableAfternoon {
                        if noteDate >= noonToday {
                            todayGroups[.thisAfternoon]?.append(note)
                        } else {
                            todayGroups[.thisMorning]?.append(note)
                        }
                    } else {
                        todayGroups[.thisMorning]?.append(note)
                    }
                }
            } else if calendar.isDate(noteDate, inSameDayAs: yesterday) {
                nonTodayGroups[.yesterday, default: []].append(note)
            } else if noteDate >= weekStart {
                nonTodayGroups[.thisWeek, default: []].append(note)
            } else {
                nonTodayGroups[.older, default: []].append(note)
            }
        }

        // Now build the resulting array in the desired order.
        var groupsArray: [GroupedNotes] = []

        // Order today's groups according to what's enabled.
        var todayOrder: [TimeGroup] = []
        if enableLast15 {
            todayOrder.append(.last15Min)
        }
        if enableLast1 {
            todayOrder.append(.last1Hour)
        }
        if enableAfternoon {
            todayOrder.append(.thisAfternoon)
            todayOrder.append(.thisMorning)
        } else {
            todayOrder.append(.thisMorning)
        }
        for group in todayOrder {
            if let notes = todayGroups[group], !notes.isEmpty {
                groupsArray.append(GroupedNotes(group: group, notes: notes))
            }
        }

        // Order non–today groups in a fixed order.
        let nonTodayOrder: [TimeGroup] = [.yesterday, .thisWeek, .older]
        for group in nonTodayOrder {
            if let notes = nonTodayGroups[group], !notes.isEmpty {
                groupsArray.append(GroupedNotes(group: group, notes: notes))
            }
        }
        return groupsArray
    }

    func archiveGroupNotes(_ notes: [RecentNote], groupTitle: String) {
        archivedNotes = notes
        archivedNotesCount = notes.count

        for note in notes {
            do {
                let fileToArchive = note.fileURL
                guard FileManager.shared.fm.fileExists(atPath: fileToArchive.path) else {
                    continue
                }

                try FileManager.shared.archiveNote(at: fileToArchive)

                withAnimation(.easeOut(duration: 0.0)) {
                    self.notes.removeAll { $0.fileURL == note.fileURL }
                }
            } catch {
                print("Error archiving note: \(error)")
            }
        }

        withAnimation(.easeIn(duration: 0.2)) {
            showUndoArchiveToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation(.easeOut(duration: 0.2)) {
                if self.showUndoArchiveToast {
                    self.showUndoArchiveToast = false
                    self.archivedNotes = []
                }
            }
        }
    }

    func undoGroupArchive() {
        for note in archivedNotes {
            do {
                if let monthFolder = FileManager.shared.getMonthlyArchiveFolder() {
                    let archivedPath = monthFolder.appendingPathComponent(
                        note.fileURL.lastPathComponent)
                    try FileManager.shared.fm.moveItem(at: archivedPath, to: note.fileURL)

                    withAnimation {
                        self.notes.append(note)
                    }
                }
            } catch {
                print("Error restoring note: \(error)")
            }
        }

        withAnimation {
            showUndoArchiveToast = false
            archivedNotes = []
        }
    }
}

//MARK: - Main List View
struct RecentNotesListView: View {
    let notes: [RecentNote]
    let onSelectNote: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = RecentNotesViewModel()
    @FocusState private var searchFocused: Bool
    @State private var isShowAllHovered = false
    @State private var eventMonitor: Any?

    private func setupKeyboardMonitor() {
        removeKeyboardMonitor()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            switch event.keyCode {
            case 125:  // Down arrow
                viewModel.selectNextNote()
                return nil
            case 126:  // Up arrow
                viewModel.selectPreviousNote()
                return nil
            case 36:  // Return key
                // 当中文输入正在进行时，不直接触发选择逻辑，让系统处理输入候选确认
                let composing: Bool = {
                    if let window = NSApp.keyWindow,
                        let client = window.firstResponder as? NSTextInputClient
                    {
                        return client.hasMarkedText()
                    }
                    return false
                }()
                if composing {
                    return event
                }

                if let currentIndex = viewModel.currentNoteIndex {
                    let currentNote = viewModel.filteredNotes[currentIndex]
                    onSelectNote(currentNote.content)
                    dismiss()
                    return nil
                }
                return event
            case 51:  // Delete key
                if event.modifierFlags.contains(.command) {
                    if let currentIndex = viewModel.currentNoteIndex {
                        let currentNote = viewModel.filteredNotes[currentIndex]
                        withAnimation {
                            viewModel.archiveNote(currentNote)
                        }
                    }
                    return nil
                }
                return event
            case 53:  // ESC key
                dismiss()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func openInFinder() {
        guard let notesDirectory = FileManager.shared.notesDirectory else {
            print("Could not access notes directory")
            return
        }

        NSWorkspace.shared.selectFile(
            nil,
            inFileViewerRootedAtPath: notesDirectory.path
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search notes...", text: $viewModel.searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 14))
                        .tint(.purple)
                        .focused($searchFocused)
                    if !viewModel.searchText.isEmpty {
                        Button(action: {
                            viewModel.searchText = ""
                            viewModel.resetSelection()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .onChange(of: viewModel.searchText) {
                    viewModel.resetSelection()
                }

                // Notes List
                if !viewModel.filteredNotes.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(viewModel.groupedFilteredNotes, id: \.group.rawValue) {
                                    group in
                                    VStack(alignment: .leading, spacing: 4) {
                                        // Group header
                                        TimeGroupHeader(
                                            title: group.group.rawValue,
                                            notes: group.notes,
                                            viewModel: viewModel)

                                        // Notes in this group
                                        ForEach(Array(group.notes.enumerated()), id: \.element.id) {
                                            index, note in
                                            let globalIndex =
                                                viewModel.filteredNotes.firstIndex(where: {
                                                    $0.id == note.id
                                                }) ?? 0

                                            let noteRow = NoteRow(
                                                note: note,
                                                isHighLight: viewModel.currentNoteIndex
                                                    == globalIndex ? true : false,
                                                onTap: {
                                                    onSelectNote(note.content)
                                                    dismiss()
                                                },
                                                onDelete: {
                                                    withAnimation {
                                                        viewModel.archiveNote(note)
                                                    }
                                                },
                                                onHover: { isHovered in
                                                    viewModel.setHoveredNote(
                                                        isHovered ? globalIndex : nil)
                                                },
                                                searchText: viewModel.searchText
                                            )

                                            LazyVStack {
                                                noteRow
                                                    .transition(
                                                        .asymmetric(
                                                            insertion: .opacity,
                                                            removal: .move(edge: .leading)
                                                        )
                                                    )
                                            }
                                            .id(note.id)
                                        }
                                    }

                                    // Add divider after each group except the last one
                                    if group.group.rawValue
                                        != viewModel.groupedFilteredNotes.last?.group.rawValue
                                    {
                                        Divider()
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 4)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: 360)

                        .onChange(of: viewModel.currentNoteIndex) {
                            if let index = viewModel.currentNoteIndex, !viewModel.hoverEnabled {
                                withAnimation {
                                    if let note = viewModel.filteredNotes[safe: index] {
                                        proxy.scrollTo(note.id)
                                    }
                                }
                            }
                        }
                    }
                    .onHover { _ in
                        if searchFocused {
                            searchFocused = false
                        }
                    }
                }

                // Empty State
                if viewModel.filteredNotes.isEmpty {
                    Text(viewModel.searchText.isEmpty ? "No notes" : "No matching notes")
                        .foregroundColor(.secondary)
                        .padding(24)
                        .frame(height: 360)
                }
            }
            .frame(width: 320)
            .background(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95))
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)

            // Toast View
            if viewModel.showArchiveToast {
                VStack {
                    Spacer()
                    StandardToastView(
                        icon: "archivebox.fill",
                        message: "Note Archived"
                    )
                }
                .transition(.opacity)
            }

            // Add Undo Toast
            if viewModel.showUndoArchiveToast {
                VStack {
                    Spacer()
                    StandardToastView(
                        icon: "archivebox.fill",
                        message:
                            "Copied summary & archived \(viewModel.archivedNotesCount) \(viewModel.archivedNotesCount == 1 ? "note" : "notes")",
                        actionButton: ("Undo", { viewModel.undoGroupArchive() })
                    )
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            setupKeyboardMonitor()
        }
        .onDisappear {
            searchFocused = false
            print("searchFocused rmvd")
            removeKeyboardMonitor()
        }
    }
}

enum HighlightState {
    case none
    case selected
    case hovered
}

// MARK: - Note Row View
struct NoteRow: View {
    let note: RecentNote
    let isHighLight: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onHover: (Bool) -> Void
    let searchText: String
    @State private var isCopied = false
    @State private var isHoveringCopy = false
    @State private var isHoveringShare = false
    @State private var showPreview = false
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var isInfoHovered = false
    @State private var isSummarizing = false
    @State private var summary: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDeleteHovered = false

    private func getRelativeTime(from date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current

        // Check if the date is from an earlier day
        if !calendar.isDate(date, inSameDayAs: now) {
            // For dates before today, show actual timestamp '
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            return dateFormatter.string(from: date)
        }

        // For today's dates, use relative time
        let diffInSeconds = Int(now.timeIntervalSince(date))
        let diffInMinutes = diffInSeconds / 60
        let diffInHours = diffInMinutes / 60
        let diffInDays = diffInHours / 24

        if diffInMinutes < 1 {
            return "less than 1 min"
        } else if diffInMinutes < 60 {
            return "\(diffInMinutes) min"
        } else if diffInHours < 24 {
            return "\(diffInHours) hr \(diffInMinutes % 60) min"
        } else {
            return "\(diffInDays) day \(diffInHours % 24) hr"
        }
    }

    private func getMatchingContent() -> (title: String, contexts: [AttributedString]?) {
        // 默认显示标题
        let title = note.title.isEmpty ? "Untitled" : note.title

        guard !searchText.isEmpty else {
            return (title, nil)
        }

        // 调试打印
        print("Searching for: \(searchText)")
        print("Title: \(title)")
        print("Content length: \(note.content.count)")

        var matchingContexts: [AttributedString] = []

        // 查找包含搜索词的段落和位置
        let paragraphs = note.content.components(separatedBy: .newlines)
        for paragraph in paragraphs {
            if paragraph.localizedCaseInsensitiveContains(searchText) {
                // 使用 NSString 来处理中文字符
                let nsString = paragraph as NSString
                let range = nsString.range(of: searchText, options: .caseInsensitive)

                if range.location != NSNotFound {
                    // 计算前后文的范围
                    let preStart = max(0, range.location - 20)
                    let preLength = min(20, range.location - preStart)
                    let postStart = range.location + range.length
                    let postLength = min(20, nsString.length - postStart)

                    // 提取前后文
                    let preContext = nsString.substring(
                        with: NSRange(location: preStart, length: preLength))
                    let matchText = nsString.substring(with: range)
                    let postContext = nsString.substring(
                        with: NSRange(location: postStart, length: postLength))

                    // 组合完整的上下文
                    let fullContext = "\(preContext)\(matchText)\(postContext)"
                    var attributed = AttributedString(fullContext)

                    // 计算高亮范围
                    let highlightRange = (fullContext as NSString).range(of: matchText)
                    if highlightRange.location != NSNotFound {
                        let attribRange = Range(highlightRange, in: attributed)!
                        attributed[attribRange].backgroundColor = .yellow.opacity(0.3)
                        attributed[attribRange].foregroundColor = .primary
                    }

                    matchingContexts.append(attributed)
                }
            }
        }

        return (title, matchingContexts.isEmpty ? nil : matchingContexts)
    }

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.content, forType: .string)

        // Trigger animation
        withAnimation {
            isCopied = true
        }

        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }

    private func shareContent() {
        // 使用 NSSharingServicePicker 展示分享菜单，分享 note.content
        let items: [Any] = [note.content]
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            let sharingPicker = NSSharingServicePicker(items: items)
            sharingPicker.show(
                relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    let content = getMatchingContent()

                    HStack {
                        Text(content.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)

                        Spacer()
                    }

                    if let summary = summary {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .padding(.top, 4)
                    }

                    if let contexts = content.contexts {
                        ForEach(Array(contexts.enumerated()), id: \.offset) { _, context in
                            Text(context)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    HStack(spacing: 4) {
                        Text(getRelativeTime(from: note.lastModified))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("\(note.content.count) Chars")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .opacity(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if isHighLight {
                // Info button
                Button(action: {}) {
                    HStack {
                        Spacer()
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                isInfoHovered
                                    ? (colorScheme == .dark
                                        ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                    : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    isInfoHovered = hovering
                    if hovering {
                        let workItem = DispatchWorkItem {
                            withAnimation {
                                showPreview = true
                            }
                        }
                        hoverWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
                    } else {
                        hoverWorkItem?.cancel()
                        withAnimation {
                            showPreview = false
                        }
                    }
                }
                .popover(isPresented: $showPreview, arrowEdge: .leading) {
                    NotePreviewView(content: note.content)
                }

                // Copy button
                Button(action: copyContent) {
                    HStack {
                        Spacer()
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .contentTransition(.symbolEffect(.replace))
                        Spacer()
                    }
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                isHoveringCopy
                                    ? (colorScheme == .dark
                                        ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                    : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    isHoveringCopy = hovering
                }

                // Share button
                Button(action: shareContent) {
                    HStack {
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                isHoveringShare
                                    ? (colorScheme == .dark
                                        ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                    : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    isHoveringShare = hovering
                }

                // Archive button
                Button(action: onDelete) {
                    HStack {
                        Spacer()
                        Image(systemName: "archivebox")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                isDeleteHovered
                                    ? (colorScheme == .dark
                                        ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                    : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    isDeleteHovered = hovering
                }

            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isHighLight
                        ? (colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85))
                        : Color.clear
                )
                .opacity(0.5)
                .padding(.horizontal, 6)
        )
        .onHover(perform: onHover)
    }
}

struct NotePreviewView: View {
    let content: String

    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 10, x: -4, y: 4)
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct TimeGroupHeader: View {
    let title: String
    let notes: [RecentNote]
    @StateObject var viewModel: RecentNotesViewModel
    @State private var isSummarizing = false
    @State private var isCopied = false
    @State private var isHoveringCopy = false
    @State private var isHoveringArchive = false
    @State private var isHoveringShare = false
    @Environment(\.colorScheme) private var colorScheme

    // 控制 Copy 按钮扩展状态
    @State private var isCopyOptionsExpanded = false
    // 控制 Share 按钮扩展状态
    @State private var isShareOptionsExpanded = false

    private var shouldShowSummarize: Bool {
        guard let group = TimeGroup(rawValue: title) else { return false }
        return !(viewModel.showingSummaries[group] ?? false)
    }

    private func summarizeGroupNotes() {
        // 确保能够转换为 TimeGroup，否则直接返回
        guard let group = TimeGroup(rawValue: title) else { return }
        isSummarizing = true

        // 合并当前分组内所有笔记的标题和内容
        let combinedContent = notes.map { note in
            "Note: \(note.title)\n\(note.content)"
        }.joined(separator: "\n---\n")

        // 风控校验：不允许超过 10000 字
        if combinedContent.count > 10000 {
            print("The content exceeds 10,000 characters and cannot be summarized.")
            DispatchQueue.main.async {
                // 更新摘要内容，提示用户文本过长
                var newSummaries = viewModel.groupSummaries
                newSummaries[group] = "Content is too long to be summarized."
                viewModel.groupSummaries = newSummaries
            }
            isSummarizing = false
            return
        }

        // 定义流式处理类，处理 API 逐步返回的数据
        class StreamHandler: SummarizeStreamDelegate {
            var summary: String = ""
            weak var viewModel: RecentNotesViewModel?
            let group: TimeGroup
            let completion: () -> Void  // 通知摘要完成

            init(
                viewModel: RecentNotesViewModel?, group: TimeGroup, completion: @escaping () -> Void
            ) {
                print("🎯 StreamHandler initialized for group: \(group)")
                self.viewModel = viewModel
                self.group = group
                self.completion = completion

                // 清空之前的摘要
                DispatchQueue.main.async {
                    var newSummaries = viewModel?.groupSummaries ?? [:]
                    newSummaries[group] = ""
                    viewModel?.groupSummaries = newSummaries
                }
            }

            func receivedPartialContent(_ content: String) {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let viewModel = self.viewModel else { return }
                    self.summary += content
                    print("🔄 Updating summary: \(self.summary)")
                    // 更新摘要到 ViewModel
                    var newSummaries = viewModel.groupSummaries
                    newSummaries[self.group] = self.summary
                    viewModel.groupSummaries = newSummaries
                    print("📊 GroupSummaries now: \(viewModel.groupSummaries)")
                }
            }

            func completed() {
                print("✅ Summary completed for group: \(group)")
                print("📄 Final summary: \(summary)")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let viewModel = self.viewModel else { return }
                    var newSummaries = viewModel.groupSummaries
                    newSummaries[self.group] = self.summary
                    viewModel.groupSummaries = newSummaries
                    if #available(macOS 10.11, *) {
                        NSHapticFeedbackManager.defaultPerformer.perform(
                            .generic, performanceTime: .now)
                    }
                    self.completion()  // 通知摘要流程结束
                }
            }

            func failed(with error: Error) {
                print("❌ Summary failed for group: \(group) - Error: \(error)")
                DispatchQueue.main.async {
                    self.completion()  // 出错时也结束摘要流程
                }
            }
        }

        // 创建流式处理对象，并传入回调以更新 isSummarizing 状态
        let streamHandler = StreamHandler(viewModel: viewModel, group: group) {
            self.isSummarizing = false
        }

        // 发起摘要请求（已通过前置校验确保文本长度不超过 10000 字）
        DoubaoAPI.shared.summarizeWithStream(text: combinedContent, delegate: streamHandler)
    }

    private func copyContent() {
        guard let summary = viewModel.groupSummaries[TimeGroup(rawValue: title)!] else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)

        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }

    private func copyAndArchive() {
        if let summary = viewModel.groupSummaries[TimeGroup(rawValue: title)!] {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(summary, forType: .string)
            viewModel.archiveGroupNotes(notes, groupTitle: title)
        }
    }

    private func shareContent() {
        guard let summary = viewModel.groupSummaries[TimeGroup(rawValue: title)!] else { return }
        let items: [Any] = [summary]
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            let sharingPicker = NSSharingServicePicker(items: items)
            sharingPicker.show(
                relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }

    private func shareAndArchive() {
        if let summary = viewModel.groupSummaries[TimeGroup(rawValue: title)!] {
            let items: [Any] = [summary]
            if let window = NSApp.keyWindow, let contentView = window.contentView {
                let sharingPicker = NSSharingServicePicker(items: items)
                sharingPicker.show(
                    relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
            }
            viewModel.archiveGroupNotes(notes, groupTitle: title)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if shouldShowSummarize {
                    Button(action: summarizeGroupNotes) {
                        if !isSummarizing {
                            Text("Summarize")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.8))
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.4)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let group = TimeGroup(rawValue: title),
                let groupSummary = viewModel.groupSummaries[group],
                !groupSummary.isEmpty
            {
                VStack(alignment: .leading, spacing: 8) {
                    Text(groupSummary)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .lineSpacing(4)

                    if !isSummarizing {
                        // 将 Copy 与 Share 操作放在同一个 HStack 中，横向排列
                        HStack(spacing: 8) {
                            // Copy 操作
                            HStack(spacing: 0) {
                                Button(action: copyContent) {
                                    Text("Copy")
                                        .font(.system(size: 12))
                                        .padding(.vertical, 2)
                                        .padding(.horizontal, 6)
                                }
                                .buttonStyle(.plain)

                                if isCopyOptionsExpanded {
                                    Divider()
                                        .frame(height: 28)
                                    Button(action: copyAndArchive) {
                                        Text("Copy & Archive")
                                            .font(.system(size: 12))
                                            .padding(.vertical, 2)
                                            .padding(.horizontal, 6)
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(isCopyOptionsExpanded ? 1 : 0)
                                }
                            }
                            .padding(2)
                            .frame(height: 28)  // 固定垂直高度，确保悬停前后位置不变
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        isCopyOptionsExpanded
                                            ? (colorScheme == .dark
                                                ? Color.white.opacity(0.1)
                                                : Color.black.opacity(0.05))
                                            : Color.clear)
                            )
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isCopyOptionsExpanded = hovering
                                }
                            }

                            // Share 操作
                            HStack(spacing: 0) {
                                Button(action: shareContent) {
                                    Text("Share")
                                        .font(.system(size: 12))
                                        .padding(.vertical, 2)
                                        .padding(.horizontal, 6)
                                }
                                .buttonStyle(.plain)

                                if isShareOptionsExpanded {
                                    Divider()
                                        .frame(height: 28)
                                    Button(action: shareAndArchive) {
                                        Text("Share & Archive")
                                            .font(.system(size: 12))
                                            .padding(.vertical, 2)
                                            .padding(.horizontal, 6)
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(isShareOptionsExpanded ? 1 : 0)
                                }
                            }
                            .padding(4)
                            .frame(height: 28)  // 固定垂直高度，保证悬停时 y 轴位置不变
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        isShareOptionsExpanded
                                            ? (colorScheme == .dark
                                                ? Color.white.opacity(0.1)
                                                : Color.black.opacity(0.05))
                                            : Color.clear)
                            )
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isShareOptionsExpanded = hovering
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                }
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                colorScheme == .dark
                                    ? Color(white: 0.15).opacity(0.95)
                                    : Color(white: 0.95).opacity(0.95))
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.1), .clear],
                                    startPoint: .bottomTrailing,
                                    endPoint: .topLeading
                                )
                            )
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                LinearGradient(
                                    gradient: Gradient(colors: [.purple, .pink]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: .purple.opacity(0.2), radius: 12, x: 0, y: 4)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .background(Color.clear)
    }
}

struct ToastStyle {
    static let backgroundColor = Color(white: 0.15).opacity(0.95)
    static let lightBackgroundColor = Color(white: 0.95).opacity(0.95)
    static let shadowColor = Color.black.opacity(0.2)
    static let cornerRadius: CGFloat = 8
    static let padding = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
}

struct StandardToastView: View {
    let icon: String
    let message: String
    var actionButton: (title: String, action: () -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Enhanced icon with animation
            if #available(macOS 15.0, *) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                    .symbolEffect(.bounce.up, options: .repeat(1))
            } else {
                // Fallback on earlier versions
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .foregroundColor(.primary)
                    .font(.system(size: 13, weight: .medium))
            }

            if let button = actionButton {
                Button(button.title, action: button.action)
                    .buttonStyle(.plain)
                    // .foregroundColor(.red)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(ToastStyle.padding)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: ToastStyle.cornerRadius)
                    .fill(
                        colorScheme == .dark
                            ? ToastStyle.backgroundColor : ToastStyle.lightBackgroundColor)

                // Add subtle gradient overlay
                RoundedRectangle(cornerRadius: ToastStyle.cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.1), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Add subtle border
                RoundedRectangle(cornerRadius: ToastStyle.cornerRadius)
                    .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
            }
        )
        .shadow(
            color: ToastStyle.shadowColor,
            radius: 12,
            x: 0,
            y: 4
        )
        .padding(.bottom, 12)
    }
}
