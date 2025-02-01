//
//  ProStatusChecker.swift
//  HyperNote
//
//  Created by LC John on 2/1/25.
//

import Foundation

class ProStatusChecker {
    static let shared = ProStatusChecker()
    private let baseURL = "http://localhost:3000/api/user/pro-status"
    
    struct ProStatusResponse: Codable {
        let isPro: Bool
    }
    
    func checkProStatus(email: String) async throws -> Bool {
        guard let url = URL(string: baseURL) else {
            throw ProStatusError.invalidConfiguration
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add user email to headers for verification
        if !email.isEmpty {
            request.setValue(email, forHTTPHeaderField: "X-User-Email")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProStatusError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            throw ProStatusError.requestFailed
        }
        
        let proStatus = try JSONDecoder().decode(ProStatusResponse.self, from: data)
        return proStatus.isPro
    }
}

enum ProStatusError: Error {
    case invalidConfiguration
    case requestFailed
    case invalidResponse
    
    var localizedDescription: String {
        switch self {
        case .invalidConfiguration:
            return "The pro status checker is not properly configured"
        case .requestFailed:
            return "Failed to check pro status"
        case .invalidResponse:
            return "Received an invalid response from the server"
        }
    }
}
