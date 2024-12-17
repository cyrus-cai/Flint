//
//  FileManagerExtend.swift
//  Hyper Note
//
//  Created by LC John on 2024/11/26.
//

import Foundation

private let kCustomNotesDirectoryPath = "CustomNotesDirectoryPath"

class FileManager {
    static let shared = FileManager()
    let fm = Foundation.FileManager.default

    // 获取应用程序文档目录
    var documentsDirectory: URL {
        let paths = fm.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    // 获取应用程序专用的笔记存储目录
    var notesDirectory: URL {
        if let customPath = UserDefaults.standard.string(forKey: kCustomNotesDirectoryPath) {
            let customURL = URL(fileURLWithPath: customPath)
            if !fm.fileExists(atPath: customURL.path) {
                try? fm.createDirectory(at: customURL, withIntermediateDirectories: true)
            }
            return customURL
        }

        // Default path if no custom path is set
        let defaultPath = documentsDirectory.appendingPathComponent("obsidian/Float", isDirectory: true)
        if !fm.fileExists(atPath: defaultPath.path) {
            try? fm.createDirectory(at: defaultPath, withIntermediateDirectories: true)
        }
        return defaultPath
    }

    // 设置自定义路径
    func setCustomNotesDirectory(_ path: String) {
        UserDefaults.standard.set(path, forKey: kCustomNotesDirectoryPath)
    }

    // 重置为默认路径
    func resetToDefaultDirectory() {
        UserDefaults.standard.removeObject(forKey: kCustomNotesDirectoryPath)
    }

    // 获取当前路径
    var currentNotesPath: String {
        return notesDirectory.path
    }

    // Check if using custom path
    var isUsingCustomPath: Bool {
        return UserDefaults.standard.string(forKey: kCustomNotesDirectoryPath) != nil
    }

    // 根据标题生成文件路径
    func fileURL(for title: String) -> URL {
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return notesDirectory.appendingPathComponent("\(sanitizedTitle).md")
    }

    // 检查文件是否存在
    func fileExists(at url: URL) -> Bool {
        return fm.fileExists(atPath: url.path)
    }
}
