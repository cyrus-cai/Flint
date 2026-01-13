//
//  StripeCheckout.swift
//  Writedown
//
//  Created by LC John on 1/29/25.
//  Refactored to use backend proxy for security
//

import Foundation

/// Stripe 支付服务 - 通过后端代理创建支付会话
/// 注意: 不在客户端存储任何 Stripe 密钥，所有敏感操作由后端处理
struct StripeCheckout {
    // 后端 API 端点
    private static let createSessionEndpoint = "https://www.writedown.space/api/create-checkout-session"

    // MARK: - Request/Response Types

    struct CheckoutRequest: Codable {
        let planId: String
        let email: String?
        let deviceId: String?
    }

    struct CheckoutResponse: Codable {
        let url: String?
        let error: ErrorResponse?
    }

    struct ErrorResponse: Codable {
        let message: String
    }

    // MARK: - Error Types

    enum CheckoutError: LocalizedError {
        case networkError(underlying: Error)
        case serverError(message: String)
        case invalidResponse
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .serverError(let message):
                return message
            case .invalidResponse:
                return "Invalid response from server"
            case .invalidURL:
                return "Invalid server URL"
            }
        }
    }

    // MARK: - Public Methods

    /// 通过后端创建 Stripe Checkout 会话
    /// - Parameters:
    ///   - request: 包含 planId, email, deviceId 的请求
    ///   - origin: 成功/取消后的回调 URL scheme
    /// - Returns: 包含支付 URL 或错误的响应
    static func createCheckoutSession(
        request: CheckoutRequest,
        origin: String
    ) async -> CheckoutResponse {
        do {
            guard let url = URL(string: createSessionEndpoint) else {
                return CheckoutResponse(
                    url: nil,
                    error: ErrorResponse(message: "Invalid endpoint URL")
                )
            }

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.timeoutInterval = 30

            // 构建请求体
            let body: [String: Any?] = [
                "planId": request.planId,
                "email": request.email,
                "deviceId": request.deviceId,
                "successUrl": "\(origin)?session_id={CHECKOUT_SESSION_ID}",
                "cancelUrl": origin
            ]

            // 移除 nil 值并序列化
            let filteredBody = body.compactMapValues { $0 }
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: filteredBody)

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                return CheckoutResponse(
                    url: nil,
                    error: ErrorResponse(message: "Invalid response type")
                )
            }

            // 调试日志
            #if DEBUG
            if let responseString = String(data: data, encoding: .utf8) {
                print("📡 Checkout API Response (\(httpResponse.statusCode)): \(responseString)")
            }
            #endif

            if httpResponse.statusCode == 200 {
                // 尝试解析成功响应
                let decoder = JSONDecoder()

                // 后端可能返回 { "url": "..." } 或 { "checkoutUrl": "..." }
                if let sessionResponse = try? decoder.decode(CheckoutResponse.self, from: data) {
                    return sessionResponse
                }

                // 备用解析：直接解析 JSON
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let checkoutUrl = json["url"] as? String ?? json["checkoutUrl"] as? String {
                    return CheckoutResponse(url: checkoutUrl, error: nil)
                }

                return CheckoutResponse(
                    url: nil,
                    error: ErrorResponse(message: "Failed to parse checkout URL")
                )
            } else {
                // 尝试解析错误信息
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = json["error"] as? String ?? json["message"] as? String {
                    return CheckoutResponse(
                        url: nil,
                        error: ErrorResponse(message: errorMessage)
                    )
                }

                return CheckoutResponse(
                    url: nil,
                    error: ErrorResponse(message: "Server error: \(httpResponse.statusCode)")
                )
            }
        } catch {
            print("❌ Checkout session creation failed: \(error)")
            return CheckoutResponse(
                url: nil,
                error: ErrorResponse(message: error.localizedDescription)
            )
        }
    }
}
