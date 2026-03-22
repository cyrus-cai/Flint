import ArgumentParser
import Foundation

struct EditNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Update an existing note."
    )

    @Argument(help: "Note title or path.")
    var identifier: String

    @Flag(name: .long, help: "Append to note instead of replacing.")
    var append: Bool = false

    @Flag(name: .long, help: "Read new content from stdin.")
    var stdin: Bool = false

    @Option(name: .long, help: "New content string.")
    var content: String?

    func run() throws {
        let url = try resolveNote(identifier)

        var newContent: String
        if stdin {
            var lines: [String] = []
            while let line = readLine(strippingNewline: false) {
                lines.append(line)
            }
            newContent = lines.joined()
        } else if let c = content {
            newContent = c
        } else {
            throw FlintError("Provide --content \"text\" or --stdin.")
        }

        if append {
            let existing = try String(contentsOf: url, encoding: .utf8)
            newContent = existing + "\n" + newContent
        }

        try newContent.write(to: url, atomically: true, encoding: .utf8)
        print(url.path)
    }
}
