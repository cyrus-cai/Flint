//
//  FileManagerExtend.swift
//  Hyper Note
//
//  Created by LC John on 2024/11/26.
//

import Foundation

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
        let notesPath = documentsDirectory.appendingPathComponent("HyperNote", isDirectory: true)
        if !fm.fileExists(atPath: notesPath.path) {
            try? fm.createDirectory(at: notesPath, withIntermediateDirectories: true)
        }
        return notesPath
    }
    
    // 根据标题生成文件路径
    func fileURL(for title: String) -> URL {
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return notesDirectory.appendingPathComponent("\(sanitizedTitle).txt")
    }
    
    // 检查文件是否存在
    func fileExists(at url: URL) -> Bool {
        return fm.fileExists(atPath: url.path)
    }
}
