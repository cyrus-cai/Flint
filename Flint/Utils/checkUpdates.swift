import Foundation

private struct GitHubVersionResponse: Codable {
    let tagName: String
}

class VersionChecker {
    static let shared = VersionChecker()

    private let versionURL = URL(string: "https://api.github.com/repos/cyrus-cai/Flint/releases/latest")!

    func checkLatestVersion() async throws -> String {
        var request = URLRequest(url: versionURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(GitHubVersionResponse.self, from: data)
        return release.tagName.replacingOccurrences(of: #"^v"#, with: "", options: .regularExpression)
    }
}
