import ArgumentParser
import Foundation

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Full-text search across all notes."
    )

    @Argument(help: "Search query.")
    var query: String

    @Flag(name: .long, help: "Search title only.")
    var title: Bool = false

    @Flag(name: .long, help: "Output as JSON.")
    var json: Bool = false

    func run() throws {
        let fm = LocalFileManager.shared
        let allNotes = fm.getAllNotes()
        let queryLower = query.lowercased()

        var results: [(url: URL, matchLine: String)] = []
        for url in allNotes {
            if title {
                let name = url.deletingPathExtension().lastPathComponent
                if name.lowercased().contains(queryLower) {
                    results.append((url, name))
                }
            } else {
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                if content.lowercased().contains(queryLower) {
                    let firstMatch = content.components(separatedBy: .newlines)
                        .first { $0.lowercased().contains(queryLower) } ?? ""
                    results.append((url, firstMatch))
                }
            }
        }

        if json {
            let items: [[String: String]] = results.map {
                ["path": $0.url.path, "match": $0.matchLine, "title": $0.url.deletingPathExtension().lastPathComponent]
            }
            let data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            if results.isEmpty {
                print("No results for '\(query)'.")
            } else {
                for r in results {
                    print("\(r.url.deletingPathExtension().lastPathComponent)")
                    print("  \(r.url.path)")
                    if !r.matchLine.isEmpty {
                        print("  > \(r.matchLine.trimmingCharacters(in: .whitespaces))")
                    }
                    print()
                }
            }
        }
    }
}
