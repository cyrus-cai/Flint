import Foundation

struct FlintError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func resolveNote(_ identifier: String) throws -> URL {
    if identifier.hasPrefix("/") {
        let url = URL(fileURLWithPath: identifier).standardizedFileURL
        // Restrict absolute paths to the notes directory
        guard let notesDir = LocalFileManager.shared.floatDirectory else {
            throw FlintError("Notes directory not configured.")
        }
        let notesPrefix = notesDir.standardizedFileURL.path
        guard url.path.hasPrefix(notesPrefix + "/") || url.path == notesPrefix else {
            throw FlintError("Path is outside the Flint notes directory.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FlintError("File not found: \(identifier)")
        }
        return url
    }

    let fm = LocalFileManager.shared
    let allNotes = fm.getAllNotes()
    let searchName = identifier.hasSuffix(".md") ? identifier : "\(identifier).md"

    let matches = allNotes.filter {
        $0.lastPathComponent.caseInsensitiveCompare(searchName) == .orderedSame
    }

    guard !matches.isEmpty else {
        throw FlintError("Note not found: '\(identifier)'. Use `flint list` to see available notes.")
    }

    if matches.count > 1 {
        FileHandle.standardError.write(Data("Warning: Multiple notes match '\(identifier)'. Using most recent.\n".utf8))
        let sorted = matches.sorted { url1, url2 in
            let d1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let d2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return d1 > d2
        }
        return sorted.first!
    }

    return matches.first!
}
