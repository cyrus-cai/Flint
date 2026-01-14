//
//  AutoUpdate.swift
//  Hyper Note
//
//  Created by LC John on 2024/11/29.
//

import Cocoa
import Combine
import Foundation

class AutoUpdater {
    // ⚠️ 请替换为您 Vercel Blob 中 latest.json 的实际公开链接
    // 例如: "https://public.blob.vercel-storage.com/your-store-id/latest.json"
    private let versionCheckURL = URL(string: "https://wfcpsam37fc4yuvn.public.blob.vercel-storage.com/latest.json")!

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
            .appendingPathComponent("Writedown")
            .appendingPathComponent("Updates")
    }

    // 检查更新
    func checkForUpdates() async throws -> UpdateInfo? {
        // 防止缓存，添加时间戳参数 (可选，视 Vercel 缓存策略而定)
        var urlComponents = URLComponents(url: versionCheckURL, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [URLQueryItem(name: "t", value: "\(Date().timeIntervalSince1970)")]
        let url = urlComponents?.url ?? versionCheckURL

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        
        print("Checking for updates at: \(url)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            print("Failed to fetch version info. Status: \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        let updateInfo = try JSONDecoder().decode(UpdateInfo.self, from: data)
        print("Remote version info: \(updateInfo)")

        // 只有当有新版本时才返回 updateInfo
        return compareVersions(updateInfo.version, isGreaterThan: currentVersion) ? updateInfo : nil
    }

    private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        let progressHandler: (Double) -> Void

        init(progressHandler: @escaping (Double) -> Void) {
            self.progressHandler = progressHandler
        }

        // 下载进度更新时调用
        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            if totalBytesExpectedToWrite > 0 {
                let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                progressHandler(progress)
            }
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            // 文件移动在外部处理
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            if let error = error {
                print("Download error: \(error)")
            }
        }
    }

    func downloadUpdate(from url: URL) async throws -> URL {
        let fileManager = Foundation.FileManager.default
        try fileManager.createDirectory(
            at: downloadDirectory,
            withIntermediateDirectories: true)

        let destinationURL = downloadDirectory.appendingPathComponent("update.zip")

        // 清理旧文件
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        // 创建带代理的 URLSession
        let delegate = DownloadDelegate(progressHandler: { [weak self] progress in
            self?.progressSubject.send(progress)
        })
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        // 执行下载
        print("Downloading update from: \(url)")
        let (downloadURL, response) = try await session.download(from: url)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Download failed with status: \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        try fileManager.moveItem(at: downloadURL, to: destinationURL)
        progressSubject.send(1.0)  // 发送完成进度
        return destinationURL
    }

    func installUpdate(from updateFile: URL) throws {
        let fileManager = Foundation.FileManager.default

        // 清理并创建解压目录
        let updateDirectory = downloadDirectory.appendingPathComponent("extracted")
        if fileManager.fileExists(atPath: updateDirectory.path) {
            try fileManager.removeItem(at: updateDirectory)
        }
        try fileManager.createDirectory(at: updateDirectory, withIntermediateDirectories: true)

        // 解压更新包
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

        // 获取应用程序目录路径
        guard let applicationsDirectory = fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first else {
            throw UpdateError.invalidAppPath
        }

        let newAppPath = updateDirectory.appendingPathComponent("Writedown.app")
        let targetAppPath = applicationsDirectory.appendingPathComponent("Writedown.app")
        
        // 简单验证解压是否成功
        if !fileManager.fileExists(atPath: newAppPath.path) {
            print("Error: Writedown.app not found in extracted files. Found: \(try? fileManager.contentsOfDirectory(atPath: updateDirectory.path))")
            throw UpdateError.invalidUpdateFile
        }

        // 直接执行更新操作
        DispatchQueue.main.async {
            do {
                let scriptContent = """
                    #!/bin/bash
                    sleep 2  # 等待当前应用退出
                    rm -rf "\(targetAppPath.path)"  # 删除旧版本
                    cp -R "\(newAppPath.path)" "\(targetAppPath.path)"  # 复制新版本
                    rm -rf "\(self.downloadDirectory.path)"  # 清理下载文件
                    open "\(targetAppPath.path)"  # 启动新版本
                    """

                let scriptURL = self.downloadDirectory.appendingPathComponent("update_script.sh")
                try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)

                let chmodProcess = Process()
                chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmodProcess.arguments = ["755", scriptURL.path]
                try chmodProcess.run()
                chmodProcess.waitUntilExit()

                let updateTask = Process()
                updateTask.executableURL = URL(fileURLWithPath: "/bin/bash")
                updateTask.arguments = [scriptURL.path]
                try updateTask.run()

                NSApplication.shared.terminate(nil)
            } catch {
                print("Update installation error:", error)
                let errorAlert = NSAlert(error: error)
                errorAlert.runModal()
            }
        }
    }

    // 更新错误枚举
    enum UpdateError: Error {
        case invalidAppPath
        case shellCommandFailed
        case invalidUpdateFile
        case updateInstallationFailed

        var localizedDescription: String {
            switch self {
            case .invalidAppPath:
                return "Unable to obtain application path"
            case .shellCommandFailed:
                return "Failed to execute update command"
            case .invalidUpdateFile:
                return "The update file is invalid or corrupted"
            case .updateInstallationFailed:
                return "Installation of update failed"
            }
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
    
    // In the AutoUpdater class, add a helper method to return the cached update file (if it exists).
    func cachedUpdateFile() -> URL? {
        let fileManager = Foundation.FileManager.default
        let destinationURL = downloadDirectory.appendingPathComponent("update.zip")
        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        return nil
    }

    // New method to delete the downloaded update package
    func deleteDownloadedUpdatePackage() throws {
        let fileManager = Foundation.FileManager.default
        let destinationURL = downloadDirectory.appendingPathComponent("update.zip")
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
            print("Deleted downloaded update package.")
        } else {
            print("No downloaded update package found.")
        }
    }
}

// 更新信息模型
struct UpdateInfo: Codable {
    let version: String
    let downloadURL: String
    let lastUpdated: String
    let description: String
}

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var newVersionAvailable: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var remoteVersion: String? = nil

    private let updater = AutoUpdater()
    private var progressSubscription: AnyCancellable?

    private init() {}

    func checkAndDownloadUpdate() {
        Task {
            do {
                if let updateInfo = try await updater.checkForUpdates() {
                    DispatchQueue.main.async {
                        self.isDownloading = true
                        self.downloadProgress = 0
                        self.remoteVersion = updateInfo.version
                    }
                    self.progressSubscription = updater.progressPublisher
                        .receive(on: RunLoop.main)
                        .sink { progress in
                            self.downloadProgress = progress
                        }
                    guard let downloadURL = URL(string: updateInfo.downloadURL) else {
                        throw URLError(.badURL)
                    }
                    _ = try await updater.downloadUpdate(from: downloadURL)
                    self.progressSubscription?.cancel()
                    DispatchQueue.main.async {
                        self.isDownloading = false
                        self.newVersionAvailable = true
                    }
                }
            } catch {
                print("Error checking or downloading update: \(error)")
            }
        }
    }

    func installUpdatePackage() {
        Task {
            do {
                if let cachedFile = self.updater.cachedUpdateFile() {
                    try self.updater.installUpdate(from: cachedFile)
                } else if let updateInfo = try await self.updater.checkForUpdates(),
                          let downloadURL = URL(string: updateInfo.downloadURL) {
                    DispatchQueue.main.async {
                        self.newVersionAvailable = true
                        self.isDownloading = true
                        self.downloadProgress = 0
                    }
                    self.progressSubscription = self.updater.progressPublisher
                        .receive(on: RunLoop.main)
                        .sink { progress in
                            self.downloadProgress = progress
                        }
                    let updateFile = try await self.updater.downloadUpdate(from: downloadURL)
                    self.progressSubscription?.cancel()
                    try self.updater.installUpdate(from: updateFile)
                    DispatchQueue.main.async {
                        self.isDownloading = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert(error: error)
                    alert.runModal()
                }
            }
        }
    }
}
