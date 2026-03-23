import ArgumentParser
import Foundation

struct ReadNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read a note by title or path."
    )

    @Argument(help: "Note title (without .md) or full file path.")
    var identifier: String

    func run() throws {
        let url = try resolveNote(identifier)
        let content = try String(contentsOf: url, encoding: .utf8)
        print(content)
    }
}
