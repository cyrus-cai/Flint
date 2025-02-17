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

    // Get Archive directory
    var archiveDirectory: URL? {
        guard let floatDir = floatDirectory else { return nil }
        let archiveURL = floatDir.appendingPathComponent("Archived")
        if !fm.fileExists(atPath: archiveURL.path) {
            try? fm.createDirectory(at: archiveURL, withIntermediateDirectories: true)
        }
        return archiveURL
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

    // Add this method to get monthly archive folder
    func getMonthlyArchiveFolder() -> URL? {
        guard let archiveDir = archiveDirectory else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMM"
        let folderName = dateFormatter.string(from: Date())

        let monthFolder = archiveDir.appendingPathComponent(folderName)
        do {
            try fm.createDirectory(
                at: monthFolder, withIntermediateDirectories: true, attributes: nil)
            print("Created archive folder at: \(monthFolder.path)")
            return monthFolder
        } catch {
            print("Error creating archive folder: \(error)")
            return nil
        }
    }

    // Add archive note method
    func archiveNote(at sourceURL: URL) throws {
        print("Starting archive process...")
        print("Source file: \(sourceURL.path)")

        guard let monthFolder = getMonthlyArchiveFolder() else {
            print("Failed to create archive folders")
            throw NSError(
                domain: "FileManager", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create archive folders"])
        }

        let fileName = sourceURL.lastPathComponent
        let destinationURL = monthFolder.appendingPathComponent(fileName)

        // Check if source file exists
        guard fm.fileExists(atPath: sourceURL.path) else {
            print("Source file does not exist")
            throw NSError(
                domain: "FileManager", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Source file does not exist"])
        }

        print("Moving file to: \(destinationURL.path)")

        if fm.fileExists(atPath: destinationURL.path) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMddHHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let nameWithoutExtension = (fileName as NSString).deletingPathExtension
            let newFileName = "\(nameWithoutExtension)_\(timestamp).md"
            let newDestinationURL = monthFolder.appendingPathComponent(newFileName)

            print("File exists, using new name: \(newFileName)")
            try fm.moveItem(at: sourceURL, to: newDestinationURL)
        } else {
            try fm.moveItem(at: sourceURL, to: destinationURL)
        }

        print("Archive complete")
    }
}
