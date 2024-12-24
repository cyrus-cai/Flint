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
            let recentURLs = notesWithDates.prefix(50)

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

class RecentNotesViewModel: ObservableObject {
    @Published var notes: [RecentNote] = []
    @Published var searchText: String = ""
    @Published var selectedNoteIndex: Int? = nil
    @Published var hoveredNoteIndex: Int? = nil
    @Published var currentNoteIndex: Int? = nil
    @Published private var isHoverEnabled = true

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
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
                // 上下键始终用于导航，不管搜索框是否聚焦
                viewModel.selectNextNote()
                return nil
            case 126:  // Up arrow
                // 上下键始终用于导航，不管搜索框是否聚焦
                viewModel.selectPreviousNote()
                return nil
            case 36:  // Return key
                // enter 键始终用于将该条内容填充到现在的文本框中
                if let currentIndex = viewModel.currentNoteIndex {
                    let currentNote = viewModel.filteredNotes[currentIndex]
                    onSelectNote(currentNote.content)
                    dismiss()
                }
                return nil
            case 51:  // Delete key
                if event.modifierFlags.contains(.command) {
                    // Command+Delete: 删除当前选中的条目
                    if let currentIndex = viewModel.currentNoteIndex {
                        let currentNote = viewModel.filteredNotes[currentIndex]
                        withAnimation {  // 添加动画
                            viewModel.deleteNote(currentNote)
                        }

                    }
                    return nil
                }
                return event
            case 53:  // ESC key
                dismiss()
                return nil
            default:
                // 其他所有按键都正常传递
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
                    .onHover { isHovered in
                        if isHovered {
                            searchFocused = true
                        }
                    }
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
                        // 历史记录列表的高度间隔
                        LazyVStack(spacing: 6) {
                            ForEach(Array(viewModel.filteredNotes.enumerated()), id: \.element.id) {
                                index, note in
                                NoteRow(
                                    note: note,
                                    isHighLight: viewModel.currentNoteIndex == index ? true : false,
                                    onTap: {
                                        onSelectNote(note.content)
                                        dismiss()
                                    },
                                    onDelete: {
                                        withAnimation {  // 添加动画
                                            viewModel.deleteNote(note)
                                        }
                                        //                                        viewModel.deleteNote(note)
                                    },
                                    onHover: { isHovered in
                                        viewModel.setHoveredNote(isHovered ? index : nil)
                                    },
                                    searchText: viewModel.searchText
                                )
                                .id(note.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: viewModel.currentNoteIndex) {
                        if let index = viewModel.currentNoteIndex, !viewModel.hoverEnabled {
                            withAnimation {
                                proxy.scrollTo(index)
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
            }

            // Footer
            // if !viewModel.notes.isEmpty && !viewModel.filteredNotes.isEmpty {
            // {
                // Divider()
                // HStack {
                //     Button(action: openInFinder) {
                //         HStack {
                //             Text("Show All")
                //                 .font(.system(size: 12))
                //                 .foregroundColor(.secondary)
                //         }
                //         .frame(maxWidth: .infinity)
                //         .padding(.vertical, 8)
                //         .background(
                //             RoundedRectangle(cornerRadius: 0)
                //                 .fill(
                //                     isShowAllHovered
                //                         ? (colorScheme == .dark
                //                             ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                //                         : Color.clear)
                //         )
                //     }
                //     .buttonStyle(PlainButtonStyle())
                //     .onHover { hovering in
                //         isShowAllHovered = hovering
                //     }
                // }
            // }

        }
        .frame(width: 320)
        .background(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
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

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDeleteHovered = false

    private func getRelativeTime(from date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current

        // Check if the date is from an earlier day
        if !calendar.isDate(date, inSameDayAs: now) {
            // For dates before today, show actual timestamp
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
                    let preContext = nsString.substring(with: NSRange(location: preStart, length: preLength))
                    let matchText = nsString.substring(with: range)
                    let postContext = nsString.substring(with: NSRange(location: postStart, length: postLength))

                    // 组合完整的上下��
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

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    let content = getMatchingContent()

                    // 始终显示标题
                    Text(content.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)

                    // 如果有匹配的内容，显示所有匹配行
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
                        Text("\(note.content.count) characters")
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
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(isDeleteHovered ? .red : .primary)
                        .padding(.horizontal, 2)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    isDeleteHovered = hovering
                }
                .transition(.opacity)
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
        .onHover { hovering in
            withAnimation {
                onHover(hovering)
            }
        }
    }
}
