import ArgumentParser
import Foundation

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Delete a note."
    )

    @Argument(help: "Note title or path.")
    var identifier: String

    @Flag(name: .long, help: "Skip confirmation prompt.")
    var force: Bool = false

    func run() throws {
        let url = try resolveNote(identifier)

        if !force {
            print("Delete \(url.lastPathComponent)? [y/N]", terminator: " ")
            guard readLine()?.lowercased() == "y" else {
                print("Cancelled.")
                return
            }
        }

        try FileManager.default.removeItem(at: url)
        print("Deleted: \(url.path)")
    }
}
