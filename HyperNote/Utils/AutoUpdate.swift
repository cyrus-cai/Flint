//
//  AutoUpdate.swift
//  Hyper Note
//
//  Created by LC John on 2024/11/29.
//

import Foundation
import Cocoa
import Combine

class AutoUpdater {
    // 版本信息接口地址
    private let versionCheckURL = "https://www.figa.asia/api/version"
    // 当前应用版本
    private var currentVersion: String
    // 临时下载目录
    private let downloadDirectory: URL
    
    private let progressSubject = PassthroughSubject<Double, Never>()
    var progressPublisher: AnyPublisher<Double, Never> {
        progressSubject.eraseToAnyPublisher()
    }
    
    
    init() {
        // 从 Info.plist 获取当前版本
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            self.currentVersion = version
        } else {
            self.currentVersion = "0.1.0"
        }
        
        // 设置下载目录
        self.downloadDirectory = Foundation.FileManager.default.temporaryDirectory
            .appendingPathComponent("HyperNote")
            .appendingPathComponent("Updates")
    }
    
    // 检查更新
    func checkForUpdates() async throws -> UpdateInfo? {
            let (data, _) = try await URLSession.shared.data(from: URL(string: versionCheckURL)!)
            let updateInfo = try JSONDecoder().decode(UpdateInfo.self, from: data)
            
            print(updateInfo,"updateInfo")
            
            // 只有当有新版本时才返回 updateInfo
            return compareVersions(updateInfo.version, isGreaterThan: currentVersion) ? updateInfo : nil
        }
    
    private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        let progressHandler: (Double) -> Void
        
        init(progressHandler: @escaping (Double) -> Void) {
            self.progressHandler = progressHandler
        }
        
        // 下载进度更新时调用
        func urlSession(_ session: URLSession,
                       downloadTask: URLSessionDownloadTask,
                       didWriteData bytesWritten: Int64,
                       totalBytesWritten: Int64,
                       totalBytesExpectedToWrite: Int64) {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressHandler(progress)
        }
        
        // 下载完成时调用（必需实现的方法）
        func urlSession(_ session: URLSession,
                       downloadTask: URLSessionDownloadTask,
                       didFinishDownloadingTo location: URL) {
            // 这个方法是必需的，但在我们的实现中不需要做任何事
            // 因为我们在 downloadUpdate 方法中处理文件移动
        }
        
        // 可选：处理下载完成或错误
        func urlSession(_ session: URLSession,
                       task: URLSessionTask,
                       didCompleteWithError error: Error?) {
            if let error = error {
                print("Download error: \(error)")
            }
        }
    }
    
    func downloadUpdate(from url: URL) async throws -> URL {
        let fileManager = Foundation.FileManager.default
        try fileManager.createDirectory(at: downloadDirectory,
                                      withIntermediateDirectories: true)
        
        let destinationURL = downloadDirectory.appendingPathComponent("update.zip")
        
        // Check if the file already exists
        if fileManager.fileExists(atPath: destinationURL.path) {
            print("Update package already exists, using existing file")
            progressSubject.send(1.0) // 如果文件已存在，直接发送完成进度
            return destinationURL
        }
        
        // 创建带代理的 URLSession
        let delegate = DownloadDelegate(progressHandler: { [weak self] progress in
            self?.progressSubject.send(progress)
        })
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        
        // 执行下载
        let (downloadURL, _) = try await session.download(from: url)
        
        // 如果目标位置已存在文件，先删除
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try fileManager.moveItem(at: downloadURL, to: destinationURL)
        progressSubject.send(1.0) // 发送完成进度
        return destinationURL
    }

    
    func installUpdate(from updateFile: URL) throws {
        let fileManager = Foundation.FileManager.default
        
        // Clean and create extraction directory
        let updateDirectory = downloadDirectory.appendingPathComponent("extracted")
        print(updateDirectory, "updateDirectory")
        if fileManager.fileExists(atPath: updateDirectory.path) {
            try fileManager.removeItem(at: updateDirectory)
        }
        try fileManager.createDirectory(at: updateDirectory,
                                        withIntermediateDirectories: true)
        
        // Extract files
        print("Extracting update file...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = [updateFile.path, "-d", updateDirectory.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            print("Unzip output:", output)
        }
        
        if process.terminationStatus != 0 {
            throw UpdateError.shellCommandFailed
        }
        
        guard let currentAppPath = Bundle.main.bundleURL.path.removingPercentEncoding,
              !currentAppPath.isEmpty else {
            throw UpdateError.invalidAppPath
        }
        
        let newAppPath = updateDirectory.appendingPathComponent("HyperNote.app").path
        guard fileManager.fileExists(atPath: newAppPath) else {
            throw UpdateError.invalidUpdateFile
        }
        
        // 获取应用程序文件夹路径
        guard let applicationsDirectory = fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first else {
            throw UpdateError.invalidAppPath
        }
        
        // 构建目标路径
        let targetAppPath = applicationsDirectory.appendingPathComponent("HyperNote.app")
        
        // 在主队列中执行更新操作
        DispatchQueue.main.async { [self] in
            do {
                // 复制新版本到临时位置
                let tempAppPath = self.downloadDirectory.appendingPathComponent("HyperNote.app")
                if fileManager.fileExists(atPath: tempAppPath.path) {
                    try fileManager.removeItem(at: tempAppPath)
                }
                try fileManager.copyItem(at: URL(fileURLWithPath: newAppPath), to: tempAppPath)
                
                // 请求用户授权移动应用
                let alert = NSAlert()
                alert.messageText = "更新准备就绪"
                alert.informativeText = "新版本已下载完成。点击确定开始安装更新。"
                alert.addButton(withTitle: "确定")
                alert.addButton(withTitle: "取消")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    // 用户确认后，打开新版本
                    NSWorkspace.shared.open(tempAppPath)
                    
                    // 清理更新文件夹
                    do {
                        try fileManager.removeItem(at: self.downloadDirectory)
                        print("Update files cleaned up successfully")
                    } catch {
                        print("Error cleaning up update files: \(error)")
                    }
                    
                    // 退出当前应用
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                print("Update installation error:", error)
                // 显示错误信息
                let errorAlert = NSAlert(error: error)
                errorAlert.runModal()
            }
        }}

    // 更新错误枚举
    enum UpdateError: Error {
        case invalidAppPath
        case shellCommandFailed
        case invalidUpdateFile
        case updateInstallationFailed
        
        var localizedDescription: String {
            switch self {
            case .invalidAppPath:
                return "无法获取应用路径"
            case .shellCommandFailed:
                return "执行更新命令失败"
            case .invalidUpdateFile:
                return "更新文件无效或已损坏"
            case .updateInstallationFailed:
                return "安装更新失败"
            }
        }
    }
    
    // 执行 shell 命令
    private func shell(_ command: String) throws {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        // 如果命令是 unzip，直接使用 unzip 可执行文件
        if command.starts(with: "unzip") {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            // 将命令转换为参数数组
            let components = command.components(separatedBy: " ")
            let args = components.dropFirst().map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            process.arguments = Array(args)
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("Process output:", output)
            }
            
            if process.terminationStatus != 0 {
                print("Process failed with status:", process.terminationStatus)
                throw UpdateError.shellCommandFailed
            }
        } catch {
            print("Process execution error:", error)
            throw UpdateError.shellCommandFailed
        }
    }
    
    // 比较版本号
    private func compareVersions(_ version1: String, isGreaterThan version2: String) -> Bool {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(v1Components.count, v2Components.count)
        
        for i in 0..<maxLength {
            let v1 = i < v1Components.count ? v1Components[i] : 0
            let v2 = i < v2Components.count ? v2Components[i] : 0
            
            if v1 > v2 {
                return true
            } else if v1 < v2 {
                return false
            }
        }
        return false
    }
}

// 更新信息模型
struct UpdateInfo: Codable {
    let version: String
    let downloadURL: String
    let lastUpdated: String
}

// 更新错误枚举
enum UpdateError: Error {
    case invalidAppPath
    case shellCommandFailed
    case invalidUpdateFile
    case helperCompilationFailed
    
    var localizedDescription: String {
        switch self {
        case .invalidAppPath:
            return "无法获取应用路径"
        case .shellCommandFailed:
            return "执行更新命令失败"
        case .invalidUpdateFile:
            return "更新文件无效或已损坏"
        case .helperCompilationFailed:
            return "更新辅助工具创建失败"
        }
    }
}
