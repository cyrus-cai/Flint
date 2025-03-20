//
//  Summarize.swift
//  Writedown
//
//  Created by LC John on 1/26/25.
//

import AppKit
import Foundation

class DeepseekAPI {
    static let shared = DeepseekAPI()
    private let baseURL = "https://api.deepseek.com/chat/completions"
    private let apiKey: String

    private init() {
        // Load API key from configuration
        // In production, this should be securely stored
        self.apiKey = "sk-26764f1aa7b14441925d3fd444466e38"
    }

    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
    }

    struct ChatResponse: Codable {
        let id: String
        let choices: [Choice]

        struct Choice: Codable {
            let message: ChatMessage
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }
    }

    func summarize(text: String) async throws -> String {
        print("🤖 Starting summarization request")
        print("📝 Input text length: \(text.count) Chars")

        let systemPrompt =
            "请整理文本，按【Saved】、【Todo】分类。1.若 Saved 有内容。1.1若为代码，格式使用 ``` code inside ``` 1.2 若非代码，使用 bullet list ；2.若 Todo 有内容时，格式使用 - [ ] 3.若原文没有可整理为【Saved】或/和【Todo】的内容，相关条目下方应为空（无任何多余符号、描述等）4.【Saved】和【Todo】中间，需空行 5.以原文本的语言整理 6.严格遵循原文，杜绝额外补充，杜绝重复总结"


            //  let systemPrompt =
            // "请整理文本。1.若为代码，格式使用 ``` code inside ``` 2. 若非代码，使用 bullet list ；3.若 Todo 有内容时，格式使用 - [ ] 4.以原文本的语言整理 5.严格遵循原文，杜绝额外补充，杜绝重复总结"

        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: text),
        ]

        let request = ChatRequest(
            model: "deepseek-chat",
            messages: messages,
            stream: false
        )

        do {
            var urlRequest = URLRequest(url: URL(string: baseURL)!)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let encodedBody = try JSONEncoder().encode(request)
            urlRequest.httpBody = encodedBody

            print("📤 Sending request to Deepseek API")
            print("🔑 Using API key: \(apiKey.prefix(8))...")

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type received")
                throw DeepseekError.invalidResponse
            }

            print("📥 Received response with status code: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
                print("❌ API request failed:")
                print("Status code: \(httpResponse.statusCode)")
                print("Error response: \(errorBody)")
                throw DeepseekError.requestFailed
            }

            let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
            let summary = chatResponse.choices.first?.message.content ?? ""

            print("✅ Successfully generated summary")
            print("📝 Summary length: \(summary.count) Chars")

            return summary

        } catch let error as DecodingError {
            print("❌ JSON Decoding error:")
            switch error {
            case .dataCorrupted(let context):
                print("Data corrupted: \(context.debugDescription)")
            case .keyNotFound(let key, let context):
                print("Key '\(key.stringValue)' not found: \(context.debugDescription)")
            case .typeMismatch(let type, let context):
                print("Type '\(type)' mismatch: \(context.debugDescription)")
            case .valueNotFound(let type, let context):
                print("Value of type '\(type)' not found: \(context.debugDescription)")
            @unknown default:
                print("Unknown decoding error: \(error)")
            }
            throw error
        } catch {
            print("❌ Unexpected error: \(error.localizedDescription)")
            print("Error details: \(error)")
            throw error
        }
    }
}

protocol SummarizeStreamDelegate: AnyObject {
    func receivedPartialContent(_ content: String)
    func completed()
    func failed(with error: Error)
}

class DoubaoAPI {
    static let shared = DoubaoAPI()
    private let baseURL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
    private let apiKey: String
    private var currentTask: URLSessionDataTask?

    private init() {
        self.apiKey = "9eadfde1-ce10-4159-a87b-5490ba6a2209"
    }

    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
    }

    struct StreamResponse: Codable {
        let id: String
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

    /// Begins a streaming summarization request.
    func summarizeWithStream(text: String, delegate: SummarizeStreamDelegate, type: SummarizeType = .title) {
        print("🔄 Starting streaming summarization of type: \(type)")
        print("📝 Input text length: \(text.count) characters")

        // Retrieve the user-selected model from UserDefaults.
        // If none is found (or if for some reason the stored value is missing),
        // fall back to the first non-pro model.
        let selectedModel =
            UserDefaults.standard.string(forKey: "AIModel")
            ?? AIModelConfig.availableModels.first(where: { !$0.isProOnly })?.modelId
            ?? "ep-20250212220411-mtfqd"

        // Select the appropriate prompt based on summarization type
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

        let requestPayload = ChatRequest(model: selectedModel, messages: messages, stream: true)

        guard let url = URL(string: baseURL) else {
            delegate.failed(with: DoubaoError.invalidConfiguration)
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            urlRequest.httpBody = try JSONEncoder().encode(requestPayload)
        } catch {
            delegate.failed(with: error)
            return
        }

        // 使用内部的 StreamTaskHandler 保存 delegate
        let session = URLSession(
            configuration: .default, delegate: StreamTaskHandler(delegate: delegate),
            delegateQueue: nil)
        currentTask = session.dataTask(with: urlRequest)
        currentTask?.resume()
        print("🚀 API request started")
    }

    // 内部类：用于处理流式响应数据，把 SummarizeStreamDelegate 保存为 streamDelegate。
    private class StreamTaskHandler: NSObject, URLSessionDataDelegate {
        let streamDelegate: SummarizeStreamDelegate
        private var partialData = Data()

        init(delegate: SummarizeStreamDelegate) {
            self.streamDelegate = delegate
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
        {
            // 累计新接收到的数据到缓存中
            partialData.append(data)

            // 尝试将缓存转换为字符串
            guard let responseString = String(data: partialData, encoding: .utf8) else {
                return
            }

            // 将数据按换行符分割
            var lines = responseString.components(separatedBy: "\n")

            // 如果最后一行不完整，则保留它到缓存中，其他行作为完整行来处理
            let incompleteLine = responseString.hasSuffix("\n") ? nil : lines.popLast()

            for line in lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))

                if jsonString == "[DONE]" {
                    DispatchQueue.main.async {
                        self.streamDelegate.completed()
                    }
                    continue
                }

                guard !jsonString.isEmpty else { continue }

                guard let jsonData = jsonString.data(using: .utf8) else { continue }
                do {
                    let streamResponse = try JSONDecoder().decode(
                        DoubaoAPI.StreamResponse.self, from: jsonData)
                    if let content = streamResponse.choices.first?.delta.content {
                        DispatchQueue.main.async { [weak self] in
                            self?.streamDelegate.receivedPartialContent(content)
                        }
                    }
                    // 如果返回 finishReason 为 "stop" 的标记，则调用完成回调
                    if streamResponse.choices.first?.finishReason == "stop" {
                        DispatchQueue.main.async {
                            self.streamDelegate.completed()
                        }
                    }
                } catch {
                    print("❌ Error decoding JSON: \(error)")
                    print("Problem JSON string: \(jsonString)")
                }
            }

            // 清空缓存并保留未完整处理的最后一行（如果存在）
            if let incompleteLine = incompleteLine {
                partialData = incompleteLine.data(using: .utf8) ?? Data()
            } else {
                partialData = Data()
            }
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
        ) {
            if let error = error {
                DispatchQueue.main.async {
                    self.streamDelegate.failed(with: error)
                }
            }
        }
    }

    func cancelSummarize() {
        currentTask?.cancel()
        currentTask = nil
        print("⏹️ Summarization cancelled")
    }
}

enum DoubaoError: Error {
    case invalidConfiguration
    case requestFailed
}

enum DeepseekError: Error {
    case requestFailed
    case invalidResponse
    case invalidConfiguration

    var localizedDescription: String {
        switch self {
        case .requestFailed:
            return "The API request failed"
        case .invalidResponse:
            return "Received an invalid response from the API"
        case .invalidConfiguration:
            return "The API is not properly configured"
        }
    }
}

// Add an enum to indicate summarization type
enum SummarizeType {
    case title   // For generating concise titles
    case content // For summarizing note content in structured format
}
