import ArgumentParser
import Foundation

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List notes, optionally filtered by week."
    )

    @Option(name: .long, help: "Filter by ISO week (e.g., 2026W12).")
    var week: String?

    @Option(name: .long, help: "Maximum number of notes to show.")
    var limit: Int?

    @Flag(name: .long, help: "Output as JSON.")
    var json: Bool = false

    func run() throws {
        let fm = LocalFileManager.shared
        var notes = fm.getRecentNotes()

        if let week = week {
            notes = notes.filter { $0.fileURL.path.contains(week) }
        }

        if let limit = limit {
            guard limit >= 0 else {
                throw FlintError("--limit must be non-negative.")
            }
            notes = Array(notes.prefix(limit))
        }

        if json {
            let formatter = ISO8601DateFormatter()
            let items: [[String: Any]] = notes.map { note in
                [
                    "title": note.title,
                    "preview": note.firstLinePreview,
                    "path": note.fileURL.path,
                    "modified": formatter.string(from: note.lastModified),
                    "source": note.sourceApp ?? "",
                    "type": note.noteType ?? "",
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            if notes.isEmpty {
                print("No notes found.")
                return
            }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            for note in notes {
                print("\(dateFormatter.string(from: note.lastModified))  \(note.title)")
            }
        }
    }
}
