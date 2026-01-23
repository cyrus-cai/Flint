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

    // MARK: - Private Properties

    private var currentProcess: Process?
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
        case completed
        case failed(String)
    }

    // MARK: - Output Line

    struct OutputLine: Identifiable {
        let id = UUID()
        let content: String
        let type: StreamType
        let timestamp: Date
    }

    enum StreamType {
        case stdout
        case stderr
        case system
    }

    // MARK: - Public Methods

    /// Execute Claude Code CLI
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

        addSystemMessage("Starting Claude Code...")

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
        // Claude CLI requires -p (print mode) for non-interactive use
        // Use note content directly as the prompt
        guard let content = noteContent, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            addSystemMessage("❌ No note content to send")
            state = .failed("Empty note")
            throw ClaudeCodeError.launchFailed("No note content provided")
        }

        process.arguments = ["-p", content]

        // Configure I/O pipes
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = nil

        // Store current process
        currentProcess = process

        // Start async output reading tasks
        outputTask = Task {
            do {
                let bytes = outPipe.fileHandleForReading.bytes
                for try await line in bytes.lines {
                    await self.addOutputLine(content: line, type: .stdout)
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

    /// Cancel current execution
    func cancel() {
        guard let process = currentProcess, process.isRunning else { return }

        addSystemMessage("⏹ Cancelling execution...")

        process.terminate()

        outputTask?.cancel()
        errorTask?.cancel()

        currentProcess = nil
        outputTask = nil
        errorTask = nil

        if case .running = state {
            state = .idle
        }
    }

    /// Clear output lines
    func clearOutput() {
        outputLines = []
        if state != .running {
            state = .idle
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
    private func addOutputLine(content: String, type: StreamType) {
        outputLines.append(OutputLine(
            content: content,
            type: type,
            timestamp: Date()
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
            timestamp: Date()
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
        outputTask = nil
        errorTask = nil
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
