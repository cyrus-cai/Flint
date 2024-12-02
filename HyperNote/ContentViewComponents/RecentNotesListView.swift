import SwiftUI
import Foundation

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
    
    init() {
        notes = FileManager.getRecentNotes()
    }
    
    func deleteNote(_ note: RecentNote) {
        do {
            try Foundation.FileManager.default.removeItem(at: note.fileURL)
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes.remove(at: index)
            }
        } catch {
            print("Error deleting note: \(error)")
        }
    }
}

// MARK: - Recent Notes List View
struct RecentNotesListView: View {
    let notes: [RecentNote]
    let onSelectNote: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = RecentNotesViewModel()
    
    private func openInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: FileManager.shared.notesDirectory.path)
    }

    var body: some View {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.notes) { note in
                            NoteRow(note: note, onTap: {
                                onSelectNote(note.content)
                                dismiss()
                            }, onDelete: {
                                viewModel.deleteNote(note)
                            })
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 400)
                
                Button(action: openInFinder) {
                    HStack {
                        Text("Show All")
                            .font(.system(size: 14))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
            }
            .frame(width: 280)
            .background(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95))
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
//
        }
}

// MARK: - Note Row View
struct NoteRow: View {
    let note: RecentNote
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    private func getRelativeTime(from date: Date) -> String {
        let now = Date()
        let diffInSeconds = Int(now.timeIntervalSince(date))
        let diffInMinutes = diffInSeconds / 60
        let diffInHours = diffInMinutes / 60
        let diffInDays = diffInHours / 24
        
        if diffInMinutes < 1 {
            return "less than 1 min"
        } else if diffInMinutes < 60 {
            return "\(diffInMinutes) min"
        } else if diffInHours < 24 {
            return "\(diffInHours) hr \(diffInMinutes-diffInDays*24*60-diffInHours*60) min"
        } else {
            return "\(diffInDays) day \(diffInHours-diffInDays*24) hr"
        }
    }
    
    var body: some View {
        HStack {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(getRelativeTime(from: note.lastModified))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
//                        .foregroundColor(.red)
                        .font(.system(size: 13))
                        .padding(.horizontal,2)
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ?
                    (colorScheme == .dark ? Color(white: 0.3) : Color(white: 0.85)) :
                    Color.clear)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        )
        .onHover { hovering in
            withAnimation {
                isHovered = hovering
            }
        }
    }
}

// MARK: - File Manager Extension
extension FileManager {
    static func getRecentNotes() -> [RecentNote] {
        do {
            let notesURL = FileManager.shared.notesDirectory
            let resourceKeys = Set([URLResourceKey.contentModificationDateKey])
            let fileManager = Foundation.FileManager.default
            // 获取目录内容
            let fileURLs = try Foundation.FileManager.default.contentsOfDirectory(
                at: notesURL,
                includingPropertiesForKeys: Array(resourceKeys)
            )
            
            // 过滤并获取文件信息
            var notesWithDates: [(URL, Date)] = []
            for url in fileURLs {
                if url.pathExtension == "txt" {
                    let resourceValues = try url.resourceValues(forKeys: resourceKeys)
                    if let modificationDate = resourceValues.contentModificationDate {
                        notesWithDates.append((url, modificationDate))
                    }
                }
            }
            
            // 排序并限制数量
            notesWithDates.sort { $0.1 > $1.1 }
            let recentURLs = notesWithDates.prefix(50)
            
            // 转换为 RecentNote 对象
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
