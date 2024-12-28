import Foundation

private let kCustomNotesDirectoryPath = "CustomNotesDirectoryPath"
private let kMigrationCompletedKey = "MigrationCompleted"

extension Notification.Name {
    static let storageLocationDidChange = Notification.Name("storageLocationDidChange")
}

class FileManager {
    static let shared = FileManager()
    let fm = Foundation.FileManager.default

    // Get current week folder name (e.g., "2024W50")
    public var currentWeekFolder: String {
        let calendar = Calendar.current
        let today = Date()
        let week = calendar.component(.weekOfYear, from: today)
        let year = calendar.component(.year, from: today)
        return "\(year)W\(String(format: "%02d", week))"
    }

    // Get base notes directory (Obsidian vault)
    var baseDirectory: URL? {
        guard let customPath = UserDefaults.standard.string(forKey: kCustomNotesDirectoryPath)
        else {
            return nil
        }
        return URL(fileURLWithPath: customPath)
    }

    // Get Float directory
    var floatDirectory: URL? {
        guard let base = baseDirectory else { return nil }
        let floatURL = base.appendingPathComponent("Float")
        if !fm.fileExists(atPath: floatURL.path) {
            try? fm.createDirectory(at: floatURL, withIntermediateDirectories: true)
        }
        return floatURL
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
                if fileURL.pathExtension == "md" {
                    notes.append(fileURL)
                }
            }
            return notes
        } catch {
            print("Error getting notes: \(error)")
            return []
        }
    }

    // Check if path is configured
    var isPathConfigured: Bool {
        return baseDirectory != nil
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
                let floatURL = baseDir.appendingPathComponent("Float")
                let weekURL = floatURL.appendingPathComponent(weekFolder)
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
}
