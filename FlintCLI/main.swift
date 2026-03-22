import ArgumentParser

struct FlintCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flint",
        abstract: "Flint — a local-first note-taking tool. Notes are plain Markdown files organized by ISO week.",
        version: kFlintCLIVersion,
        subcommands: [
            Create.self,
            List.self,
            Search.self,
            ReadNote.self,
            EditNote.self,
            Remove.self,
            Status.self,
        ],
        defaultSubcommand: Create.self
    )
}

FlintCLI.main()
