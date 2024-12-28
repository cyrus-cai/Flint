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
        print("Creating Feishu document:")
        print("- Title: \(title)")
        print("- Folder Token: \(folderToken)")
        print("- Content length: \(content.count) characters")

        let endpoint = "\(baseURL)/docx/v1/documents"
        let parameters: [String: Any] = [
            "title": title,
            "folder_token": folderToken,
            "content": content,  // 添加文档内容
        ]

        guard let url = URL(string: endpoint),
            let accessToken = self.accessToken
        else {
            print("❌ Invalid configuration - URL or access token missing")
            throw FeishuError.invalidConfiguration
        }

        print("Request details:")
        print("- URL: \(endpoint)")
        print("- Access Token: \(String(accessToken.prefix(10)))...")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            print("❌ Feishu createDocument failed:")
            print("- Response: \(response)")
            if let errorData = String(data: data, encoding: .utf8) {
                print("- Error details: \(errorData)")
            }
            throw FeishuError.requestFailed
        }

        print("✅ Successfully created document:")
        print("- Title: \(title)")
        print("- Response status: \(httpResponse.statusCode)")
    }

    private func createFolder(endpoint: String, parameters: [String: Any]) async throws -> String {
        print("\n📁 Creating Feishu folder:")
        print("- Endpoint: \(endpoint)")
        print("- Parameters: \(parameters)")

        guard let url = URL(string: endpoint),
            let accessToken = self.accessToken
        else {
            print("❌ Invalid configuration:")
            print("- URL or access token is missing")
            throw FeishuError.invalidConfiguration
        }

        print("\nRequest details:")
        print("- URL: \(endpoint)")
        print("- Access Token: \(String(accessToken.prefix(10)))...")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            print("\n❌ Feishu createFolder failed:")
            print("- Response: \(response)")
            if let errorData = String(data: data, encoding: .utf8) {
                print("- Error details: \(errorData)")
            }
            throw FeishuError.requestFailed
        }

        guard let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataDict = responseDict["data"] as? [String: Any],
            let token = dataDict["token"] as? String
        else {
            print("\n❌ Invalid response format")
            print("- Response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            throw FeishuError.invalidResponse
        }

        print("\n✅ Successfully created folder:")
        print("- Folder token: \(token)")
        print("- Response status: \(httpResponse.statusCode)")

        return token
    }
}

enum FeishuError: Error {
    case invalidConfiguration
    case requestFailed
    case invalidResponse
    case httpError(statusCode: Int)
}
