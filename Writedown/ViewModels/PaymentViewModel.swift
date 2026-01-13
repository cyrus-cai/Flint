//
//  PaymentViewModel.swift
//  Writedown
//
//  Created by Claude on 2025/01/13.
//  Payment flow state management with loading states and error handling
//

import Foundation
import Combine
import AppKit

// MARK: - PaymentViewModel

@MainActor
final class PaymentViewModel: ObservableObject {

    // MARK: - Published State

    /// 是否正在处理支付
    @Published var isProcessing: Bool = false

    /// 当前错误
    @Published var error: PaymentError?

    /// 是否显示成功提示
    @Published var showSuccessAlert: Bool = false

    // MARK: - Error Types

    enum PaymentError: LocalizedError, Identifiable {
        var id: String { localizedDescription }

        case networkError(message: String)
        case paymentFailed(message: String)
        case cancelled
        case noSubscriptionFound

        var errorDescription: String? {
            switch self {
            case .networkError(let message):
                return "Network Error: \(message)"
            case .paymentFailed(let message):
                return "Payment Failed: \(message)"
            case .cancelled:
                return "Payment was cancelled"
            case .noSubscriptionFound:
                return "No subscription found"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .networkError:
                return "Please check your internet connection and try again."
            case .paymentFailed:
                return "Please try again or contact support."
            case .cancelled:
                return nil
            case .noSubscriptionFound:
                return "No active subscription was found for this device. Please purchase a subscription."
            }
        }
    }

    // MARK: - Public Methods

    /// 开始支付流程
    /// - Parameter email: 可选的用户邮箱
    func startPayment(email: String? = nil) async {
        guard !isProcessing else { return }

        isProcessing = true
        error = nil

        defer { isProcessing = false }

        let request = StripeCheckout.CheckoutRequest(
            planId: "pro",
            email: email ?? UserDefaults.standard.string(forKey: AppStorageKeys.userEmail),
            deviceId: DeviceManager.shared.getDeviceIdentifier()
        )

        let response = await StripeCheckout.createCheckoutSession(
            request: request,
            origin: "https://www.writedown.space/stripePayment"
        )

        if let errorResponse = response.error {
            self.error = .paymentFailed(message: errorResponse.message)
            return
        }

        guard let urlString = response.url, let url = URL(string: urlString) else {
            self.error = .networkError(message: "Invalid payment URL received")
            return
        }

        // 打开支付页面
        NSWorkspace.shared.open(url)
    }

    /// 处理支付回调
    /// - Parameter sessionId: Stripe session ID
    func handlePaymentCallback(sessionId: String) async {
        guard !isProcessing else { return }

        isProcessing = true
        error = nil

        defer { isProcessing = false }

        do {
            let verified = try await verifyPayment(sessionId: sessionId)
            if verified {
                showSuccessAlert = true
                // 更新订阅状态
                SubscriptionManager.shared.setProStatus(true)
            } else {
                error = .paymentFailed(message: "Payment verification failed")
            }
        } catch {
            self.error = .networkError(message: error.localizedDescription)
        }
    }

    /// 恢复购买
    func restorePurchase() async {
        guard !isProcessing else { return }

        isProcessing = true
        error = nil

        defer { isProcessing = false }

        let result = await SubscriptionManager.shared.restorePurchase()

        switch result {
        case .success(let isPro):
            if isPro {
                showSuccessAlert = true
            } else {
                error = .noSubscriptionFound
            }
        case .failure(let err):
            error = .networkError(message: err.localizedDescription)
        }
    }

    /// 重试上次失败的操作
    func retry() async {
        error = nil
        await startPayment()
    }

    /// 清除错误状态
    func clearError() {
        error = nil
    }

    // MARK: - Private Methods

    private func verifyPayment(sessionId: String) async throws -> Bool {
        guard let url = URL(string: "https://www.writedown.space/verify-payment?session_id=\(sessionId)") else {
            throw PaymentError.networkError(message: "Invalid verification URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return false
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            return false
        }

        return status == "success"
    }
}
