import Foundation

private struct GitHubVersionResponse: Codable {
    let draft: Bool
    let tagName: String
}

class VersionChecker {
    static let shared = VersionChecker()

    private let versionURL = URL(string: "https://api.github.com/repos/cyrus-cai/Flint/releases?per_page=20")!

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
        let releases = try decoder.decode([GitHubVersionResponse].self, from: data)

        guard let release = releases.first(where: { !$0.draft && !$0.tagName.contains("-beta") }) else {
            throw URLError(.fileDoesNotExist)
        }

        return release.tagName.replacingOccurrences(of: #"^v"#, with: "", options: .regularExpression)
    }
}
