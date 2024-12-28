import Foundation

public class FeishuAPI {
    static let shared = FeishuAPI()
    private let baseURL = "https://open.feishu.cn/open-apis"
    private var accessToken: String?

    // Configuration keys
    private let kFeishuEnabled = "FeishuSyncEnabled"
    private let kFeishuAccessToken = "FeishuAccessToken"
    private let kFeishuTokenExpiration = "FeishuTokenExpiration"

    var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: kFeishuEnabled)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: kFeishuEnabled)
        }
    }

    private init() {
        // Try to load saved token on initialization
        loadSavedToken()
    }

    func configure(accessToken: String, expiresIn: Int = 7200) {
        self.accessToken = accessToken

        // Save token and expiration time
        let defaults = UserDefaults.standard
        defaults.set(accessToken, forKey: kFeishuAccessToken)

        // Calculate and save expiration date
        let expirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        defaults.set(expirationDate, forKey: kFeishuTokenExpiration)
    }

    private func loadSavedToken() {
        let defaults = UserDefaults.standard

        // Check if we have a saved token and it hasn't expired
        if let savedToken = defaults.string(forKey: kFeishuAccessToken),
            let expirationDate = defaults.object(forKey: kFeishuTokenExpiration) as? Date,
            expirationDate > Date()
        {
            self.accessToken = savedToken
            self.isEnabled = true
        } else {
            // Token is either missing or expired
            self.accessToken = nil
            self.isEnabled = false

            // Clean up expired token
            defaults.removeObject(forKey: kFeishuAccessToken)
            defaults.removeObject(forKey: kFeishuTokenExpiration)
        }
    }

    func clearToken() {
        self.accessToken = nil
        self.isEnabled = false

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: kFeishuAccessToken)
        defaults.removeObject(forKey: kFeishuTokenExpiration)
    }

    func ensureRootFolder() async throws -> String {
        let endpoint = "\(baseURL)/drive/v1/files/create_folder"
        let parameters: [String: Any] = [
            "name": "Float",
            "folder_token": "",  // Empty for root directory
        ]

        return try await createFolder(
            endpoint: endpoint, parameters: parameters, folderName: "Float")
    }

    func createWeekFolder(parentToken: String, weekName: String) async throws -> String {
        // First check if the folder already exists under the parent
        if let existingToken = try await checkFolderExists(name: weekName, parentToken: parentToken)
        {
            print("✅✅✅ Week folder already exists:")
            print("- Folder name: \(weekName)")
            print("- Token: \(existingToken)")
            return existingToken
        }

        let endpoint = "\(baseURL)/drive/v1/files/create_folder"
        let parameters: [String: Any] = [
            "name": weekName,
            "folder_token": parentToken,
        ]

        return try await createFolder(
            endpoint: endpoint, parameters: parameters, folderName: weekName)
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

    private func createFolder(endpoint: String, parameters: [String: Any], folderName: String)
        async throws -> String
    {
        if let existingToken = try await checkFolderExists(name: folderName) {
            print("✅✅✅ Folder already exists:")
            print("- Folder name: \(folderName)")
            print("- Token: \(existingToken)")
            return existingToken
        }

        print("\n📁 Creating new Feishu folder:")
        print("- Folder name: \(folderName)")

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
        print("- Folder name: \(folderName)")
        print("- Folder token: \(token)")
        print("- Response status: \(httpResponse.statusCode)")

        return token
    }

    private func checkFolderExists(name: String, parentToken: String? = nil) async throws -> String?
    {
        let endpoint = "\(baseURL)/drive/v1/files"

        guard var components = URLComponents(string: endpoint) else {
            throw FeishuError.invalidConfiguration
        }

        // Build query parameters
        var queryItems = [URLQueryItem]()
        queryItems.append(URLQueryItem(name: "page_size", value: "200"))
        queryItems.append(URLQueryItem(name: "order_by", value: "CreatedTime"))
        queryItems.append(URLQueryItem(name: "direction", value: "DESC"))

        // Add parent folder token if provided
        if let parentToken = parentToken {
            queryItems.append(URLQueryItem(name: "folder_token", value: parentToken))
        }

        components.queryItems = queryItems

        guard let url = components.url,
            let accessToken = self.accessToken
        else {
            throw FeishuError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        print("\n🔍 Searching for folder:")
        print("- Name: \(name)")
        print("- Parent Token: \(parentToken ?? "root")")
        print("- URL: \(url)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response")
            return nil
        }

        if httpResponse.statusCode != 200 {
            print("❌ Request failed with status code: \(httpResponse.statusCode)")
            if let errorData = String(data: data, encoding: .utf8) {
                print("- Error details: \(errorData)")
            }
            return nil
        }

        guard let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let code = responseDict["code"] as? Int,
            code == 0,
            let dataDict = responseDict["data"] as? [String: Any],
            let files = dataDict["files"] as? [[String: Any]]
        else {
            print("❌ Invalid response format")
            print("- Response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            return nil
        }

        print("📋 Found \(files.count) items")

        // Search for matching folder
        for file in files {
            if let itemName = file["name"] as? String,
                let token = file["token"] as? String,
                let type = file["type"] as? String
            {
                if itemName == name && type == "folder" {
                    print("✅ Found exact match:")
                    print("- Name: \(itemName)")
                    print("- Token: \(token)")
                    return token
                }
            }
        }

        print("❌ No exact match found for: \(name)")
        return nil
    }
}

enum FeishuError: Error {
    case invalidConfiguration
    case requestFailed
    case invalidResponse
    case httpError(statusCode: Int)
}
