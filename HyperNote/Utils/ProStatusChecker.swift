//
//  ProStatusChecker.swift
//  HyperNote
//
//  Created by LC John on 2/1/25.
//

import Foundation

class ProStatusChecker {
    static let shared = ProStatusChecker()
    private let baseURL = "https://hp-subscription-callback.vercel.app/api/proStatus"

    struct ProStatusResponse: Codable {
        let isPro: Bool
    }

    func checkProStatus(email: String) async throws -> Bool {
        var urlComponents = URLComponents(string: baseURL)
        urlComponents?.queryItems = [URLQueryItem(name: "email", value: email)]

        guard let url = urlComponents?.url else {
            print("❌ URL configuration failed")
            throw ProStatusError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        print("🔍 Checking pro status for email: \(email)")
        print("📡 Request URL: \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw ProStatusError.invalidResponse
        }

        print("📥 Response status code: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            if let responseData = String(data: data, encoding: .utf8) {
                print("❌ Request failed with status code: \(httpResponse.statusCode)")
                print("📄 Response body: \(responseData)")
            }
            throw ProStatusError.requestFailed
        }

        do {
            let proStatus = try JSONDecoder().decode(ProStatusResponse.self, from: data)
            print("✅ Pro status response: \(proStatus.isPro)")
            return proStatus.isPro
        } catch {
            print("❌ JSON decoding failed: \(error)")
            if let responseData = String(data: data, encoding: .utf8) {
                print("📄 Raw response data: \(responseData)")
            }
            throw error
        }
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
