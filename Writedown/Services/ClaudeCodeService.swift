//
//  ClaudeCodeService.swift
//  Writedown
//
//  Created by AI Agent on 1/23/26.
//

import Foundation
import Combine
import AppKit

/// Service for managing Claude Code CLI execution lifecycle
@MainActor
class ClaudeCodeService: ObservableObject {
    static let shared = ClaudeCodeService()

    // MARK: - Published Properties

    @Published private(set) var state: ExecutionState = .idle
    @Published private(set) var outputLines: [OutputLine] = []
    @Published private(set) var pendingPermission: PermissionRequest?
    @Published private(set) var sessionInfo: SessionInfo?

    // MARK: - Private Properties

    private var currentProcess: Process?
    private var stdinPipe: Pipe?
    private var outputTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?

    // MARK: - CLI Path Detection

    /// Detected CLI path (cached)
    private(set) var detectedCLIPath: String?

    private init() {
        detectedCLIPath = resolveClaudeCodePath()
    }

    // MARK: - Execution State

    enum ExecutionState: Equatable {
        case idle
        case preparing
        case running
        case waitingForPermission
        case completed
        case failed(String)
    }

    // MARK: - Session Info (from stream-json init)

    struct SessionInfo {
        let sessionId: String
        let model: String
        let tools: [String]
        let cwd: String
    }

    // MARK: - Permission Request

    struct PermissionRequest: Identifiable {
        let id = UUID()
        let toolUseId: String
        let toolName: String
        let input: [String: Any]
        let description: String?
        let timestamp: Date

        var displayDescription: String {
            if let desc = description {
                return desc
            }
            // Generate description based on tool type
            switch toolName {
            case "Bash":
                if let command = input["command"] as? String {
                    return "Run command: \(command)"
                }
            case "Write":
                if let path = input["file_path"] as? String {
                    return "Write file: \(path)"
                }
            case "Edit":
                if let path = input["file_path"] as? String {
                    return "Edit file: \(path)"
                }
            case "Read":
                if let path = input["file_path"] as? String {
                    return "Read file: \(path)"
                }
            default:
                break
            }
            return "Use tool: \(toolName)"
        }
    }

    // MARK: - Output Line

    struct OutputLine: Identifiable {
        let id = UUID()
        let content: String
        let type: StreamType
        let timestamp: Date
        let metadata: OutputMetadata?

        init(content: String, type: StreamType, timestamp: Date = Date(), metadata: OutputMetadata? = nil) {
            self.content = content
            self.type = type
            self.timestamp = timestamp
            self.metadata = metadata
        }
    }

    struct OutputMetadata {
        let toolName: String?
        let toolUseId: String?
        let isThinking: Bool
        let isToolResult: Bool
    }

    enum StreamType {
        case stdout
        case stderr
        case system
        case thinking      // Claude's thinking process
        case toolUse       // Tool invocation
        case toolResult    // Tool result
        case assistant     // Assistant message
        case error         // Error message
    }

    // MARK: - Public Methods

    /// Execute Claude Code CLI with stream-json output format
    /// - Parameters:
    ///   - noteContent: Current note content to pass as context
    ///   - noteTitle: Current note title
    ///   - workingDirectory: Directory to execute in
    ///   - prompt: Optional initial prompt
    func execute(
        noteContent: String?,
        noteTitle: String?,
        workingDirectory: URL,
        prompt: String? = nil
    ) async throws {
        // Cancel any existing execution
        cancel()

        // Clear previous output and set state to preparing
        outputLines = []
        pendingPermission = nil
        sessionInfo = nil
        state = .preparing

        // Add system message
        addSystemMessage("Detecting Claude Code CLI...")

        // Resolve CLI path
        guard let cliPath = resolveClaudeCodePath() else {
            handleCLINotFound()
            throw ClaudeCodeError.cliNotFound
        }

        addSystemMessage("Found CLI at: \(cliPath)")
        addSystemMessage("Working directory: \(workingDirectory.path)")

        // Check if working directory exists
        guard FileManager.default.fileExists(atPath: workingDirectory.path) else {
            let errorMsg = "Working directory does not exist: \(workingDirectory.path)"
            state = .failed(errorMsg)
            throw ClaudeCodeError.invalidWorkingDirectory(workingDirectory.path)
        }

        // Set state to running
        state = .running

        addSystemMessage("Starting Claude Code with stream-json output...")

        // Create and configure process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.currentDirectoryURL = workingDirectory

        // Configure environment variables
        var env = ProcessInfo.processInfo.environment
        if let title = noteTitle {
            env["HYPERNOTE_TITLE"] = title
        }
        process.environment = env

        // Configure arguments
        guard let content = noteContent, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            addSystemMessage("❌ No note content to send")
            state = .failed("Empty note")
            throw ClaudeCodeError.launchFailed("No note content provided")
        }

        // Use stream-json format for rich output
        // --verbose: show full turn-by-turn output
        // --output-format stream-json: structured JSON output
        // --input-format stream-json: allows sending permission responses
        // --permission-prompt-tool stdio: handle permissions via stdin/stdout
        process.arguments = [
            "-p", content,
            "--verbose",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--permission-prompt-tool", "stdio"
        ]

        // Configure I/O pipes
        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        // Store references
        currentProcess = process
        stdinPipe = inPipe

        // Start async output reading task for stream-json
        outputTask = Task {
            do {
                let bytes = outPipe.fileHandleForReading.bytes
                for try await line in bytes.lines {
                    await self.processStreamJsonLine(line)
                }
            } catch {
                // Stream closed or read error - expected when process terminates
            }
        }

        errorTask = Task {
            do {
                let bytes = errPipe.fileHandleForReading.bytes
                for try await line in bytes.lines {
                    await self.addOutputLine(content: line, type: .stderr)
                }
            } catch {
                // Stream closed or read error - expected when process terminates
            }
        }

        // Launch process
        do {
            try process.run()
        } catch {
            state = .failed(error.localizedDescription)
            addSystemMessage("❌ Failed to launch: \(error.localizedDescription)")
            throw ClaudeCodeError.launchFailed(error.localizedDescription)
        }

        Task.detached(priority: .userInitiated) { [process] in
            process.waitUntilExit()
            await self.finishProcess(process)
        }
    }

    /// Respond to a pending permission request
    /// - Parameters:
    ///   - allow: Whether to allow the tool use
    ///   - message: Optional message (used when denying)
    func respondToPermission(allow: Bool, message: String? = nil) {
        guard let request = pendingPermission, let pipe = stdinPipe else {
            addSystemMessage("⚠️ No pending permission request")
            return
        }

        let response: [String: Any]
        if allow {
            response = [
                "jsonrpc": "2.0",
                "id": request.toolUseId,
                "result": [
                    "behavior": "allow",
                    "updatedInput": request.input
                ]
            ]
            addSystemMessage("✓ Allowed: \(request.toolName)")
        } else {
            response = [
                "jsonrpc": "2.0",
                "id": request.toolUseId,
                "result": [
                    "behavior": "deny",
                    "message": message ?? "User denied this action"
                ]
            ]
            addSystemMessage("✗ Denied: \(request.toolName)")
        }

        // Send response via stdin
        if let jsonData = try? JSONSerialization.data(withJSONObject: response),
           var jsonString = String(data: jsonData, encoding: .utf8) {
            jsonString += "\n"
            if let data = jsonString.data(using: .utf8) {
                pipe.fileHandleForWriting.write(data)
            }
        }

        pendingPermission = nil
        if state == .waitingForPermission {
            state = .running
        }
    }

    /// Cancel current execution
    func cancel() {
        guard let process = currentProcess, process.isRunning else { return }

        addSystemMessage("⏹ Cancelling execution...")

        process.terminate()

        outputTask?.cancel()
        errorTask?.cancel()

        currentProcess = nil
        stdinPipe = nil
        outputTask = nil
        errorTask = nil
        pendingPermission = nil

        if case .running = state {
            state = .idle
        }
    }

    /// Clear output lines
    func clearOutput() {
        outputLines = []
        pendingPermission = nil
        if state != .running {
            state = .idle
        }
    }

    // MARK: - Stream JSON Processing

    /// Process a line of stream-json output
    private func processStreamJsonLine(_ line: String) {
        guard !line.isEmpty else { return }

        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Not valid JSON, treat as raw text
            addOutputLine(content: line, type: .stdout)
            return
        }

        guard let messageType = json["type"] as? String else {
            addOutputLine(content: line, type: .stdout)
            return
        }

        switch messageType {
        case "system":
            handleSystemMessage(json)

        case "assistant":
            handleAssistantMessage(json)

        case "user":
            handleUserMessage(json)

        case "tool_use":
            handleToolUseMessage(json)

        case "tool_result":
            handleToolResultMessage(json)

        case "result":
            handleResultMessage(json)

        case "stream_event":
            handleStreamEvent(json)

        case "permission_request":
            handlePermissionRequest(json)

        default:
            // Unknown type, display raw
            addOutputLine(content: "[\(messageType)] \(line)", type: .stdout)
        }
    }

    private func handleSystemMessage(_ json: [String: Any]) {
        if let subtype = json["subtype"] as? String, subtype == "init" {
            // Session initialization
            if let sessionId = json["session_id"] as? String,
               let model = json["model"] as? String,
               let cwd = json["cwd"] as? String {
                let tools = json["tools"] as? [String] ?? []
                sessionInfo = SessionInfo(
                    sessionId: sessionId,
                    model: model,
                    tools: tools,
                    cwd: cwd
                )
                addOutputLine(
                    content: "Session started: \(model)",
                    type: .system,
                    metadata: nil
                )
            }
        }
    }

    private func handleAssistantMessage(_ json: [String: Any]) {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return
        }

        for block in content {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    addOutputLine(content: text, type: .assistant)
                }

            case "thinking":
                if let thinking = block["thinking"] as? String, !thinking.isEmpty {
                    addOutputLine(
                        content: thinking,
                        type: .thinking,
                        metadata: OutputMetadata(toolName: nil, toolUseId: nil, isThinking: true, isToolResult: false)
                    )
                }

            case "tool_use":
                if let toolName = block["name"] as? String,
                   let toolId = block["id"] as? String {
                    let input = block["input"] as? [String: Any] ?? [:]
                    let inputStr = formatToolInput(toolName: toolName, input: input)
                    addOutputLine(
                        content: "🔧 \(toolName): \(inputStr)",
                        type: .toolUse,
                        metadata: OutputMetadata(toolName: toolName, toolUseId: toolId, isThinking: false, isToolResult: false)
                    )
                }

            default:
                break
            }
        }

        // Check for errors
        if let error = json["error"] as? String {
            addOutputLine(content: "Error: \(error)", type: .error)
        }
    }

    private func handleUserMessage(_ json: [String: Any]) {
        // User messages are usually echoes, we can skip or show them
        if let message = json["message"] as? [String: Any],
           let content = message["content"] as? String {
            addOutputLine(content: "User: \(content.prefix(100))...", type: .system)
        }
    }

    private func handleToolUseMessage(_ json: [String: Any]) {
        if let toolName = json["name"] as? String,
           let toolId = json["id"] as? String {
            let input = json["input"] as? [String: Any] ?? [:]
            let inputStr = formatToolInput(toolName: toolName, input: input)
            addOutputLine(
                content: "🔧 Using \(toolName): \(inputStr)",
                type: .toolUse,
                metadata: OutputMetadata(toolName: toolName, toolUseId: toolId, isThinking: false, isToolResult: false)
            )
        }
    }

    private func handleToolResultMessage(_ json: [String: Any]) {
        let toolUseId = json["tool_use_id"] as? String
        var resultText = ""

        if let content = json["content"] as? String {
            resultText = content
        } else if let output = json["output"] as? String {
            resultText = output
        }

        // Truncate long results
        let displayText = resultText.count > 500 ? String(resultText.prefix(500)) + "..." : resultText
        addOutputLine(
            content: "📋 Result: \(displayText)",
            type: .toolResult,
            metadata: OutputMetadata(toolName: nil, toolUseId: toolUseId, isThinking: false, isToolResult: true)
        )
    }

    private func handleResultMessage(_ json: [String: Any]) {
        let subtype = json["subtype"] as? String ?? "unknown"
        let isError = json["is_error"] as? Bool ?? false

        if let result = json["result"] as? String {
            if isError {
                addOutputLine(content: "❌ \(result)", type: .error)
            } else {
                addOutputLine(content: "✓ \(result)", type: .assistant)
            }
        }

        // Show usage stats if available
        if let durationMs = json["duration_ms"] as? Int,
           let cost = json["total_cost_usd"] as? Double {
            addOutputLine(
                content: "Completed in \(durationMs)ms, cost: $\(String(format: "%.4f", cost))",
                type: .system
            )
        }
    }

    private func handleStreamEvent(_ json: [String: Any]) {
        guard let event = json["event"] as? [String: Any],
              let eventType = event["type"] as? String else {
            return
        }

        switch eventType {
        case "content_block_delta":
            if let delta = event["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String {
                switch deltaType {
                case "text_delta":
                    if let text = delta["text"] as? String {
                        // Append to last line if it's also assistant text, or create new
                        appendOrAddText(text, type: .assistant)
                    }
                case "thinking_delta":
                    if let thinking = delta["thinking"] as? String {
                        appendOrAddText(thinking, type: .thinking)
                    }
                default:
                    break
                }
            }

        case "content_block_start":
            if let contentBlock = event["content_block"] as? [String: Any],
               let blockType = contentBlock["type"] as? String {
                if blockType == "thinking" {
                    addOutputLine(content: "💭 Thinking...", type: .thinking)
                } else if blockType == "tool_use",
                          let toolName = contentBlock["name"] as? String {
                    addOutputLine(content: "🔧 Calling \(toolName)...", type: .toolUse)
                }
            }

        default:
            break
        }
    }

    private func handlePermissionRequest(_ json: [String: Any]) {
        guard let toolUseId = json["tool_use_id"] as? String,
              let toolName = json["tool_name"] as? String else {
            return
        }

        let input = json["input"] as? [String: Any] ?? [:]
        let description = json["description"] as? String

        let request = PermissionRequest(
            toolUseId: toolUseId,
            toolName: toolName,
            input: input,
            description: description,
            timestamp: Date()
        )

        pendingPermission = request
        state = .waitingForPermission

        addOutputLine(
            content: "⚠️ Permission required: \(request.displayDescription)",
            type: .system
        )
    }

    // MARK: - Helper Methods

    private func formatToolInput(toolName: String, input: [String: Any]) -> String {
        switch toolName {
        case "Bash":
            return input["command"] as? String ?? ""
        case "Write", "Edit", "Read":
            return input["file_path"] as? String ?? ""
        case "Glob":
            return input["pattern"] as? String ?? ""
        case "Grep":
            return input["pattern"] as? String ?? ""
        default:
            if let data = try? JSONSerialization.data(withJSONObject: input, options: []),
               let str = String(data: data, encoding: .utf8) {
                return str.count > 100 ? String(str.prefix(100)) + "..." : str
            }
            return ""
        }
    }

    private func appendOrAddText(_ text: String, type: StreamType) {
        // For streaming deltas, try to append to the last line of same type
        if let lastIndex = outputLines.lastIndex(where: { $0.type == type }) {
            let lastLine = outputLines[lastIndex]
            let newContent = lastLine.content + text
            outputLines[lastIndex] = OutputLine(
                content: newContent,
                type: type,
                timestamp: lastLine.timestamp,
                metadata: lastLine.metadata
            )
        } else {
            addOutputLine(content: text, type: type)
        }
    }

    // MARK: - Private Methods

    /// Resolve Claude Code CLI path
    private func resolveClaudeCodePath() -> String? {
        // 1. Check UserDefaults for custom path
        if let customPath = UserDefaults.standard.string(forKey: "claudeCodeCLIPath"),
           FileManager.default.fileExists(atPath: customPath) {
            return customPath
        }

        // 2. Check common installation paths
        let commonPaths = [
            NSString(string: "~/.claude/local/bin/claude").expandingTildeInPath,  // Official installer
            "/opt/homebrew/bin/claude",       // M1/M2 Mac Homebrew
            "/usr/local/bin/claude",          // Intel Mac Homebrew
            NSString(string: "~/.local/bin/claude").expandingTildeInPath,
            "/opt/homebrew/bin/claude-code",  // Legacy name
            "/usr/local/bin/claude-code",     // Legacy name
            NSString(string: "~/.local/bin/claude-code").expandingTildeInPath,
            "/usr/bin/claude"
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // 3. Try to find via 'which' command
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

    /// Handle CLI not found scenario
    private func handleCLINotFound() {
        addSystemMessage("❌ Claude Code CLI not found")
        addSystemMessage("📦 Install with: curl -fsSL https://claude.ai/install.sh | bash")
        addSystemMessage("💡 Or set custom path in Settings")

        state = .failed("CLI not found")

        // Send system notification
        Task {
            await NotificationService.shared.sendError(
                title: "Claude Code CLI Not Found",
                message: "Install with: curl -fsSL https://claude.ai/install.sh | bash\n\nOr configure the path in Settings."
            )
        }
    }

    /// Add output line
    private func addOutputLine(content: String, type: StreamType, metadata: OutputMetadata? = nil) {
        outputLines.append(OutputLine(
            content: content,
            type: type,
            timestamp: Date(),
            metadata: metadata
        ))

        // Limit buffer size to prevent memory issues
        if outputLines.count > 1000 {
            outputLines.removeFirst()
        }
    }

    /// Add system message
    private func addSystemMessage(_ message: String) {
        outputLines.append(OutputLine(
            content: message,
            type: .system,
            timestamp: Date(),
            metadata: nil
        ))
    }

    private func finishProcess(_ process: Process) async {
        await outputTask?.value
        await errorTask?.value

        guard currentProcess == process else { return }

        let exitCode = process.terminationStatus

        if exitCode == 0 {
            state = .completed
            addSystemMessage("✓ Claude Code completed successfully")
        } else {
            state = .failed("Exit code: \(exitCode)")
            addSystemMessage("❌ Claude Code exited with code: \(exitCode)")
        }

        currentProcess = nil
        stdinPipe = nil
        outputTask = nil
        errorTask = nil
        pendingPermission = nil
    }
}

// MARK: - Errors

enum ClaudeCodeError: LocalizedError {
    case cliNotFound
    case launchFailed(String)
    case invalidWorkingDirectory(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "Claude Code CLI not found. Install with: curl -fsSL https://claude.ai/install.sh | bash"
        case .launchFailed(let reason):
            return "Failed to launch Claude Code: \(reason)"
        case .invalidWorkingDirectory(let path):
            return "Invalid working directory: \(path)"
        }
    }
}
