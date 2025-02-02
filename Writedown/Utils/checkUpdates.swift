//
//  checkUpdates.swift
//  Hyper Note
//
//  Created by LC John on 2024/11/29.
//

import Foundation

struct VersionResponse: Codable {
    let version: String
    let lastUpdated: String
}

class VersionChecker {
    static let shared = VersionChecker()
    private let versionURL = URL(string: "https://www.figa.asia/api/version")!
    
    func checkLatestVersion() async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: versionURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let versionInfo = try JSONDecoder().decode(VersionResponse.self, from: data)
        return versionInfo.version
    }
}
