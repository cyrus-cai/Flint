//
//  AutoUpdate.swift
//  Flint
//
//  Created by LC John on 2024/11/29.
//

#if canImport(AppKit)
import Cocoa
import Combine
#endif
import Foundation

class AutoUpdater {
    private let releaseFeedURL = URL(string: "https://api.github.com/repos/cyrus-cai/Flint/releases?per_page=20")!
    private let releaseAssetName = "Flint.zip"

    private var currentVersion: String
    private let downloadDirectory: URL

    #if canImport(AppKit)
    private let progressSubject = PassthroughSubject<Double, Never>()
    var progressPublisher: AnyPublisher<Double, Never> {
        progressSubject.eraseToAnyPublisher()
    }
    #endif

    init(currentVersion: String? = nil) {
        if let version = currentVersion {
            self.currentVersion = version
        } else if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            self.currentVersion = version
        } else {
            self.currentVersion = "0.1.0"
        }

        self.downloadDirectory = Foundation.FileManager.default.temporaryDirectory
            .appendingPathComponent("Flint")
            .appendingPathComponent("Updates")
    }

    func checkForUpdates() async throws -> UpdateInfo? {
        var request = URLRequest(
            url: releaseFeedURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let releases = try decoder.decode([GitHubRelease].self, from: data)

        // Determine if this build is a beta release.
        // Check the FlintReleaseChannel plist key (set by release.sh).
        // If absent (older builds before this key was introduced), assume beta
        // since all published versions so far are beta.
        let channel = Bundle.main.infoDictionary?["FlintReleaseChannel"] as? String
        let currentIsBeta = (channel ?? "beta") == "beta"

        guard let release = releases.first(where: {
            !$0.draft && (currentIsBeta || !$0.tagName.contains("-beta"))
        }) else {
            return nil
        }

        guard let asset = release.assets.first(where: { $0.name == releaseAssetName })
            ?? release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            throw UpdateError.invalidUpdateFile
        }

        let normalizedVersion = release.tagName.replacingOccurrences(
            of: #"^v"#,
            with: "",
            options: .regularExpression
        )

        let updateInfo = UpdateInfo(
            version: normalizedVersion,
            downloadURL: asset.browserDownloadUrl,
            lastUpdated: release.publishedAt ?? "",
            description: release.body ?? ""
        )

        return compareVersions(updateInfo.version, isGreaterThan: currentVersion) ? updateInfo : nil
    }

    #if canImport(AppKit)
    private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        let progressHandler: (Double) -> Void

        init(progressHandler: @escaping (Double) -> Void) {
            self.progressHandler = progressHandler
        }

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

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let delegate = DownloadDelegate(progressHandler: { [weak self] progress in
            self?.progressSubject.send(progress)
        })
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        print("Downloading update from: \(url)")
        let (downloadURL, response) = try await session.download(from: url)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("Download failed with status: \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        try fileManager.moveItem(at: downloadURL, to: destinationURL)
        progressSubject.send(1.0)
        return destinationURL
    }

    func installUpdate(from updateFile: URL) throws {
        let fileManager = Foundation.FileManager.default

        let updateDirectory = downloadDirectory.appendingPathComponent("extracted")
        if fileManager.fileExists(atPath: updateDirectory.path) {
            try fileManager.removeItem(at: updateDirectory)
        }
        try fileManager.createDirectory(at: updateDirectory, withIntermediateDirectories: true)

        print("Extracting update file...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", updateFile.path, updateDirectory.path]

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

        guard let applicationsDirectory = fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first else {
            throw UpdateError.invalidAppPath
        }

        let newAppPath = updateDirectory.appendingPathComponent("Flint.app")
        let targetAppPath = applicationsDirectory.appendingPathComponent("Flint.app")

        if !fileManager.fileExists(atPath: newAppPath.path) {
            let extractedContents = String(describing: try? fileManager.contentsOfDirectory(atPath: updateDirectory.path))
            print("Error: Flint.app not found in extracted files. Found: \(extractedContents)")
            throw UpdateError.invalidUpdateFile
        }

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

    func cachedUpdateFile() -> URL? {
        let fileManager = Foundation.FileManager.default
        let destinationURL = downloadDirectory.appendingPathComponent("update.zip")
        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        return nil
    }

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
    #endif

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

    func compareVersions(_ version1: String, isGreaterThan version2: String) -> Bool {
        // Strip pre-release suffixes (e.g. "-beta") so "17-beta" parses as 17
        func numericComponents(_ version: String) -> [Int] {
            version.split(separator: ".").compactMap { part in
                let digits = part.prefix(while: { $0.isNumber })
                return Int(digits)
            }
        }
        let v1Components = numericComponents(version1)
        let v2Components = numericComponents(version2)

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

struct UpdateInfo: Codable {
    let version: String
    let downloadURL: String
    let lastUpdated: String
    let description: String
}

private struct GitHubRelease: Decodable {
    let draft: Bool
    let tagName: String
    let body: String?
    let publishedAt: String?
    let assets: [GitHubReleaseAsset]
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadUrl: String
}

#if canImport(AppKit)
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
#endif
