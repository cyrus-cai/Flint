import ArgumentParser
import Foundation

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new note with the given text."
    )

    @Argument(help: "The note content.")
    var text: [String] = []

    @Flag(name: .long, help: "Read content from stdin.")
    var stdin: Bool = false

    mutating func run() throws {
        var content: String
        if stdin {
            var lines: [String] = []
            while let line = readLine(strippingNewline: false) {
                lines.append(line)
            }
            content = lines.joined()
        } else {
            content = text.joined(separator: " ")
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FlintError("No content provided. Usage: flint create \"your note text\"")
        }

        let fm = LocalFileManager.shared

        // Use first line (truncated) as title, or timestamp if too short
        let firstLine = content.components(separatedBy: .newlines).first ?? ""
        let title: String
        if firstLine.count > 2 && firstLine.count <= 60 {
            title = firstLine
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HHmmss"
            title = formatter.string(from: Date())
        }

        guard let fileURL = fm.fileURL(for: title) else {
            throw FlintError("Could not determine notes directory.")
        }
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FlintError("Note already exists: \(fileURL.lastPathComponent)")
        }

        let fullContent = "<!-- Source: CLI -->\n\(content)"
        try fullContent.write(to: fileURL, atomically: true, encoding: .utf8)
        print(fileURL.path)
    }
}
