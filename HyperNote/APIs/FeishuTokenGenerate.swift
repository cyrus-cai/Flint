//Fucking troublesome feishu

import Foundation

//1、获取授权码 Code
//https://open.feishu.cn/document/common-capabilities/sso/api/obtain-oauth-code

//2、获取 user_access_token
//https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/authentication-management/access-token/get-user-access-token
//grant_type + client_id + client_secret + code + redirect_uri

//{
//"access_token": "eyJhbGciOiJFUzI1NiIs**********X6wrZHYKDxJkWwhdkrYg",
//"expires_in": 7200, // 非固定值，请务必根据响应体中返回的实际值来确定 access_token 的有效期
//"refresh_token": "eyJhbGciOiJFUzI1NiIs**********XXOYOZz1mfgIYHwM8ZJA",
//"refresh_token_expires_in": 604800, // 非固定值，请务必根据响应体中返回的实际值来确定 refresh_token 的有效期
//"scope": "auth:user.id:read offline_access task:task:read user_profile",
//"token_type": "Bearer"
//}

struct FeishuAuthConfig {
    static let clientId = "cli_a7e563ddc4b8501c"  // 替换为你的 App ID
    static let redirectUri = "https://float-auth-landingpage.vercel.app/"
    static let scopes = ["auth:user.id:read", "offline_access", "docx:document"]  // 需要的权限范围
}

class FeishuAuthManager {
    static func generateAuthorizationURL() -> URL? {
        var components = URLComponents(
            string: "https://accounts.feishu.cn/open-apis/authen/v1/authorize")

        let state = UUID().uuidString
        print("🔐 Generating Feishu auth URL with state: \(state)")

        let queryItems = [
            URLQueryItem(name: "client_id", value: FeishuAuthConfig.clientId),
            URLQueryItem(name: "redirect_uri", value: FeishuAuthConfig.redirectUri),
            URLQueryItem(name: "scope", value: FeishuAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]

        components?.queryItems = queryItems

        if let url = components?.url {
            print("📤 Generated Feishu auth URL: \(url)")
            return url
        } else {
            print("❌ Failed to generate Feishu auth URL")
            return nil
        }
    }

    static func handleAuthCallback(url: URL) -> String? {
        print("📥 Handling Feishu auth callback: \(url)")

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let queryItems = components.queryItems
        else {
            print("❌ Failed to parse callback URL")
            return nil
        }

        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            print("❌ Authorization error: \(error)")
            return nil
        }

        if let code = queryItems.first(where: { $0.name == "code" })?.value {
            print("✅ Successfully obtained auth code")
            return code
        } else {
            print("❌ No auth code found in callback")
            return nil
        }
    }
}
