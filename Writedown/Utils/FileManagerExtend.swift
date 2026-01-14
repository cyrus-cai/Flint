import Foundation

private let kCustomNotesDirectoryPath = "CustomNotesDirectoryPath"
private let kMigrationCompletedKey = "MigrationCompleted"

extension Notification.Name {
    static let storageLocationDidChange = Notification.Name("storageLocationDidChange")
}

// MARK: - Recent Note Model
struct RecentNote: Identifiable {
    let id = UUID()
    let title: String
    let firstLinePreview: String  // Add this to store the first line separately
    let content: String
    let lastModified: Date
    let fileURL: URL
    let sourceApp: String?  // New field for source application
    var isStarred: Bool = false  // 新增的星标属性
}

class LocalFileManager {
    static let shared = LocalFileManager()
    let fm = Foundation.FileManager.default

    // Get current week folder name (e.g., "2024W50")
    public var currentWeekFolder: String {
        let calendar = Calendar(identifier: .iso8601)
        let today = Date()

        let week = calendar.component(.weekOfYear, from: today)
        let year = calendar.component(.yearForWeekOfYear, from: today)

        return "\(year)W\(String(format: "%02d", week))"
    }

    // Get base notes directory (Obsidian vault)
    var baseDirectory: URL? {
        // First check if user has set a custom path
        if let customPath = UserDefaults.standard.string(forKey: kCustomNotesDirectoryPath) {
            return URL(fileURLWithPath: customPath)
        }

        // If no custom path, use default path in Documents folder
        let fileManager = Foundation.FileManager.default
        guard
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            return nil
        }

        // Create default Writedown folder in Documents
        let defaultPath = documentsURL.appendingPathComponent("Writedown")

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: defaultPath.path) {
            try? fileManager.createDirectory(at: defaultPath, withIntermediateDirectories: true)
        }

        return defaultPath
    }

    // Get Float directory
    var floatDirectory: URL? {
        guard let base = baseDirectory else { return nil }
        // let floatURL = base.appendingPathComponent("Float")
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    // Get current week directory
    var currentWeekDirectory: URL? {
        guard let floatDir = floatDirectory else { return nil }
        let weekURL = floatDir.appendingPathComponent(currentWeekFolder)
        if !fm.fileExists(atPath: weekURL.path) {
            try? fm.createDirectory(at: weekURL, withIntermediateDirectories: true)
        }
        return weekURL
    }

    // Set custom directory (Obsidian vault)
    func setCustomDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: kCustomNotesDirectoryPath)

        // Create Float directory and current week directory
        if let floatDir = floatDirectory,
            let weekDir = currentWeekDirectory
        {
            try? fm.createDirectory(at: floatDir, withIntermediateDirectories: true)
            try? fm.createDirectory(at: weekDir, withIntermediateDirectories: true)

            // 只在未执行过迁移时执行
            if !UserDefaults.standard.bool(forKey: kMigrationCompletedKey) {
                migrateExistingNotes()
                // 标记迁移已完成
                UserDefaults.standard.set(true, forKey: kMigrationCompletedKey)
            }
        }

        NotificationCenter.default.post(name: .storageLocationDidChange, object: nil)
    }

    // Generate file URL for a note
    func fileURL(for title: String) -> URL? {
        guard let weekDir = currentWeekDirectory else { return nil }
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return weekDir.appendingPathComponent("\(sanitizedTitle).md")
    }

    // Get all notes from Float directory and its subdirectories
    func getAllNotes() -> [URL] {
        guard let floatDir = floatDirectory else { return [] }
        do {
            let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey]
            let enumerator = fm.enumerator(
                at: floatDir,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles])

            var notes: [URL] = []
            while let fileURL = enumerator?.nextObject() as? URL {
                // Skip Archived directory
                if fileURL.pathComponents.contains("Archived") {
                    enumerator?.skipDescendants()
                    continue
                }

                if fileURL.pathExtension == "md" {
                    notes.append(fileURL)
                }
            }
            return notes
        }
    }

    // Get current notes path for display
    var currentNotesPath: String {
        if let floatDir = floatDirectory {
            return floatDir.path
        }
        return "Not configured"
    }

    // Get notes directory (for Finder)
    var notesDirectory: URL? {
        return floatDirectory
    }

    // Add this method to the FileManager class

    func migrateExistingNotes() {
        guard let baseDir = baseDirectory else { return }
        let fileManager = Foundation.FileManager.default

        do {
            // 1. 获取所有 .md 文件
            let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey]
            let enumerator = fileManager.enumerator(
                at: baseDir,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles])

            var notesToMigrate: [URL] = []
            while let fileURL = enumerator?.nextObject() as? URL {
                // 跳过 Float 目录
                if fileURL.lastPathComponent == "Float" {
                    enumerator?.skipDescendants()
                    continue
                }

                // 只处理 .md 文件
                if fileURL.pathExtension == "md" {
                    notesToMigrate.append(fileURL)
                }
            }

            // 2. 移动文件到新的周目录
            for oldURL in notesToMigrate {
                // 获取文件属性以确定其创建时间
                let attributes = try fileManager.attributesOfItem(atPath: oldURL.path)
                let creationDate = attributes[.creationDate] as? Date ?? Date()

                // 根据创建时间确定周目录
                let calendar = Calendar.current
                let week = calendar.component(.weekOfYear, from: creationDate)
                let year = calendar.component(.year, from: creationDate)
                let weekFolder = "\(year)W\(String(format: "%02d", week))"

                // 创建目标目录
                // let floatURL = baseDir.appendingPathComponent("Float")
                let weekURL = baseDir.appendingPathComponent(weekFolder)
                try? fileManager.createDirectory(at: weekURL, withIntermediateDirectories: true)

                // 构建新的文件路径
                let newURL = weekURL.appendingPathComponent(oldURL.lastPathComponent)

                // 移动文件
                if !fileManager.fileExists(atPath: newURL.path) {
                    try fileManager.moveItem(at: oldURL, to: newURL)
                }
            }

        } catch {
            print("Migration error: \(error)")
        }
    }

    func getRecentNotes() -> [RecentNote] {
        do {
            let notes = self.getAllNotes()
            let resourceKeys = Set([URLResourceKey.contentModificationDateKey])

            var notesWithDates: [(URL, Date)] = []
            for url in notes {
                let resourceValues = try url.resourceValues(forKeys: resourceKeys)
                if let modificationDate = resourceValues.contentModificationDate {
                    notesWithDates.append((url, modificationDate))
                }
            }

            // Sort and limit
            notesWithDates.sort { $0.1 > $1.1 }
            let recentURLs = notesWithDates

            // Convert to RecentNote objects
            var recentNotes: [RecentNote] = []
            for (url, date) in recentURLs {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    // Get the filename without extension to use as the custom title
                    let filename = url.deletingPathExtension().lastPathComponent

                    // Get the first line for fallback if needed
                    let lines = content.components(separatedBy: .newlines)
                    let firstLine = lines.first?.isEmpty ?? true ? "Untitled" : lines[0]

                    // Extract source app from metadata comment if available
                    var sourceApp: String? = nil
                    
                    // Check for source metadata in the first line
                    if let firstLine = lines.first, firstLine.hasPrefix("<!-- Source:") {
                        // Look for the closing comment tag
                        if let endTagIndex = firstLine.range(of: "-->")?.lowerBound {
                            let startIndex = firstLine.index(firstLine.startIndex, offsetBy: 12) // Length of "<!-- Source: "
                            // Make sure the range is valid
                            if startIndex < endTagIndex {
                                sourceApp = String(firstLine[startIndex..<endTagIndex]).trimmingCharacters(in: .whitespaces)
                            }
                        }
                    }

                    // Use filename as the title (since that's what we set during title editing)
                    // but display the first line preview in the details
                    let note = RecentNote(
                        title: filename,
                        firstLinePreview: firstLine,
                        content: content,
                        lastModified: date,
                        fileURL: url,
                        sourceApp: sourceApp
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
