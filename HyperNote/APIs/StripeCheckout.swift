//
//  StripeCheckout.swift
//  HyperNote
//
//  Created by LC John on 1/29/25.
//

import Foundation

struct StripeCheckout {
    static let secretKey =
        "sk_test_51O4PcgHnr11wuS0JOVgLCOU5xi5OhqrfpXDSnSeVFSChKnkv1PYCgaybY8eFJG1AvRMqH57BsRcJtmzBz7bbF59q00nWZ2XoGt"
    static let proPriceID = "price_1QmbpsHnr11wuS0JZpfiRgwD"

    struct CheckoutRequest: Codable {
        let planId: String
        let email: String?
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
