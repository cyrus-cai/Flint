//
//  StripeCheckout.swift
//  Writedown
//
//  Created by LC John on 1/29/25.
//

import Foundation

struct StripeCheckout {
    static let secretKey =
        "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"
    //     static let proPriceID = "price_1QoPMGHnr11wuS0JpXUv9kBX"
    static let proPriceID = "price_1QoPDkHnr11wuS0JwGaH8Koq"
    //    static let proPriceID = "price_1QoNnRHnr11wuS0JQKbpAJj5"

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

    struct CheckoutSessionResponse: Codable {
        let id: String
        let url: String

        private enum CodingKeys: String, CodingKey {
            case id
            case url
        }
    }

    struct StripeErrorResponse: Codable {
        let error: StripeErrorDetail
    }

    struct StripeErrorDetail: Codable {
        let message: String
    }

    static func createCheckoutSession(request: CheckoutRequest, origin: String) async
        -> CheckoutResponse
    {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Authorization": "Bearer \(secretKey)",
            "Content-Type": "application/x-www-form-urlencoded",
        ]

        let session = URLSession(configuration: config)

        do {
            // Build Stripe request parameters
            var bodyComponents = URLComponents()
            var queryItems = [
                URLQueryItem(name: "line_items[0][price]", value: proPriceID),
                URLQueryItem(name: "line_items[0][quantity]", value: "1"),
                URLQueryItem(name: "mode", value: "payment"),
                URLQueryItem(
                    name: "success_url", value: "\(origin)?session_id={CHECKOUT_SESSION_ID}"),
                URLQueryItem(name: "cancel_url", value: origin),
            ]

            // Only add email if provided
            if let email = request.email, !email.isEmpty {
                queryItems.append(URLQueryItem(name: "customer_email", value: email))
            }

            // Add device ID as client_reference_id if available
            if let deviceId = request.deviceId {
                queryItems.append(URLQueryItem(name: "client_reference_id", value: deviceId))
            }

            bodyComponents.queryItems = queryItems

            var request = URLRequest(
                url: URL(string: "https://api.stripe.com/v1/checkout/sessions")!)
            request.httpMethod = "POST"
            request.httpBody = bodyComponents.query?.data(using: .utf8)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return CheckoutResponse(
                    url: nil,
                    error: ErrorResponse(message: "Invalid response from Stripe"))
            }

            if httpResponse.statusCode == 200 {
                let sessionObject = try JSONDecoder().decode(
                    CheckoutSessionResponse.self, from: data)
                return CheckoutResponse(url: sessionObject.url, error: nil)
            } else {
                let errorResponse = try JSONDecoder().decode(StripeErrorResponse.self, from: data)
                return CheckoutResponse(
                    url: nil, error: ErrorResponse(message: errorResponse.error.message))
            }
        } catch {
            return CheckoutResponse(
                url: nil,
                error: ErrorResponse(message: error.localizedDescription)
            )
        }
        //        return CheckoutResponse(
        //            url: nil,
        //            error: ErrorResponse(message: "Unexpected error")
        //        )
    }
}
