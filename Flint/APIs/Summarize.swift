//
//  Summarize.swift
//  Flint
//
//  Created by LC John on 1/26/25.
//

import AppKit
import Foundation
import Combine
import Security

// MARK: - Keychain Helper

enum KeychainHelper {
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return true }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

protocol SummarizeStreamDelegate: AnyObject {
    func receivedPartialContent(_ content: String)
    func completed()
    func failed(with error: Error)
}

final class MiniMaxAPI {
    static let shared = MiniMaxAPI()
    private var currentTask: URLSessionDataTask?
    private var currentSession: URLSession?

    // MARK: - Provider

    static var currentProvider: AIProvider {
        let raw = UserDefaults.standard.string(forKey: AppStorageKeys.AIProvider) ?? AIProvider.minimax.rawValue
        return AIProvider(rawValue: raw) ?? .minimax
    }

    private init() {
        runMigrations()
    }

    // MARK: - Migrations (idempotent)

    private func runMigrations() {
        // 1. Legacy UserDefaults API key → Keychain (MiniMax only)
        let legacyKey = UserDefaults.standard.string(forKey: AppStorageKeys.miniMaxAPIKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !legacyKey.isEmpty {
            if let existing = KeychainHelper.load(key: AIProvider.minimax.keychainKey), !existing.isEmpty {
                // Already migrated
            } else if KeychainHelper.save(key: AIProvider.minimax.keychainKey, value: legacyKey) {
                UserDefaults.standard.removeObject(forKey: AppStorageKeys.miniMaxAPIKey)
            }
        }

        // 2. Legacy global AIModel → per-provider AIModel_minimax
        if let oldModel = UserDefaults.standard.string(forKey: AppStorageKeys.AIModel),
           UserDefaults.standard.string(forKey: AIProvider.minimax.modelStorageKey) == nil {
            UserDefaults.standard.set(oldModel, forKey: AIProvider.minimax.modelStorageKey)
            UserDefaults.standard.removeObject(forKey: AppStorageKeys.AIModel)
        }
    }

    /// Ensures migration runs once, even when accessed via static properties.
    private static let ensureMigration: Void = {
        _ = shared
    }()

    // MARK: - API Key Management

    static var hasConfiguredAPIKey: Bool {
        _ = ensureMigration
        return !storedAPIKey.isEmpty
    }

    static func hasAPIKey(for provider: AIProvider) -> Bool {
        _ = ensureMigration
        let key = KeychainHelper.load(key: provider.keychainKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty
    }

    private static var storedAPIKey: String {
        _ = ensureMigration
        return KeychainHelper.load(key: currentProvider.keychainKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @discardableResult
    static func setAPIKey(_ value: String, for provider: AIProvider? = nil) -> Bool {
        let p = provider ?? currentProvider
        return KeychainHelper.save(key: p.keychainKey, value: value)
    }

    static func loadAPIKey(for provider: AIProvider? = nil) -> String {
        _ = ensureMigration
        let p = provider ?? currentProvider
        return KeychainHelper.load(key: p.keychainKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var apiKey: String {
        Self.storedAPIKey
    }

    // MARK: - Model Selection

    private var selectedModel: String {
        let provider = Self.currentProvider
        let storedModel = UserDefaults.standard.string(forKey: provider.modelStorageKey)
        if let storedModel,
            provider.models.contains(where: { $0.modelId == storedModel })
        {
            return storedModel
        }
        return provider.defaultModelId
    }

    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    struct ThinkingParam: Codable {
        let type: String
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let temperature: Double
        let topP: Double
        let thinking: ThinkingParam?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case temperature
            case topP = "top_p"
            case thinking
        }
    }

    struct StreamResponse: Codable {
        let choices: [Choice]

        struct Choice: Codable {
            let delta: Delta
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }

        struct Delta: Codable {
            let content: String?
        }
    }

    struct ChatCompletionResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    /// Build a URLRequest, snapshotting provider/key/model at call time.
    private func makeRequest(
        messages: [ChatMessage],
        stream: Bool,
        temperature: Double
    ) throws -> URLRequest {
        // Snapshot current state so in-flight requests are not affected by provider switches
        let endpoint = Self.currentProvider.chatCompletionsURL
        let key = apiKey
        let model = selectedModel

        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidConfiguration
        }

        guard !key.isEmpty else {
            throw AIServiceError.missingAPIKey
        }

        // kimi-k2.5 only accepts temperature=0.6 (with thinking disabled)
        let isKimiK25 = model.hasPrefix("kimi-k2.5")
        let effectiveTemperature = isKimiK25 ? 0.6 : temperature
        let thinking: ThinkingParam? = isKimiK25 ? ThinkingParam(type: "disabled") : nil

        let requestPayload = ChatRequest(
            model: model,
            messages: messages,
            stream: stream,
            temperature: effectiveTemperature,
            topP: 0.95,
            thinking: thinking
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(requestPayload)
        return urlRequest
    }

    private func performCompletion(
        messages: [ChatMessage],
        temperature: Double
    ) async throws -> String {
        let urlRequest = try makeRequest(messages: messages, stream: false, temperature: temperature)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw AIServiceError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: errorBody
            )
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let rawContent = completion.choices.first?.message.content ?? ""
        return Self.sanitizeOutput(rawContent)
    }

    private static func stripThinkingTags(from text: String) -> String {
        var sanitized = text

        if let regex = try? NSRegularExpression(
            pattern: "<think>[\\s\\S]*?</think>",
            options: [.caseInsensitive]
        ) {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: ""
            )
        }

        return sanitized
    }

    private static func sanitizeOutput(_ text: String) -> String {
        stripThinkingTags(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Begins a streaming summarization request.
    func summarizeWithStream(
        text: String,
        delegate: SummarizeStreamDelegate,
        type: SummarizeType = .title
    ) {
        print("🔄 Starting streaming summarization of type: \(type)")
        print("📝 Input text length: \(text.count) characters")

        let systemPrompt: String

        switch type {
        case .title:
            systemPrompt = "Please summarize the text content as a title, according to the most commonly used language in the user's text, as concisely & short as possible, less than 4 English words or 8 chinese words."
        case .content:
            systemPrompt = """
            请整理以下文本，按【Saved】、【Todo】分类。1.其中 Saved 有内容时。如果有代码，格式建议使用 ``` code inside ```，其他格式使用纯文本；2.Todo 有内容时，格式建议采用 - [ ] ，如果原文中没有对应内容，【Saved】、【Todo】下面应该完全为空（没有 - 或 - [ ] 等符号）。3.【Saved】、【Todo】中间空行 4.按照用户文本中最常用的语言，决定回复的语言 5.请严格遵循原文！避免随意补充！避免内容重复！避免任何无关字符加入！避免添加不存在的'Note'等字符！
            """
        }

        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: text),
        ]

        do {
            let urlRequest = try makeRequest(
                messages: messages,
                stream: true,
                temperature: type == .title ? 0.3 : 0.5
            )

            // Cancel any in-flight stream before starting a new one
            cancelSummarize()

            let session = URLSession(
                configuration: .default,
                delegate: StreamTaskHandler(delegate: delegate),
                delegateQueue: nil
            )
            currentSession = session
            currentTask = session.dataTask(with: urlRequest)
            currentTask?.resume()
            print("🚀 API request started")
        } catch {
            delegate.failed(with: error)
        }
    }

    private class StreamTaskHandler: NSObject, URLSessionDataDelegate {
        let streamDelegate: SummarizeStreamDelegate
        private var partialData = Data()
        private var hasCompleted = false
        private var thinkBuffer = ""
        private var insideThinkTag = false

        init(delegate: SummarizeStreamDelegate) {
            self.streamDelegate = delegate
        }

        private func finishIfNeeded(session: URLSession) {
            guard !hasCompleted else { return }
            hasCompleted = true
            // Flush any buffered partial content that wasn't part of a think tag
            if !thinkBuffer.isEmpty && !insideThinkTag {
                let remaining = thinkBuffer
                thinkBuffer = ""
                DispatchQueue.main.async { [weak self] in
                    self?.streamDelegate.receivedPartialContent(remaining)
                }
            }
            DispatchQueue.main.async {
                self.streamDelegate.completed()
            }
            session.finishTasksAndInvalidate()
        }

        private func failWith(_ error: Error, session: URLSession) {
            guard !hasCompleted else { return }
            // Intentional cancellation (e.g. restarting a stream) is not a real failure
            if (error as NSError).code == NSURLErrorCancelled { return }
            hasCompleted = true
            DispatchQueue.main.async {
                self.streamDelegate.failed(with: error)
            }
            session.invalidateAndCancel()
        }

        // Validate HTTP status on the initial response
        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                let error = AIServiceError.requestFailed(
                    statusCode: httpResponse.statusCode,
                    message: "HTTP \(httpResponse.statusCode)"
                )
                failWith(error, session: session)
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
        {
            partialData.append(data)

            guard let responseString = String(data: partialData, encoding: .utf8) else {
                return
            }

            var lines = responseString.components(separatedBy: "\n")
            let incompleteLine = responseString.hasSuffix("\n") ? nil : lines.popLast()

            for line in lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))

                if jsonString == "[DONE]" {
                    finishIfNeeded(session: session)
                    continue
                }

                guard !jsonString.isEmpty else { continue }

                guard let jsonData = jsonString.data(using: .utf8) else { continue }
                do {
                    let streamResponse = try JSONDecoder().decode(
                        MiniMaxAPI.StreamResponse.self,
                        from: jsonData
                    )
                    if let content = streamResponse.choices.first?.delta.content {
                        let filtered = filterThinkingContent(content)
                        if !filtered.isEmpty {
                            DispatchQueue.main.async { [weak self] in
                                self?.streamDelegate.receivedPartialContent(filtered)
                            }
                        }
                    }

                    if streamResponse.choices.first?.finishReason == "stop" {
                        finishIfNeeded(session: session)
                    }
                } catch {
                    print("❌ Error decoding JSON: \(error)")
                    print("Problem JSON string: \(jsonString)")
                }
            }

            if let incompleteLine = incompleteLine {
                partialData = incompleteLine.data(using: .utf8) ?? Data()
            } else {
                partialData = Data()
            }
        }

        /// Handles <think>...</think> tags that may span multiple SSE chunks.
        /// Buffers trailing characters that could be a partial tag delimiter
        /// split across chunk boundaries.
        private func filterThinkingContent(_ chunk: String) -> String {
            let openTag = "<think>"
            let closeTag = "</think>"
            let maxTagLen = max(openTag.count, closeTag.count)

            // Prepend any buffered partial from previous chunk
            let combined = thinkBuffer + chunk
            thinkBuffer = ""

            var output = ""
            var remaining = combined

            while !remaining.isEmpty {
                if insideThinkTag {
                    if let endRange = remaining.range(of: closeTag, options: .caseInsensitive) {
                        insideThinkTag = false
                        remaining = String(remaining[endRange.upperBound...])
                    } else {
                        // Still inside <think> — buffer trailing chars that could
                        // be a partial </think> split across chunks
                        let closeLen = closeTag.count
                        if remaining.count >= closeLen {
                            thinkBuffer = String(remaining.suffix(closeLen - 1))
                        } else {
                            thinkBuffer = remaining
                        }
                        remaining = ""
                    }
                } else {
                    if let startRange = remaining.range(of: openTag, options: .caseInsensitive) {
                        output += String(remaining[remaining.startIndex..<startRange.lowerBound])
                        insideThinkTag = true
                        remaining = String(remaining[startRange.upperBound...])
                    } else {
                        // Hold back a trailing window that could be a partial tag
                        if remaining.count >= maxTagLen {
                            let safeEnd = remaining.index(remaining.endIndex, offsetBy: -(maxTagLen - 1))
                            output += String(remaining[..<safeEnd])
                            thinkBuffer = String(remaining[safeEnd...])
                        } else {
                            thinkBuffer = remaining
                        }
                        remaining = ""
                    }
                }
            }

            return output
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
        ) {
            if let error = error {
                failWith(error, session: session)
            } else {
                // Transport finished without error — ensure delegate is notified
                finishIfNeeded(session: session)
            }
        }
    }

    func cancelSummarize() {
        currentTask?.cancel()
        currentTask = nil
        currentSession?.invalidateAndCancel()
        currentSession = nil
        print("⏹️ Summarization cancelled")
    }

    func checkRelevance(text: String) async throws -> Bool {
        let systemPrompt = "You are a specialized content filter. Analyze the user's clipboard content. If it contains valuable information (technical knowledge, code, instructions, useful data) that a user might want to save for later, reply with 'SAVE'. If it is trivial (random numbers, passwords, temporary logs, system gibberish) or junk, reply with 'REJECT'. Only reply with one word: SAVE or REJECT."

        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: text)
        ]

        do {
            let content = (try await performCompletion(messages: messages, temperature: 0.2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            return content == "SAVE"
        } catch {
            print("AI Check failed: \(error)")
            throw error
        }
    }

    func generateTitle(text: String) async throws -> String {
        let systemPrompt = """
You are a professional title generator. Generate a concise, professional title based on the text content.

STRICT RULES:
1. Output ONLY the title - no explanations, no quotes, no extra text
2. Maximum length: 4 English words OR 8 Chinese characters
3. Use the same language as the input text
4. If you cannot generate a suitable title, output exactly: CANNOT_GENERATE
5. Never output phrases like "无法生成", "不适合", or multi-line content
6. Never include line breaks, quotes, or formatting

Examples:
Input: "Today I learned about Swift concurrency..."
Output: Swift Concurrency Notes

Input: "今天研究了 SwiftUI 的新特性..."
Output: SwiftUI 新特性研究
"""
        
        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: text)
        ]

        do {
            let rawTitle = try await performCompletion(messages: messages, temperature: 0.3)

            let cleanTitle = rawTitle
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: String(UnicodeScalar(0x201C)!), with: "")
                .replacingOccurrences(of: String(UnicodeScalar(0x201D)!), with: "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if cleanTitle.isEmpty || cleanTitle == "CANNOT_GENERATE" || cleanTitle.count > 100 {
                let timestamp = Date().timeIntervalSince1970
                return "Note \(Int(timestamp))"
            }

            return cleanTitle
        } catch {
            print("AI Title Generation failed: \(error)")
            throw error
        }
    }

    // MARK: - AI Agent Intent Analysis

    /// Analyze user input to determine intent (reminder, calendar event, etc.)
    /// - Parameter text: The user's natural language input
    /// - Returns: An IntentResponse with parsed intent, time, and suggestions
    func analyzeIntent(text: String) async throws -> IntentResponse {
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss EEEE"
        let currentDateString = dateFormatter.string(from: currentDate)

        let systemPrompt = """
You are an AI assistant that analyzes user input to understand their intent. The current date and time is: \(currentDateString).

IMPORTANT: Recognize forwarded chat message formats
Users often paste messages copied from chat apps (DingTalk, Feishu, WeChat, Slack, etc.). These have varied formats but share common patterns:

How to identify forwarded chat messages:
1. Look for a TIMESTAMP pattern in the first few lines, such as:
   - "X/XX 上午/下午 X:XX" (e.g., "1/22 下午 9:40")
   - "XX:XX" (e.g., "9:40")
   - "YYYY-MM-DD HH:MM"
2. May contain a username/ID in parentheses like （xxx.yyy） or (username)
3. The sender's name usually appears BEFORE the timestamp
4. The actual message content appears AFTER the timestamp line
5. There may be empty lines between sections

When you detect a forwarded chat message:
- Extract the "title" from the MESSAGE CONTENT (after the timestamp), NOT from sender name
- The timestamp in the message shows when it was SENT - this is NOT the reminder time
- If the message content contains relative time words like "明天", "后天", "下周", calculate relative to TODAY (\(currentDateString)), not the message's sent date
- Put sender info in "notes" for context

Example input (with empty lines):
王经理

（wang.pm） 1/22 下午 9:40

@ 开发组 版本修复已上线明天帮忙验证下

Expected output:
{
  "intent": "scheduleReminder",
  "title": "版本修复验证",
  "dateTime": "(tomorrow from today)T09:00:00",
  "isAllDay": false,
  "confidence": 0.85,
  "notes": "来自 王经理 的消息：版本修复已上线，需要验证",
  "rawInterpretation": "王经理 请求明天帮忙验证版本修复"
}

Analyze the user's input and respond with a JSON object containing:
1. "intent": One of "scheduleReminder", "createCalendarEvent", "textEditing", "quickNote", "unknown"
2. "title": The extracted title/subject (what to remind or event name)
3. "dateTime": ISO 8601 formatted date-time string if time information is found (e.g., "2026-01-23T15:00:00")
4. "isAllDay": Boolean, true if it's an all-day event/reminder
5. "confidence": A number between 0 and 1 indicating confidence
6. "notes": Any additional notes or context
7. "rawInterpretation": Human-readable interpretation of the intent

Chinese time expressions to recognize (calculate from current date \(currentDateString)):
- 明天 = tomorrow
- 后天 = day after tomorrow
- 下周X = next week's day X (周一=Monday, 周日=Sunday)
- X点 = X o'clock
- 上午 = AM (morning)
- 下午 = PM (afternoon)
- 晚上 = evening (typically after 6 PM)
- X分钟后 = in X minutes
- X小时后 = in X hours

Examples for direct user input:
- "明天下午3点提醒我开会" -> scheduleReminder, title: "开会", dateTime: tomorrow 15:00
- "下周一上午10点开会" -> createCalendarEvent, title: "开会", dateTime: next Monday 10:00
- "提醒我买菜" -> scheduleReminder (no specific time, set to tomorrow 9:00 by default)
- "今天记得写日报" -> scheduleReminder, title: "写日报", dateTime: today (soon)

IMPORTANT: Only output valid JSON, no other text. The response must be parseable as JSON.
"""

        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: text)
        ]

        do {
            let content = try await performCompletion(messages: messages, temperature: 0.2)

            return try parseIntentResponse(from: content, originalText: text)
        } catch {
            print("AI Intent Analysis failed: \(error)")
            throw error
        }
    }

    /// Parse the AI response into an IntentResponse
    private func parseIntentResponse(from jsonString: String, originalText: String) throws -> IntentResponse {
        // Clean up the JSON string (remove markdown code blocks if present)
        var cleanJson = jsonString
        if cleanJson.hasPrefix("```json") {
            cleanJson = String(cleanJson.dropFirst(7))
        }
        if cleanJson.hasPrefix("```") {
            cleanJson = String(cleanJson.dropFirst(3))
        }
        if cleanJson.hasSuffix("```") {
            cleanJson = String(cleanJson.dropLast(3))
        }
        cleanJson = cleanJson.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanJson.data(using: .utf8) else {
            throw AIServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        let rawResponse = try decoder.decode(RawIntentResponse.self, from: jsonData)

        // Parse the date-time
        var parsedDateTime: ParsedDateTime? = nil
        if let dateTimeString = rawResponse.dateTime, !dateTimeString.isEmpty {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            // Try different ISO 8601 formats
            var parsedDate: Date? = isoFormatter.date(from: dateTimeString)

            if parsedDate == nil {
                isoFormatter.formatOptions = [.withInternetDateTime]
                parsedDate = isoFormatter.date(from: dateTimeString)
            }

            if parsedDate == nil {
                // Try a simpler format
                let simpleFormatter = DateFormatter()
                simpleFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                parsedDate = simpleFormatter.date(from: dateTimeString)
            }

            if let date = parsedDate {
                parsedDateTime = ParsedDateTime(
                    date: date,
                    isAllDay: rawResponse.isAllDay ?? false,
                    confidence: rawResponse.confidence ?? 0.8,
                    originalText: dateTimeString
                )
            }
        }

        // Map the intent type
        let intentType: IntentType
        switch rawResponse.intent.lowercased() {
        case "schedulereminder":
            intentType = .scheduleReminder
        case "createcalendarevent":
            intentType = .createCalendarEvent
        case "textediting":
            intentType = .textEditing
        case "quicknote":
            intentType = .quickNote
        default:
            intentType = .unknown
        }

        return IntentResponse(
            intent: intentType,
            title: rawResponse.title,
            parsedDateTime: parsedDateTime,
            notes: rawResponse.notes,
            confidence: rawResponse.confidence ?? 0.5,
            rawInterpretation: rawResponse.rawInterpretation ?? originalText
        )
    }

    /// Raw response structure from AI
    private struct RawIntentResponse: Codable {
        let intent: String
        let title: String?
        let dateTime: String?
        let isAllDay: Bool?
        let confidence: Double?
        let notes: String?
        let rawInterpretation: String?
    }

    static func prepareForAI(_ content: String, maxChars: Int = 300) -> String {
        if content.count <= maxChars { return content }
        
        let prefix = content.prefix(100)
        let suffix = content.suffix(100)
        
        let middleIndex = content.count / 2
        let startOffset = max(0, middleIndex - 50)
        let middleStart = content.index(content.startIndex, offsetBy: startOffset)
        let endOffset = min(content.count, startOffset + 100)
        let middleEnd = content.index(content.startIndex, offsetBy: endOffset)
        
        let middle = content[middleStart..<middleEnd]
        
        return "\(prefix)\n...\n\(middle)\n...\n\(suffix)"
    }
}

enum AIServiceError: LocalizedError {
    case missingAPIKey
    case invalidConfiguration
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return L("API Key is required")
        case .invalidConfiguration:
            return L("API configuration is invalid")
        case .invalidResponse:
            return L("AI returned an invalid response")
        case .requestFailed(let statusCode, let message):
            if message.isEmpty {
                return String(format: L("AI request failed (%d)"), statusCode)
            }
            return String(format: L("AI request failed (%d): %@"), statusCode, message)
        }
    }
}

/// Backward compatibility alias
typealias MiniMaxError = AIServiceError

// Add an enum to indicate summarization type
enum SummarizeType {
    case title   // For generating concise titles
    case content // For summarizing note content in structured format
}

// MARK: - MaybeLike Service

class MaybeLikeService: ObservableObject {
    static let shared = MaybeLikeService()
    private var timer: Timer?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    
    // Configuration
    private let minChars = 5     // Ignore very short copies
    private let maxContextChars = 300 // For AI context window optimization
    
    private init() {
        self.lastChangeCount = pasteboard.changeCount
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProviderChange),
            name: .aiProviderDidChange,
            object: nil
        )
    }

    @objc private func handleProviderChange() {
        if UserDefaults.standard.bool(forKey: AppStorageKeys.enableAutoSaveClipboard),
           MiniMaxAPI.hasConfiguredAPIKey {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    func startMonitoring() {
        guard UserDefaults.standard.bool(forKey: AppStorageKeys.enableAutoSaveClipboard) else {
            print("MaybeLike Service: Monitoring disabled by user settings")
            return
        }

        guard MiniMaxAPI.hasConfiguredAPIKey else {
            print("MaybeLike Service: API key missing")
            return
        }
        
        stopMonitoring()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        print("MaybeLike Service started monitoring...")
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        print("MaybeLike Service stopped monitoring...")
    }

    func ignoreCurrentClipboardChange() {
        let currentCount = pasteboard.changeCount
        if lastChangeCount != currentCount {
            lastChangeCount = currentCount
            print("MaybeLike Service: Ignoring current clipboard change (manually handled)")
        }
    }
    
    private func checkPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        // 1. Privacy Check: Ignore confidential types
        if let types = pasteboard.types {
            let typeNames = types.map { $0.rawValue }
            if typeNames.contains("org.nspasteboard.ConcealedType") || 
               typeNames.contains("com.agilebits.onepassword") {
                print("MaybeLike: Ignored concealed content")
                return
            }
        }
        
        // 2. Content Check
        guard let content = pasteboard.string(forType: .string), !content.isEmpty else { return }
        
        // Basic filters
        if content.count < minChars { return }
        if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: content)) { return }
        
        processContent(content)
    }
    
    private func processContent(_ content: String) {
        guard MiniMaxAPI.hasConfiguredAPIKey else {
            return
        }

        let aiInput = MiniMaxAPI.prepareForAI(content, maxChars: maxContextChars)
        
        Task {
            do {
                let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
                if sourceApp == "Flint" { return } 
                
                print("MaybeLike: Asking AI to check content relevance...")
                let isRelevent = try await MiniMaxAPI.shared.checkRelevance(text: aiInput)
                
                if isRelevent {
                    print("MaybeLike: AI accepted content, generating title...")
                    let aiTitle = try await MiniMaxAPI.shared.generateTitle(text: aiInput)
                    print("MaybeLike: Generated title: \(aiTitle)")
                    
                    await MainActor.run {
                        self.saveToNotes(content, sourceApp: sourceApp, title: aiTitle)
                    }
                } else {
                    print("MaybeLike: AI rejected content")
                }
            } catch {
                print("MaybeLike: AI Check failed - \(error)")
            }
        }
    }
    
    // Private method removed as it is now in MiniMaxAPI
    
    private func saveToNotes(_ content: String, sourceApp: String, title: String) {
        let safeTitle = title.map { $0 == "/" || $0 == ":" ? "-" : $0 }
        let finalTitle: String
        
        if String(safeTitle).trimmingCharacters(in: .whitespaces).isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            finalTitle = dateFormatter.string(from: Date())
        } else {
            finalTitle = String(safeTitle)
        }
        
        let textWithMetadata = "<!-- Source: \(sourceApp) -->\n<!-- Type: MaybeLike -->\n\(content)"
        
        if var fileURL = LocalFileManager.shared.fileURL(for: finalTitle) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "HH-mm-ss"
                let uniqueSuffix = dateFormatter.string(from: Date())
                let uniqueTitle = "\(finalTitle) \(uniqueSuffix)"
                if let uniqueURL = LocalFileManager.shared.fileURL(for: uniqueTitle) {
                    fileURL = uniqueURL
                }
            }
            
            do {
                try textWithMetadata.write(to: fileURL, atomically: true, encoding: .utf8)
                print("MaybeLike: Saved note to \(fileURL.path)")

                // Send notification if enabled
                if UserDefaults.standard.bool(forKey: AppStorageKeys.enableAutoClipboardNotification) {
                    Task {
                        await NotificationService.shared.sendAIActionSuccess(
                            title: L("Maybe Like Captured"),
                            message: "\(sourceApp) | \(finalTitle)",
                            filePath: fileURL.path,
                            content: textWithMetadata
                        )
                    }
                }

            } catch {
                print("MaybeLike: Save error - \(error)")
            }
        }
    }
}
