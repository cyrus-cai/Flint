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
        let systemPrompt =
            "请整理以下文本，按【Saved】、【Todo】分类。1.其中 Saved 有内容时，格式建议使用文本，Todo 有内容时，格式建议采用 - [ ] ，如果原文中没有对应内容，【Saved】、【Todo】下面应该完全为空（没有 - 或 - [ ] 等符号）。2.【Saved】、【Todo】中间空行 3.按照用户文本中最常用的语言，决定回复的语言 4.请严格遵循原文，避免强行补充，避免内容重复。"

        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: text),
        ]

        let request = ChatRequest(
            model: "deepseek-chat",
            messages: messages,
            stream: false
        )

        var urlRequest = URLRequest(url: URL(string: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw DeepseekError.requestFailed
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? ""
    }
}

enum DeepseekError: Error {
    case requestFailed
    case invalidResponse
}
