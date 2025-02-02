////Fucking troublesome feishu
//
//import Foundation
//
////1、获取授权码 Code
////https://open.feishu.cn/document/common-capabilities/sso/api/obtain-oauth-code
//
////2、获取 user_access_token
////https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/authentication-management/access-token/get-user-access-token
////grant_type + client_id + client_secret + code + redirect_uri
//
////{
////"access_token": "eyJhbGciOiJFUzI1NiIs**********X6wrZHYKDxJkWwhdkrYg",
////"expires_in": 7200, // 非固定值，请务必根据响应体中返回的实际值来确定 access_token 的有效期
////"refresh_token": "eyJhbGciOiJFUzI1NiIs**********XXOYOZz1mfgIYHwM8ZJA",
////"refresh_token_expires_in": 604800, // 非固定值，请务必根据响应体中返回的实际值来确定 refresh_token 的有效期
////"scope": "auth:user.id:read offline_access task:task:read user_profile",
////"token_type": "Bearer"
////}
//
////3、刷新 access_token
////https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/authentication-management/access-token/refresh-user-access-token
//
//struct FeishuAuthConfig {
//    static let clientId = "cli_a7e563ddc4b8501c"  // 替换为你的 App ID
//    static let clientSecret = "UA3w8tyCE36wXbq5bJlrizzkZNEwBEKu"  // 添加 client secret
//    static let redirectUri = "https://float-auth-landingpage.vercel.app/"
//    static let scopes = [
//        "auth:user.id:read", "offline_access", "docx:document", "drive:drive",
//        "space:folder:create",
//    ]  // 需要的权限范围
//}
//
//class FeishuAuthManager {
//    static func generateAuthorizationURL() -> URL? {
//        var components = URLComponents(
//            string: "https://accounts.feishu.cn/open-apis/authen/v1/authorize")
//
//        let state = UUID().uuidString
//        print("🔐 Generating Feishu auth URL with state: \(state)")
//
//        let queryItems = [
//            URLQueryItem(name: "client_id", value: FeishuAuthConfig.clientId),
//            URLQueryItem(name: "redirect_uri", value: FeishuAuthConfig.redirectUri),
//            URLQueryItem(name: "scope", value: FeishuAuthConfig.scopes.joined(separator: " ")),
//            URLQueryItem(name: "state", value: state),
//        ]
//
//        components?.queryItems = queryItems
//
//        if let url = components?.url {
//            print("📤 Generated Feishu auth URL: \(url)")
//            return url
//        } else {
//            print("❌ Failed to generate Feishu auth URL")
//            return nil
//        }
//    }
//
//    static func handleAuthCallback(url: URL) -> String? {
//        print("📥 Handling Feishu auth callback: \(url)")
//
//        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
//            let queryItems = components.queryItems
//        else {
//            print("❌ Failed to parse callback URL")
//            return nil
//        }
//
//        if let error = queryItems.first(where: { $0.name == "error" })?.value {
//            print("❌ Authorization error: \(error)")
//            return nil
//        }
//
//        if let code = queryItems.first(where: { $0.name == "code" })?.value {
//            print("✅ Successfully obtained auth code")
//            return code
//        } else {
//            print("❌ No auth code found in callback")
//            return nil
//        }
//    }
//
//    static func getAccessToken(code: String) async throws -> FeishuTokenResponse {
//        print("🔑 Requesting access token with code: \(String(code.prefix(6)))...")
//
//        let url = URL(string: "https://open.feishu.cn/open-apis/authen/v2/oauth/token")!
//        var request = URLRequest(url: url)
//        request.httpMethod = "POST"
//        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
//
//        let body: [String: Any] = [
//            "grant_type": "authorization_code",
//            "client_id": FeishuAuthConfig.clientId,
//            "client_secret": FeishuAuthConfig.clientSecret,
//            "code": code,
//            "redirect_uri": FeishuAuthConfig.redirectUri,
//        ]
//
//        request.httpBody = try JSONSerialization.data(withJSONObject: body)
//        print("📤 Sending token request to Feishu...")
//
//        let (data, response) = try await URLSession.shared.data(for: request)
//
//        guard let httpResponse = response as? HTTPURLResponse else {
//            print("❌ Invalid response received from Feishu")
//            throw FeishuError.invalidResponse
//        }
//
//        if httpResponse.statusCode != 200 {
//            print("❌ HTTP error: \(httpResponse.statusCode)")
//            // Print response body for debugging if possible
//            if let errorBody = String(data: data, encoding: .utf8) {
//                print("Error details: \(errorBody)")
//            }
//            throw FeishuError.httpError(statusCode: httpResponse.statusCode)
//        }
//
//        let tokenResponse = try JSONDecoder().decode(FeishuTokenResponse.self, from: data)
//        print("✅ Successfully obtained access token")
//        print("📎 Token expires in: \(tokenResponse.expiresIn) seconds")
//        print("🔑 Token type: \(tokenResponse.tokenType)")
//        print("🎯 Granted scopes: \(tokenResponse.scope)")
//
//        return tokenResponse
//    }
//
//    static func refreshAccessToken(refreshToken: String, scope: String? = nil) async throws
//        -> FeishuTokenResponse
//    {
//        print("🔄 Refreshing access token...")
//
//        let url = URL(string: "https://open.feishu.cn/open-apis/authen/v2/oauth/token")!
//        var request = URLRequest(url: url)
//        request.httpMethod = "POST"
//        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
//
//        var body: [String: Any] = [
//            "grant_type": "refresh_token",
//            "client_id": FeishuAuthConfig.clientId,
//            "client_secret": FeishuAuthConfig.clientSecret,
//            "refresh_token": refreshToken,
//        ]
//
//        // Add scope if provided
//        if let scope = scope {
//            body["scope"] = scope
//        }
//
//        request.httpBody = try JSONSerialization.data(withJSONObject: body)
//        print("📤 Sending refresh token request to Feishu...")
//
//        let (data, response) = try await URLSession.shared.data(for: request)
//
//        guard let httpResponse = response as? HTTPURLResponse else {
//            print("❌ Invalid response received from Feishu")
//            throw FeishuError.invalidResponse
//        }
//
//        if httpResponse.statusCode != 200 {
//            print("❌ HTTP error: \(httpResponse.statusCode)")
//            if let errorBody = String(data: data, encoding: .utf8) {
//                print("Error details: \(errorBody)")
//            }
//            throw FeishuError.httpError(statusCode: httpResponse.statusCode)
//        }
//
//        let tokenResponse = try JSONDecoder().decode(FeishuTokenResponse.self, from: data)
//        print("✅ Successfully refreshed access token")
//        print("📎 New token expires in: \(tokenResponse.expiresIn) seconds")
//        print("🔑 Token type: \(tokenResponse.tokenType)")
//        print("🎯 Granted scopes: \(tokenResponse.scope)")
//
//        return tokenResponse
//    }
//}
//
//// 添加响应模型
//struct FeishuTokenResponse: Codable {
//    let accessToken: String
//    let expiresIn: Int
//    let refreshToken: String?
//    let refreshTokenExpiresIn: Int?
//    let tokenType: String
//    let scope: String
//
//    enum CodingKeys: String, CodingKey {
//        case accessToken = "access_token"
//        case expiresIn = "expires_in"
//        case refreshToken = "refresh_token"
//        case refreshTokenExpiresIn = "refresh_token_expires_in"
//        case tokenType = "token_type"
//        case scope
//    }
//}
