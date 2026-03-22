import Combine
import Foundation
import SwiftUI

// MARK: - Recent Note Model has been moved to FileManagerExtend.swift

enum TimeGroup: String {
    case last15Min = "Last 15 min"
    case last1Hour = "Last 1 hour"
    case thisMorning = "This morning"
    case thisAfternoon = "This afternoon"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case older = "Earlier"
    
    var localized: String {
        return L(self.rawValue)
    }
}

struct GroupedNotes {
    let group: TimeGroup
    let notes: [RecentNote]
}

class RecentNotesViewModel: ObservableObject {
    // MARK: - Data
    @Published var notes: [RecentNote] = []
    @Published var searchText: String = ""
    @Published var showStarredOnly = false

    // MARK: - Cached filtered/grouped results (Step 1)
    @Published private(set) var filteredNotes: [RecentNote] = []
    @Published private(set) var groupedFilteredNotes: [GroupedNotes] = []
    private(set) var filteredNoteIndexMap: [String: Int] = [:]  // note.id → index

    // MARK: - Selection (ID-based, Step 0b)
    @Published var selectedNoteID: String? = nil   // keyboard nav / toolbar prev-next anchor
    @Published var hoveredNoteID: String? = nil    // visual highlight only
    @Published private var isHoverEnabled = true

    var highlightedNoteID: String? {
        hoveredNoteID ?? selectedNoteID
    }

    // MARK: - Async refresh (Step 3)
    private(set) var refreshGeneration: UInt = 0
    private var pendingSelectedNoteID: String? = nil
    @Published var isRefreshing: Bool = false

    // MARK: - Metrics cache (Step 4)
    private let cacheQueue = DispatchQueue(label: "com.flint.contentCache")
    private var _wordCountCache: [String: Int] = [:]
    private var _charCountCache: [String: Int] = [:]
    private var _loadingIDs: Set<String> = []

    // MARK: - Combine
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Starred persistence
    private let starredNotesKey = "StarredNotes"

    // MARK: - Init

    init(loadOnInit: Bool = true) {
        if loadOnInit {
            notes = LocalFileManager.shared.getRecentNotes()
            loadStarredStatus()
        }

        // Recompute when notes, searchText, or showStarredOnly change
        Publishers.CombineLatest3($notes, $showStarredOnly, $searchText)
            .dropFirst()
            .sink { [weak self] _, _, _ in self?.recomputeFilteredNotes() }
            .store(in: &cancellables)

        // Initial computation
        recomputeFilteredNotes()
    }

    // MARK: - Filtered/Grouped recomputation

    func recomputeFilteredNotes() {
        let base = showStarredOnly ? notes.filter { $0.isStarred } : notes
        if searchText.isEmpty {
            filteredNotes = base
        } else {
            filteredNotes = base.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.firstLinePreview.localizedCaseInsensitiveContains(searchText)
            }
        }
        filteredNoteIndexMap = Dictionary(uniqueKeysWithValues:
            filteredNotes.enumerated().map { ($1.id, $0) })
        recomputeGroupedNotes()

        // Selection sync: pending from refresh takes priority
        if let pending = pendingSelectedNoteID, filteredNoteIndexMap[pending] != nil {
            selectedNoteID = pending
            pendingSelectedNoteID = nil
        } else if selectedNoteID == nil || filteredNoteIndexMap[selectedNoteID!] == nil {
            selectedNoteID = filteredNotes.first?.id
        }
        // Hover sync
        if let hid = hoveredNoteID, filteredNoteIndexMap[hid] == nil {
            hoveredNoteID = nil
        }
    }

    private func recomputeGroupedNotes() {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let weekStart = calendar.date(byAdding: .day, value: -7, to: todayStart)!

        var nonTodayGroups: [TimeGroup: [RecentNote]] = [:]
        var todayGroups: [TimeGroup: [RecentNote]] = [:]

        let fifteenMinutes: TimeInterval = 15 * 60
        let oneHour: TimeInterval = 60 * 60
        let noonToday =
            calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)
            ?? todayStart.addingTimeInterval(12 * 3600)

        let enableLast15 = now.timeIntervalSince(todayStart) >= fifteenMinutes
        let enableLast1 = now.timeIntervalSince(todayStart) >= oneHour
        let enableAfternoon = now >= noonToday

        if enableLast15 { todayGroups[.last15Min] = [] }
        if enableLast1 { todayGroups[.last1Hour] = [] }
        todayGroups[.thisMorning] = []
        if enableAfternoon { todayGroups[.thisAfternoon] = [] }

        for note in filteredNotes {
            let noteDate = note.lastModified
            if calendar.isDate(noteDate, inSameDayAs: now) {
                if enableLast15 && noteDate >= now.addingTimeInterval(-fifteenMinutes) {
                    todayGroups[.last15Min]?.append(note)
                } else if enableLast1 && noteDate >= now.addingTimeInterval(-oneHour) {
                    todayGroups[.last1Hour]?.append(note)
                } else {
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

        var groupsArray: [GroupedNotes] = []
        var todayOrder: [TimeGroup] = []
        if enableLast15 { todayOrder.append(.last15Min) }
        if enableLast1 { todayOrder.append(.last1Hour) }
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
        let nonTodayOrder: [TimeGroup] = [.yesterday, .thisWeek, .older]
        for group in nonTodayOrder {
            if let notes = nonTodayGroups[group], !notes.isEmpty {
                groupsArray.append(GroupedNotes(group: group, notes: notes))
            }
        }
        groupedFilteredNotes = groupsArray
    }

    // MARK: - Async refresh

    func refreshAsync(selectNoteID: String? = nil) {
        let gen = refreshGeneration &+ 1
        refreshGeneration = gen
        pendingSelectedNoteID = selectNoteID
        isRefreshing = true
        searchText = ""
        showStarredOnly = false
        hoveredNoteID = nil
        clearMetricsCache()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let freshNotes = LocalFileManager.shared.getRecentNotes()
            DispatchQueue.main.async {
                guard let self, self.refreshGeneration == gen else { return }
                self.notes = freshNotes
                self.loadStarredStatus()
                self.isRefreshing = false
                // Combine sink auto-triggers recomputeFilteredNotes
            }
        }
    }

    // MARK: - Selection / Hover

    private var hoverExitWorkItem: DispatchWorkItem?

    func setHoveredNote(_ noteID: String?) {
        guard isHoverEnabled else { return }
        // Cancel any pending hover-exit
        hoverExitWorkItem?.cancel()
        hoverExitWorkItem = nil

        if noteID != nil {
            // Entering a row: apply immediately
            hoveredNoteID = noteID
        } else {
            // Leaving a row: defer briefly so a neighbouring row's enter can override
            let workItem = DispatchWorkItem { [weak self] in
                self?.hoveredNoteID = nil
            }
            hoverExitWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: workItem)
        }
    }

    func selectNextNote() {
        guard !filteredNotes.isEmpty else { return }
        isHoverEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isHoverEnabled = true
        }

        if let currentID = selectedNoteID,
           let currentIndex = filteredNoteIndexMap[currentID] {
            let nextIndex = min(currentIndex + 1, filteredNotes.count - 1)
            selectedNoteID = filteredNotes[nextIndex].id
        } else {
            selectedNoteID = filteredNotes.first?.id
        }
        hoveredNoteID = nil
    }

    func selectPreviousNote() {
        guard !filteredNotes.isEmpty else { return }
        isHoverEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isHoverEnabled = true
        }

        if let currentID = selectedNoteID,
           let currentIndex = filteredNoteIndexMap[currentID] {
            let prevIndex = max(currentIndex - 1, 0)
            selectedNoteID = filteredNotes[prevIndex].id
        } else {
            selectedNoteID = filteredNotes.last?.id
        }
        hoveredNoteID = nil
    }

    func resetSelection() {
        selectedNoteID = filteredNotes.first?.id
        hoveredNoteID = nil
    }

    var hoverEnabled: Bool {
        isHoverEnabled
    }

    // MARK: - Delete

    func deleteNote(_ note: RecentNote) {
        do {
            let fileToDelete = note.fileURL
            let fileManager = Foundation.FileManager.default
            guard fileManager.fileExists(atPath: fileToDelete.path) else { return }
            try fileManager.removeItem(at: fileToDelete)
            notes.removeAll { $0.id == note.id }
            // Combine sink auto-triggers recomputeFilteredNotes which syncs selection
        } catch {
            print("Error deleting note: \(error)")
        }
    }

    // MARK: - Star

    func toggleStarred(_ note: RecentNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].isStarred.toggle()
        saveStarredStatus()
        // @Published notes change triggers Combine → recomputeFilteredNotes
    }

    private func saveStarredStatus() {
        let starredPaths = notes.filter { $0.isStarred }.map { $0.fileURL.path }
        UserDefaults.standard.set(starredPaths, forKey: starredNotesKey)
    }

    func loadStarredStatus() {
        let starredPaths = UserDefaults.standard.stringArray(forKey: starredNotesKey) ?? []
        for (index, note) in notes.enumerated() {
            if starredPaths.contains(note.fileURL.path) {
                notes[index].isStarred = true
            }
        }
    }

    // MARK: - Metrics cache

    func cachedWordCount(for noteID: String) -> Int? { _wordCountCache[noteID] }
    func cachedCharCount(for noteID: String) -> Int? { _charCountCache[noteID] }

    func loadMetricsIfNeeded(for note: RecentNote) {
        let id = note.id
        if _wordCountCache[id] != nil || _loadingIDs.contains(id) { return }
        _loadingIDs.insert(id)
        let fileURL = note.fileURL
        let gen = refreshGeneration
        cacheQueue.async { [weak self] in
            let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let wc = TextMetrics.countWords(in: content)
            let cc = content.count
            DispatchQueue.main.async {
                guard let self, self.refreshGeneration == gen else { return }
                self._wordCountCache[id] = wc
                self._charCountCache[id] = cc
                self._loadingIDs.remove(id)
                self.objectWillChange.send()
            }
        }
    }

    func clearMetricsCache() {
        _wordCountCache.removeAll()
        _charCountCache.removeAll()
        _loadingIDs.removeAll()
    }
}

//MARK: - Main List View
struct RecentNotesListView: View {
    @ObservedObject var viewModel: RecentNotesViewModel
    let onSelectNote: (String, URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searchFocused: Bool
    @State private var isShowAllHovered = false
    @State private var eventMonitor: Any?
    @State private var isCopyButtonHovered = false
    @State private var isShareButtonHovered = false

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

                if let highlightedID = viewModel.highlightedNoteID,
                   let index = viewModel.filteredNoteIndexMap[highlightedID] {
                    let note = viewModel.filteredNotes[index]
                    onSelectNote(note.content, note.fileURL)
                    dismiss()
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
        guard let notesDirectory = LocalFileManager.shared.notesDirectory else {
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
                    TextField(L("Search notes..."), text: $viewModel.searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 14))
                        .tint(.accentColor)
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

                // Notes List
                if !viewModel.filteredNotes.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(viewModel.groupedFilteredNotes, id: \.group.rawValue) { group in
                                    CollapsibleGroupView(
                                        group: group,
                                        viewModel: viewModel,
                                        onSelectNote: onSelectNote
                                    )
                                    if group.group.rawValue != viewModel.groupedFilteredNotes.last?.group.rawValue {
                                        Divider()
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 4)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: 360)
                    }
                    .onHover { _ in
                        if searchFocused {
                            searchFocused = false
                        }
                    }
                }

                // Empty State
                if viewModel.filteredNotes.isEmpty {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .frame(height: 360)
                    } else {
                        Text(viewModel.searchText.isEmpty ? L("No notes") : L("No matching notes"))
                            .foregroundColor(.secondary)
                            .padding(24)
                            .frame(height: 360)
                    }
                }
            }
            .frame(width: 320)
            .cornerRadius(8)
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
    let onHover: (Bool) -> Void
    let searchText: String
    var onToggleStar: () -> Void
    var onDelete: () -> Void
    var wordCount: Int?
    var charCount: Int?
    var onAppearLoadMetrics: (() -> Void)?
    @State private var isCopied = false
    @State private var isHoveringCopy = false
    @State private var isHoveringShare = false
    @State private var showPreview = false
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var isInfoHovered = false
    @State private var isStarHovered = false
    @State private var isSummarizing = false
    @State private var summary: String?
    @AppStorage(AppStorageKeys.showWordCount) private var showWordCount: Bool = AppDefaults.showWordCount

    @Environment(\.colorScheme) private var colorScheme

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
            return "< 1 min"
        } else if diffInMinutes < 60 {
            return "\(diffInMinutes) min"
        } else if diffInHours < 24 {
            return "\(diffInHours) hr \(diffInMinutes % 60) min"
        } else {
            return "\(diffInDays) day \(diffInHours % 24) hr"
        }
    }

    private func getMatchingContent() -> (title: String, contexts: [AttributedString]?) {
        let title = note.title.isEmpty ? "Untitled" : note.title

        guard !searchText.isEmpty else {
            return (title, nil)
        }

        // Only highlight in title and firstLinePreview (no disk I/O)
        var matchingContexts: [AttributedString] = []
        for text in [note.title, note.firstLinePreview] {
            if text.localizedCaseInsensitiveContains(searchText) {
                let nsString = text as NSString
                let range = nsString.range(of: searchText, options: .caseInsensitive)
                if range.location != NSNotFound {
                    var attributed = AttributedString(text)
                    if let attribRange = Range(range, in: attributed) {
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
                        if showWordCount {
                            if let wc = wordCount {
                                Text(String(format: L(wc != 1 ? "%d Words" : "%d Word"), wc))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            if let cc = charCount {
                                Text(String(format: L("%d Chars"), cc))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Display source app if available
                        if let sourceApp = note.sourceApp {
                            Text("·")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(sourceApp)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .opacity(0.6)
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .contextMenu {
                Group {
                    Button(action: copyContent) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.doc")
                                .imageScale(.medium)
                                .foregroundColor(.blue)
                            Text(L("Copy"))
                                .font(.system(size: 13))
                        }
                        .padding(.vertical, 3)
                    }

                    Button(action: shareContent) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .imageScale(.medium)
                                .foregroundColor(.green)
                            Text(L("Share"))
                                .font(.system(size: 13))
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider()

                Button(action: onToggleStar) {
                    HStack(spacing: 8) {
                        Image(systemName: note.isStarred ? "star.fill" : "star")
                            .imageScale(.medium)
                            .foregroundColor(.yellow)
                        Text(note.isStarred ? L("Remove Star") : L("Add Star"))
                            .font(.system(size: 13))
                    }
                    .padding(.vertical, 4)
                }
                
                Button(action: onDelete) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .imageScale(.medium)
                            .foregroundColor(.red)
                        Text(L("Delete"))
                            .font(.system(size: 13))
                    }
                    .padding(.vertical, 4)
                }
            }

            // Always show star if the note is starred, regardless of hover state
            if note.isStarred && !isHighLight {
                Button(action: onToggleStar) {
                    HStack {
                        Spacer()
                        Image(systemName: "star.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.yellow)
                        Spacer()
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Remove from starred")
            }

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

                // Star button - only shown on hover if not already starred
                Button(action: onToggleStar) {
                    HStack {
                        Spacer()
                        Image(systemName: note.isStarred ? "star.fill" : "star")
                            .font(.system(size: 13))
                            .foregroundColor(note.isStarred ? .yellow : .primary)
                        Spacer()
                    }
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                isStarHovered
                                    ? (colorScheme == .dark
                                        ? Color.white.opacity(0.1)
                                        : Color.black.opacity(0.05))
                                    : Color.clear)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    isStarHovered = hovering
                }
                .help(note.isStarred ? "Remove from starred" : "Add to starred")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .modifier(HoverButtonBackgroundModifier(isHovered: isHighLight, colorScheme: colorScheme))
        .onHover(perform: onHover)
        .padding(.horizontal, 6)
        .onAppear { onAppearLoadMetrics?() }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.clear)
    }
}

struct ToastStyle {
    static let backgroundColor = Color(white: 0.15).opacity(0.95)
    static let lightBackgroundColor = Color(white: 0.95).opacity(0.95)
    static let shadowColor = Color.black.opacity(0.2)
    // macOS 26+ Liquid Glass 适配: 使用更大的圆角
    static var cornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 12 // Larger, softer corners for Liquid Glass
        }
        return 8 // Traditional macOS corner radius
    }
    static let padding = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
}

struct StandardToastView: View {
    let icon: String
    let message: String
    var actionButton: (title: String, action: () -> Void)? = nil
    var explanatoryText: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var isButtonHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                if #available(macOS 15.0, *) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                        .symbolEffect(.bounce.up, options: .repeat(1))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(message)
                        .foregroundColor(.primary)
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.leading)

                    if let explanatoryText = explanatoryText {
                        Text(explanatoryText)
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                            .multilineTextAlignment(.leading)
                    }
                }

                if let button = actionButton {
                    Spacer()
                    Button(action: button.action) {
                        Text(button.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary.opacity(0.8))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .modifier(ToastActionButtonBackgroundModifier())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isButtonHovered = hovering
                        }
                    }
                }
            }
        }
        .padding(ToastStyle.padding)
        // macOS 26+ Liquid Glass 适配: 使用原生 glassEffect
        .modifier(StandardToastBackgroundModifier(colorScheme: colorScheme))
        .shadow(
            color: ToastStyle.shadowColor,
            radius: 12,
            x: 0,
            y: 4
        )
        .padding(.bottom, 12)
    }
}

/// Background modifier for action button in StandardToastView
private struct ToastActionButtonBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: Use native Liquid Glass effect
            content
                .glassEffect(in: .rect(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
        } else {
            // macOS 15-25: Use traditional Material
            content
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                }
        }
    }
}

/// Background modifier for StandardToastView that uses native glassEffect on macOS 26+
private struct StandardToastBackgroundModifier: ViewModifier {
    let colorScheme: ColorScheme
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26+: 使用原生 Liquid Glass 效果
            content
                .glassEffect(in: .rect(cornerRadius: ToastStyle.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: ToastStyle.cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [.green.opacity(0.1), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ToastStyle.cornerRadius)
                        .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                )
        } else {
            // macOS 15-25: 使用传统背景
            content
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: ToastStyle.cornerRadius)
                            .fill(colorScheme == .dark
                                  ? ToastStyle.backgroundColor
                                  : ToastStyle.lightBackgroundColor)
                        RoundedRectangle(cornerRadius: ToastStyle.cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [.green.opacity(0.1), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        RoundedRectangle(cornerRadius: ToastStyle.cornerRadius)
                            .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
                    }
                }
        }
    }
}

// New view: CollapsibleGroupView
// MARK: - Hover Background Modifier (matching SettingsListView)
/// On macOS 26+, uses native glassEffect for hover state
/// On earlier versions, uses colored background
private struct HoverButtonBackgroundModifier: ViewModifier {
    let isHovered: Bool
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isHovered
                            ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                            : Color.clear)
            )
    }
}

struct CollapsibleGroupView: View {
    let group: GroupedNotes
    @ObservedObject var viewModel: RecentNotesViewModel
    @State private var isExpanded: Bool
    let onSelectNote: (String, URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Namespace private var groupNamespace

    // Default collapse for the "Earlier" group (i.e. .older case)
    init(group: GroupedNotes, viewModel: RecentNotesViewModel, onSelectNote: @escaping (String, URL) -> Void) {
        self.group = group
        self.viewModel = viewModel
        self.onSelectNote = onSelectNote
        // When search is active, always expand all groups
        if !viewModel.searchText.isEmpty {
            _isExpanded = State(initialValue: true)
        } else if group.group == .older {
            _isExpanded = State(initialValue: false)
        } else {
            _isExpanded = State(initialValue: true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header with disclosure indicator
            HStack(spacing: 0) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                    TimeGroupHeader(title: group.group.localized, notes: group.notes)
                .padding(.leading, -6)
            }
            .id("header-\(group.group.rawValue)")
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    isExpanded.toggle()
                }
            }

            // Only show the note rows when expanded - 使用 LazyVStack 实现懒加载
            if isExpanded {
                LazyVStack(spacing: 2) {
                    ForEach(group.notes) { note in
                        NoteRow(
                            note: note,
                            isHighLight: viewModel.highlightedNoteID == note.id,
                            onTap: {
                                onSelectNote(note.content, note.fileURL)
                                dismiss()
                            },
                            onHover: { isHovered in
                                viewModel.setHoveredNote(isHovered ? note.id : nil)
                            },
                            searchText: viewModel.searchText,
                            onToggleStar: {
                                viewModel.toggleStarred(note)
                            },
                            onDelete: {
                                viewModel.deleteNote(note)
                            },
                            wordCount: viewModel.cachedWordCount(for: note.id),
                            charCount: viewModel.cachedCharCount(for: note.id),
                            onAppearLoadMetrics: { viewModel.loadMetricsIfNeeded(for: note) }
                        )
                    }
                }
            }
        }
        .onChange(of: viewModel.searchText) { newValue in
            // When search text changes, expand all groups if search is active
            if !newValue.isEmpty {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    isExpanded = true
                }
            } else if group.group == .older {
                // Return to default collapsed state for "Earlier" group when search is cleared
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    isExpanded = false
                }
            }
        }
    }
}
