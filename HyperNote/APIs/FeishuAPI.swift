import Foundation

public class FeishuAPI {
    static let shared = FeishuAPI()
    private let baseURL = "https://open.feishu.cn/open-apis"
    private var accessToken: String?

    // Configuration keys
    private let kFeishuEnabled = "FeishuSyncEnabled"
    private let kFeishuAccessToken = "FeishuAccessToken"
    private let kFeishuTokenExpiration = "FeishuTokenExpiration"
    private let kFeishuRefreshToken = "FeishuRefreshToken"

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

    func configure(accessToken: String, expiresIn: Int = 7200, refreshToken: String? = nil) {
        self.accessToken = accessToken
        self.isEnabled = true

        // Save token and expiration time
        let defaults = UserDefaults.standard
        defaults.set(accessToken, forKey: kFeishuAccessToken)

        // Calculate and save expiration date
        let expirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        defaults.set(expirationDate, forKey: kFeishuTokenExpiration)

        // Save refresh token if provided
        if let refreshToken = refreshToken {
            defaults.set(refreshToken, forKey: kFeishuRefreshToken)
        }
    }

    private func loadSavedToken() {
        let defaults = UserDefaults.standard

        // Check if we have a saved token and it hasn't expired
        if let savedToken = defaults.string(forKey: kFeishuAccessToken),
            let expirationDate = defaults.object(forKey: kFeishuTokenExpiration) as? Date
        {
            // If token will expire in less than 10 minutes, try to refresh it
            let tenMinutesFromNow = Date().addingTimeInterval(600)  // 10 minutes in seconds

            if expirationDate <= tenMinutesFromNow {
                // Token is about to expire, try to refresh
                if let refreshToken = defaults.string(forKey: kFeishuRefreshToken) {
                    Task {
                        do {
                            let newTokens = try await FeishuAuthManager.refreshAccessToken(
                                refreshToken: refreshToken)
                            // Configure with new tokens
                            self.configure(
                                accessToken: newTokens.accessToken,
                                expiresIn: newTokens.expiresIn,
                                refreshToken: newTokens.refreshToken
                            )
                        } catch {
                            print("Failed to refresh token: \(error)")
                            // If refresh fails and current token is already expired
                            if expirationDate <= Date() {
                                self.clearToken()
                            }
                        }
                    }
                }
            } else if expirationDate > Date() {
                // Token is still valid
                self.accessToken = savedToken
                self.isEnabled = true
            } else {
                // Token is expired and we can't refresh it
                self.clearToken()
            }
        } else {
            // No token saved or expired
            self.clearToken()
        }
    }

    func clearToken() {
        self.accessToken = nil
        self.isEnabled = false

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: kFeishuAccessToken)
        defaults.removeObject(forKey: kFeishuTokenExpiration)

        // Don't clear refresh token as it's valid for 365 days
        // Only clear it when:
        // 1. User explicitly logs out
        // 2. Server returns refresh token expired error (20037)
        // 3. Server returns refresh token revoked error (20064)
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

    func createDocument(folderToken: String, title: String) async throws -> String {
        print("Creating Feishu document:")
        print("- Title: \(title)")
        print("- Folder Token: \(folderToken)")

        // First check if document already exists in the folder
        if let existingDoc = try await checkDocumentExists(name: title, folderToken: folderToken) {
            print("✅✅✅ Document already exists:")
            print("- Document name: \(title)")
            print("- Token: \(existingDoc)")
            return existingDoc
        }

        let endpoint = "\(baseURL)/docx/v1/documents"
        let parameters: [String: Any] = [
            "title": title,
            "folder_token": folderToken,
        ]

        guard let url = URL(string: endpoint),
            let accessToken = self.accessToken
        else {
            print("❌ Invalid configuration - URL or access token missing")
            throw FeishuError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataDict = responseDict["data"] as? [String: Any],
            let documentId = dataDict["document_id"] as? String
        else {
            print("❌ Failed to create document")
            if let errorData = String(data: data, encoding: .utf8) {
                print("Error details: \(errorData)")
            }
            throw FeishuError.requestFailed
        }

        print("✅ Successfully created document:")
        print("- Document ID: \(documentId)")

        return documentId
    }

    func addDocumentContent(documentId: String, content: String) async throws {
        print("Syncing document content:")
        print("- Document ID: \(documentId)")
        print("- Content length: \(content.count) characters")

        // Get all blocks with pagination
        var allBlocks: [BlocksResponse.Block] = []
        var pageToken: String? = nil

        repeat {
            let blocksEndpoint = "\(baseURL)/docx/v1/documents/\(documentId)/blocks"
            guard var components = URLComponents(string: blocksEndpoint),
                let accessToken = self.accessToken
            else {
                print("❌ Invalid configuration - URL or access token missing")
                throw FeishuError.invalidConfiguration
            }

            // Build query parameters
            var queryItems = [
                URLQueryItem(name: "page_size", value: "500")
            ]
            if let pageToken = pageToken {
                queryItems.append(URLQueryItem(name: "page_token", value: pageToken))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                throw FeishuError.invalidConfiguration
            }

            var blocksRequest = URLRequest(url: url)
            blocksRequest.httpMethod = "GET"
            blocksRequest.setValue(
                "application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            blocksRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (blocksData, blocksResponse) = try await URLSession.shared.data(for: blocksRequest)
            guard let blocksHttpResponse = blocksResponse as? HTTPURLResponse,
                blocksHttpResponse.statusCode == 200,
                let blocksResponseData = try? JSONDecoder().decode(
                    BlocksResponse.self, from: blocksData)
            else {
                print("❌ Failed to get document blocks")
                throw FeishuError.requestFailed
            }

            // Add blocks from current page
            allBlocks.append(contentsOf: blocksResponseData.data.items)

            // Update page token for next iteration
            pageToken = blocksResponseData.data.hasMore ? blocksResponseData.data.pageToken : nil

        } while pageToken != nil

        // Delete all existing blocks except the root
        let deleteEndpoint =
            "\(baseURL)/docx/v1/documents/\(documentId)/blocks/\(documentId)/children/batch_delete"
        guard let deleteUrl = URL(string: deleteEndpoint),
            let accessToken = self.accessToken
        else {
            print("❌ Invalid configuration:")
            print("- URL or access token is missing")
            throw FeishuError.invalidConfiguration
        }

        print("\nRequest details:")
        print("- URL: \(deleteEndpoint)")
        print("- Access Token: \(String(accessToken.prefix(10)))...")

        // Count the number of direct children of the root
        let rootChildrenCount = allBlocks.filter { $0.parentId == documentId }.count

        if rootChildrenCount > 0 {
            let deleteParameters: [String: Any] = [
                "start_index": 0,
                "end_index": rootChildrenCount,
            ]

            print("- Parameters: \(deleteParameters)")

            var deleteRequest = URLRequest(url: deleteUrl)
            deleteRequest.httpMethod = "DELETE"
            deleteRequest.setValue(
                "application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            deleteRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            deleteRequest.httpBody = try JSONSerialization.data(withJSONObject: deleteParameters)

            let (deleteData, deleteResponse) = try await URLSession.shared.data(for: deleteRequest)
            guard let deleteHttpResponse = deleteResponse as? HTTPURLResponse,
                deleteHttpResponse.statusCode == 200
            else {
                print("\n❌ Delete request failed:")
                print("- Response: \(deleteResponse)")
                if let errorData = String(data: deleteData, encoding: .utf8) {
                    print("- Error details: \(errorData)")
                }
                throw FeishuError.requestFailed
            }

            print("\n✅ Successfully deleted \(rootChildrenCount) blocks")
        }

        // Split content into paragraphs
        let paragraphs = content.components(separatedBy: .newlines)
        var childrenIds = [String]()
        var descendants = [[String: Any]]()

        // Create a block for each paragraph
        for (index, paragraph) in paragraphs.enumerated() {
            guard !paragraph.isEmpty else { continue }

            let blockId = "paragraph_\(index)"
            childrenIds.append(blockId)

            let block: [String: Any] = [
                "block_id": blockId,
                "block_type": 2,  // text block
                "text": [
                    "elements": [
                        [
                            "text_run": [
                                "content": paragraph
                            ]
                        ]
                    ]
                ],
                "children": [],
            ]
            descendants.append(block)
        }

        // If no content, add an empty paragraph
        if descendants.isEmpty {
            childrenIds = ["empty_paragraph"]
            descendants = [
                [
                    "block_id": "empty_paragraph",
                    "block_type": 2,
                    "text": [
                        "elements": [
                            [
                                "text_run": [
                                    "content": ""
                                ]
                            ]
                        ]
                    ],
                    "children": [],
                ]
            ]
        }

        // Add new content using the descendant API
        let endpoint = "\(baseURL)/docx/v1/documents/\(documentId)/blocks/\(documentId)/descendant"
        let parameters: [String: Any] = [
            "children_id": childrenIds,
            "descendants": descendants,
        ]

        guard let url = URL(string: endpoint) else {
            throw FeishuError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            print("❌ Failed to sync document content")
            if let errorData = String(data: data, encoding: .utf8) {
                print("Error details: \(errorData)")
            }
            throw FeishuError.requestFailed
        }

        print("✅ Successfully synced document content")
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

    private func checkDocumentExists(name: String, folderToken: String) async throws -> String? {
        let endpoint = "\(baseURL)/drive/v1/files"

        guard var components = URLComponents(string: endpoint) else {
            throw FeishuError.invalidConfiguration
        }

        // Build query parameters
        var queryItems = [URLQueryItem]()
        queryItems.append(URLQueryItem(name: "page_size", value: "200"))
        queryItems.append(URLQueryItem(name: "folder_token", value: folderToken))
        queryItems.append(URLQueryItem(name: "order_by", value: "CreatedTime"))
        queryItems.append(URLQueryItem(name: "direction", value: "DESC"))

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

        print("\n🔍 Searching for document:")
        print("- Name: \(name)")
        print("- Folder Token: \(folderToken)")
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

        // Search for matching document
        for file in files {
            if let itemName = file["name"] as? String,
                let token = file["token"] as? String,
                let type = file["type"] as? String
            {
                print("Comparing: '\(itemName)' vs '\(name)'")
                print("Type: \(type)")

                if itemName == name {
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

// Update the BlocksResponse struct to include children
struct BlocksResponse: Codable {
    struct Data: Codable {
        let items: [Block]
        let hasMore: Bool
        let pageToken: String?

        enum CodingKeys: String, CodingKey {
            case items
            case hasMore = "has_more"
            case pageToken = "page_token"
        }
    }

    struct Block: Codable {
        let blockId: String
        let blockType: Int
        let children: [String]?
        let parentId: String?

        enum CodingKeys: String, CodingKey {
            case blockId = "block_id"
            case blockType = "block_type"
            case children
            case parentId = "parent_id"
        }
    }

    let code: Int
    let msg: String
    let data: Data
}
