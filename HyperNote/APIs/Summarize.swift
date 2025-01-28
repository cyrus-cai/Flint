//
//  Summarize.swift
//  HyperNote
//
//  Created by LC John on 1/26/25.
//

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
        print("📝 Input text length: \(text.count) characters")

        let systemPrompt =
            "请整理以下文本，按【Saved】、【Todo】分类。1.其中 Saved 有内容时。如果有代码，格式建议使用 ``` code inside ```，其他格式使用纯文本；2.Todo 有内容时，格式建议采用 - [ ] ，如果原文中没有对应内容，【Saved】、【Todo】下面应该完全为空（没有 - 或 - [ ] 等符号）。3.【Saved】、【Todo】中间空行 4.按照用户文本中最常用的语言，决定回复的语言 5.请严格遵循原文，避免强行补充，避免内容重复。"

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
            print("📝 Summary length: \(summary.count) characters")

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

