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
        let systemPrompt = "You are a helpful assistant. Please summarize the following text concisely while keeping the key points."
        
        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: text)
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
              httpResponse.statusCode == 200 else {
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
