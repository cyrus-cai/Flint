//
//  SwiftTermService.swift
//  Writedown
//
//  Created by Claude Code on 1/25/26.
//

import Foundation
import SwiftTerm
import AppKit

/// Service for managing SwiftTerm-based terminal execution
@MainActor
class SwiftTermService: ObservableObject {
    static let shared = SwiftTermService()

    // MARK: - Published Properties

    @Published private(set) var isRunning = false
    @Published private(set) var sessionInfo: SessionInfo?

    // MARK: - Private Properties

    private var currentProcess: Process?
    private var terminalDelegates: [ObjectIdentifier: ClaudeTerminalDelegate] = [:]

    // MARK: - Types

    struct SessionInfo {
        let sessionId: String
        let model: String
        let cwd: String
    }

    private init() {}

    // MARK: - Public Methods

    /// Create and configure a terminal view for Claude Code execution
    /// - Parameters:
    ///   - noteContent: Content to send to Claude
    ///   - noteTitle: Note title for context
    ///   - workingDirectory: Working directory for execution
    /// - Returns: Configured ClaudeTerminalView ready for display
    func createTerminalView(
        noteContent: String?,
        noteTitle: String?,
        workingDirectory: URL
    ) -> ClaudeTerminalView {
        let terminalView = ClaudeTerminalView(frame: .zero)

        // Configure appearance
        terminalView.nativeBackgroundColor = NSColor(hex: "#1E1E1E") ?? .black
        terminalView.nativeForegroundColor = NSColor(hex: "#CCCCCC") ?? .white
        terminalView.caretColor = NSColor(hex: "#AEAFAD") ?? .white
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Create and set delegate
        let delegate = ClaudeTerminalDelegate(terminalView: terminalView)
        terminalView.terminalDelegate = delegate

        // Store delegate reference
        let viewId = ObjectIdentifier(terminalView)
        terminalDelegates[viewId] = delegate

        // Start process
        Task {
            await startClaudeProcess(
                terminalView: terminalView,
                noteContent: noteContent,
                noteTitle: noteTitle,
                workingDirectory: workingDirectory
            )
        }

        return terminalView
    }

    /// Cancel current execution
    func cancel() {
        guard let process = currentProcess, process.isRunning else { return }
        process.terminate()
        currentProcess = nil
        isRunning = false
    }

    // MARK: - Private Methods

    private func startClaudeProcess(
        terminalView: ClaudeTerminalView,
        noteContent: String?,
        noteTitle: String?,
        workingDirectory: URL
    ) async {
        // Resolve CLI path
        guard let cliPath = resolveClaudeCodePath() else {
            await feedErrorMessage(to: terminalView, message: "Claude Code CLI not found")
            await feedInfoMessage(to: terminalView, message: "Install with: curl -fsSL https://claude.ai/install.sh | bash")
            return
        }

        // Validate content
        guard let content = noteContent?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            await feedErrorMessage(to: terminalView, message: "No note content provided")
            return
        }

        isRunning = true

        // Send startup message
        await feedInfoMessage(to: terminalView, message: "Starting Claude Code...")
        await feedInfoMessage(to: terminalView, message: "CLI: \(cliPath)")
        await feedInfoMessage(to: terminalView, message: "Working directory: \(workingDirectory.path)")
        terminalView.feed(text: "\r\n")

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.currentDirectoryURL = workingDirectory

        // Configure environment
        var env = ProcessInfo.processInfo.environment
        if let title = noteTitle {
            env["HYPERNOTE_TITLE"] = title
        }
        // Force color output
        env["FORCE_COLOR"] = "1"
        env["TERM"] = "xterm-256color"
        process.environment = env

        // Configure arguments - use stream-json for clean output without terminal control codes
        process.arguments = [
            "-p", content,
            "--output-format", "stream-json",
            "--verbose"
        ]

        print("🚀 Starting Claude process with arguments: \(process.arguments ?? [])")

        // Configure I/O pipes
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = nil

        currentProcess = process

        // Start async output reading - use raw bytes to preserve ANSI codes
        let outputTask = Task {
            await self.readAndFeedOutput(
                from: outPipe.fileHandleForReading,
                to: terminalView,
                isError: false
            )
        }

        let errorTask = Task {
            await self.readAndFeedOutput(
                from: errPipe.fileHandleForReading,
                to: terminalView,
                isError: true
            )
        }

        // Launch process
        do {
            print("🚀 Launching Claude process...")
            let launchStart = Date()
            try process.run()
            print("🚀 Process launched in \(String(format: "%.2f", Date().timeIntervalSince(launchStart) * 1000))ms, PID: \(process.processIdentifier)")
        } catch {
            await feedErrorMessage(to: terminalView, message: "Failed to launch: \(error.localizedDescription)")
            isRunning = false
            return
        }

        // Wait for completion
        Task.detached(priority: .userInitiated) { [weak self] in
            process.waitUntilExit()

            await outputTask.value
            await errorTask.value

            await self?.handleProcessCompletion(process, terminalView: terminalView)
        }
    }

    private func handleProcessCompletion(_ process: Process, terminalView: ClaudeTerminalView) async {
        let exitCode = process.terminationStatus
        isRunning = false
        currentProcess = nil

        // Send completion message
        terminalView.feed(text: "\r\n")
        if exitCode == 0 {
            await feedSuccessMessage(to: terminalView, message: "Claude Code completed successfully")
        } else {
            await feedErrorMessage(to: terminalView, message: "Claude Code exited with code: \(exitCode)")
        }
    }

    // MARK: - Helper Methods

    private func feedErrorMessage(to terminalView: ClaudeTerminalView, message: String) async {
        terminalView.feedColored(text: "\(message)", color: .red)
        terminalView.feed(text: "\r\n")
    }

    private func feedSuccessMessage(to terminalView: ClaudeTerminalView, message: String) async {
        terminalView.feedColored(text: "\(message)", color: .green)
        terminalView.feed(text: "\r\n")
    }

    private func feedInfoMessage(to terminalView: ClaudeTerminalView, message: String) async {
        terminalView.feedColored(text: "\(message)", color: .cyan)
        terminalView.feed(text: "\r\n")
    }

    /// Resolve Claude Code CLI path (reused from ClaudeCodeService)
    private func resolveClaudeCodePath() -> String? {
        // Check UserDefaults for custom path
        if let customPath = UserDefaults.standard.string(forKey: "claudeCodeCLIPath"),
           FileManager.default.fileExists(atPath: customPath) {
            return customPath
        }

        // Check common installation paths
        let commonPaths = [
            NSString(string: "~/.claude/local/bin/claude").expandingTildeInPath,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            NSString(string: "~/.local/bin/claude").expandingTildeInPath,
            "/opt/homebrew/bin/claude-code",
            "/usr/local/bin/claude-code",
            NSString(string: "~/.local/bin/claude-code").expandingTildeInPath,
            "/usr/bin/claude"
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try to find via 'which' command
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["claude"]

        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = nil

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()

            if whichProcess.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            print("Failed to run 'which' command: \(error)")
        }

        return nil
    }

    // MARK: - Raw Byte Reading

    /// Read JSON stream from file handle and feed parsed content to terminal
    private nonisolated func readAndFeedOutput(
        from fileHandle: FileHandle,
        to terminalView: ClaudeTerminalView,
        isError: Bool
    ) async {
        let streamLabel = isError ? "STDERR" : "STDOUT"
        print("📥 [\(streamLabel)] Starting output reader...")

        // Read on background thread to avoid blocking
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var totalBytes = 0
                var readCount = 0
                var lineBuffer = ""

                while true {
                    // Read available data - blocks until data or EOF
                    let data = fileHandle.availableData

                    // Empty data means EOF
                    if data.isEmpty {
                        print("[\(streamLabel)] EOF reached. Total: \(totalBytes) bytes in \(readCount) reads")
                        break
                    }

                    readCount += 1
                    totalBytes += data.count

                    // Convert to string
                    guard let text = String(data: data, encoding: .utf8) else {
                        continue
                    }

                    // Buffer and process line by line (JSON is newline-delimited)
                    lineBuffer += text
                    let lines = lineBuffer.components(separatedBy: "\n")

                    // Process complete lines, keep incomplete line in buffer
                    for i in 0..<lines.count - 1 {
                        let line = lines[i].trimmingCharacters(in: .whitespaces)
                        if line.isEmpty { continue }

                        // Parse JSON and extract content
                        if let displayText = self.parseStreamJSON(line) {
                            DispatchQueue.main.async {
                                terminalView.feed(text: displayText)
                            }
                        }
                    }

                    lineBuffer = lines.last ?? ""
                }

                // Process any remaining content in buffer
                if !lineBuffer.isEmpty {
                    let line = lineBuffer.trimmingCharacters(in: .whitespaces)
                    if let displayText = self.parseStreamJSON(line) {
                        DispatchQueue.main.async {
                            terminalView.feed(text: displayText)
                        }
                    }
                }

                continuation.resume()
            }
        }
    }

    /// Parse stream-json format and extract displayable text
    private nonisolated func parseStreamJSON(_ jsonLine: String) -> String? {
        guard let data = jsonLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Not valid JSON, might be plain text error
            if !jsonLine.isEmpty {
                return jsonLine + "\r\n"
            }
            return nil
        }

        let messageType = json["type"] as? String ?? ""

        switch messageType {
        case "assistant":
            // Assistant message with content
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                var result = ""
                for item in content {
                    if let text = item["text"] as? String {
                        result += text
                    }
                }
                if !result.isEmpty {
                    return result
                }
            }

        case "content_block_delta":
            // Streaming content delta
            if let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                return text
            }

        case "content_block_start":
            // Content block starting - might have initial text
            if let contentBlock = json["content_block"] as? [String: Any],
               let text = contentBlock["text"] as? String,
               !text.isEmpty {
                return text
            }

        case "result":
            // Final result
            if let result = json["result"] as? String {
                return "\r\n\(result)\r\n"
            }

        case "system":
            // System message
            if let message = json["message"] as? String {
                return "\r\n💡 \(message)\r\n"
            }
            if let subtype = json["subtype"] as? String {
                switch subtype {
                case "init":
                    if let sessionId = json["session_id"] as? String {
                        return "Session: \(sessionId)\r\n"
                    }
                case "result":
                    if let result = json["result"] as? String {
                        return "\r\n✅ \(result)\r\n"
                    }
                default:
                    break
                }
            }

        case "error":
            // Error message
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return "\r\n Error: \(message)\r\n"
            }

        case "user":
            // User message (tool results, subagent messages, etc.)
            // Handle tool_use_result directly on json
            if let toolResult = json["tool_use_result"] as? [String: Any] {
                if let content = toolResult["content"] as? String, !content.isEmpty {
                    return " \(content)\r\n"
                } else if let items = toolResult["content"] as? [[String: Any]] {
                    var result = ""
                    for item in items {
                        if let text = item["text"] as? String {
                            result += text
                        }
                    }
                    if !result.isEmpty {
                        return " \(result)\r\n"
                    }
                }
            }
            
            // Handle message.content as array
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                var result = ""
                for item in content {
                    if let itemType = item["type"] as? String {
                        if itemType == "tool_result", let toolContent = item["content"] as? String {
                            // Tool result content
                            result += "\(toolContent)\r\n"
                        } else if let text = item["text"] as? String {
                            result += text
                        }
                    } else if let text = item["text"] as? String {
                        // Fallback: item without type but has text
                        result += text
                    }
                }
                if !result.isEmpty {
                    return result
                }
            }
            
            // Handle message.content as string
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String, !content.isEmpty {
                return "\(content)\r\n"
            }
            
            // Handle message as string directly
            if let message = json["message"] as? String, !message.isEmpty {
                return "\(message)\r\n"
            }
            
            // Silently ignore other user messages (they're often just acknowledgments)
            return nil

        default:
            // For debugging - show unknown message types with sample content
            let jsonStr = String(data: (try? JSONSerialization.data(withJSONObject: json, options: [])) ?? Data(), encoding: .utf8) ?? ""
            let preview = String(jsonStr.prefix(500))
            print("Unknown message type: \(messageType)")
            print("   JSON preview: \(preview)")
        }

        return nil
    }

    // MARK: - Cleanup
}

// MARK: - NSColor Extension

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
