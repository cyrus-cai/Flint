
import Foundation

public class FeishuAPI {
    static let shared = FeishuAPI()
    private let baseURL = "https://open.feishu.cn/open-apis"
    private var accessToken: String?

    // Configuration keys
    private let kFeishuEnabled = "FeishuSyncEnabled"
    private let kFeishuAccessToken = "FeishuAccessToken"

    var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: kFeishuEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: kFeishuEnabled)
        }
    }

    func configure(accessToken: String) {
        self.accessToken = accessToken
        UserDefaults.standard.set(accessToken, forKey: kFeishuAccessToken)
    }

    func ensureRootFolder() async throws -> String {
        let endpoint = "\(baseURL)/drive/v1/files/create_folder"
        let parameters: [String: Any] = [
            "name": "Float",
            "folder_token": "",  // Empty for root directory
        ]

        return try await createFolder(endpoint: endpoint, parameters: parameters)
    }

    func createWeekFolder(parentToken: String, weekName: String) async throws -> String {
        let endpoint = "\(baseURL)/drive/v1/files/create_folder"
        let parameters: [String: Any] = [
            "name": weekName,
            "folder_token": parentToken,
        ]

        return try await createFolder(endpoint: endpoint, parameters: parameters)
    }

    func createDocument(folderToken: String, title: String, content: String) async throws {
        let endpoint = "\(baseURL)/docx/v1/documents"
        let parameters: [String: Any] = [
            "title": title,
            "folder_token": folderToken,
        ]

        guard let url = URL(string: endpoint),
            let accessToken = self.accessToken
        else {
            throw FeishuError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            if let errorData = String(data: data, encoding: .utf8) {
                print("Feishu API Error: \(errorData)")
            }
            throw FeishuError.requestFailed
        }
    }

    private func createFolder(endpoint: String, parameters: [String: Any]) async throws -> String {
        guard let url = URL(string: endpoint),
            let accessToken = self.accessToken
        else {
            throw FeishuError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw FeishuError.requestFailed
        }

        guard let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataDict = responseDict["data"] as? [String: Any],
            let token = dataDict["token"] as? String
        else {
            throw FeishuError.invalidResponse
        }

        return token
    }
}

enum FeishuError: Error {
    case invalidConfiguration
    case requestFailed
    case invalidResponse
}
