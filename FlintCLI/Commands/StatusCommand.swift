import ArgumentParser
import Foundation

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show notes directory info and update status as JSON."
    )

    func run() throws {
        let fm = LocalFileManager.shared
        let allNotes = fm.getAllNotes()
        let currentWeek = fm.currentWeekFolder
        let thisWeekNotes = allNotes.filter { $0.path.contains(currentWeek) }

        var statusDict: [String: Any] = [
            "version": kFlintCLIVersion,
            "notes_dir": fm.currentNotesPath,
            "current_week": currentWeek,
            "total_notes": allNotes.count,
            "this_week_notes": thisWeekNotes.count,
        ]

        // Check for latest version (synchronous bridge)
        let updater = AutoUpdater(currentVersion: kFlintCLIVersion)
        let semaphore = DispatchSemaphore(value: 0)
        var latestVersion: String? = nil
        var updateDescription: String? = nil

        Task {
            defer { semaphore.signal() }
            do {
                if let info = try await updater.checkForUpdates() {
                    latestVersion = info.version
                    updateDescription = info.description
                }
            } catch {
                // Network errors are not fatal for status
            }
        }
        _ = semaphore.wait(timeout: .now() + 5) // 5 second timeout

        statusDict["latest_version"] = latestVersion ?? kFlintCLIVersion
        statusDict["update_available"] = latestVersion != nil
        if let desc = updateDescription {
            statusDict["update_summary"] = desc
        }

        let data = try JSONSerialization.data(withJSONObject: statusDict, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
