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

// MARK: - Recent Notes List View
struct RecentNotesListView: View {
    let notes: [RecentNote]
//    let onSelectNote: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
//    let fileManager = FileManager.default
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(notes) { note in
                NoteRow(note: note) {
//                    onSelectNote(note.content)
                    dismiss()
                }
                
                if note.id != notes.last?.id {
                    Divider()
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(width: 280)
        .background(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Note Row View
struct NoteRow: View {
    let note: RecentNote
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(note.lastModified, style: .relative)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
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
            let recentURLs = notesWithDates.prefix(4)
            
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
