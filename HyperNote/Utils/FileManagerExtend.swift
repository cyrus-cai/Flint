//
//  FileManagerExtend.swift
//  Hyper Note
//
//  Created by LC John on 2024/11/26.
//

import Foundation

private let kCustomNotesDirectoryPath = "CustomNotesDirectoryPath"

extension Notification.Name {
    static let storageLocationDidChange = Notification.Name("storageLocationDidChange")
}

class FileManager {
    static let shared = FileManager()
    let fm = Foundation.FileManager.default

    // 获取应用程序文档目录
    var documentsDirectory: URL {
        let paths = fm.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    // 获取应用程序专用的笔记存储目录
    var notesDirectory: URL? {
        guard let customPath = UserDefaults.standard.string(forKey: kCustomNotesDirectoryPath) else {
            return nil
        }
        let customURL = URL(fileURLWithPath: customPath)
        if !fm.fileExists(atPath: customURL.path) {
            try? fm.createDirectory(at: customURL, withIntermediateDirectories: true)
        }
        return customURL
    }

    // 设置自定义路径
    func setCustomDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: kCustomNotesDirectoryPath)
        NotificationCenter.default.post(name: .storageLocationDidChange, object: nil)
    }

    // 重置为默认路径
    func resetToDefaultDirectory() {
        UserDefaults.standard.removeObject(forKey: kCustomNotesDirectoryPath)
        NotificationCenter.default.post(name: .storageLocationDidChange, object: nil)
    }

    // 获取当前路径
    var currentNotesPath: String {
        return notesDirectory?.path ?? "Not configured"
    }

    // Check if using custom path
    var isUsingCustomPath: Bool {
        return UserDefaults.standard.string(forKey: kCustomNotesDirectoryPath) != nil
    }

    // 根据标题生成文件路径
    func fileURL(for title: String) -> URL? {
        guard let directory = notesDirectory else { return nil }
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent("\(sanitizedTitle).md")
    }

    // 检查文件是否存在
    func fileExists(at url: URL) -> Bool {
        return fm.fileExists(atPath: url.path)
    }

    // Add new method to check if path is configured
    var isPathConfigured: Bool {
        return UserDefaults.standard.string(forKey: kCustomNotesDirectoryPath) != nil
    }

    func migrateFilesFromDefaultLocation(to newLocation: URL) {
        let defaultLocation = documentsDirectory.appendingPathComponent("HyperNote")

        // Check if default directory exists
        guard fm.fileExists(atPath: defaultLocation.path) else { return }

        do {
            // Get all files from default directory
            let files = try fm.contentsOfDirectory(at: defaultLocation,
                                                 includingPropertiesForKeys: nil)

            // Create new directory if it doesn't exist
            if !fm.fileExists(atPath: newLocation.path) {
                try fm.createDirectory(at: newLocation,
                                     withIntermediateDirectories: true)
            }

            // Move each file
            for file in files {
                var fileName = file.lastPathComponent

                // Convert .txt to .md
                if fileName.hasSuffix(".txt") {
                    fileName = fileName.replacingOccurrences(of: ".txt", with: ".md")
                }

                let destination = newLocation.appendingPathComponent(fileName)

                // If file already exists in destination, skip it
                if !fm.fileExists(atPath: destination.path) {
                    try fm.moveItem(at: file, to: destination)
                }
            }

            // Try to remove the old directory
            try fm.removeItem(at: defaultLocation)
        } catch {
            print("Migration error: \(error.localizedDescription)")
        }
    }
}
