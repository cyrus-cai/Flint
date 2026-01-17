//
//  SubscriptionManager.swift
//  Writedown
//
//  Created by Claude on 2025/01/13.
//  Centralized subscription management with periodic validation
//

import Foundation
import Combine
import AppKit

// MARK: - Notification Names

extension Notification.Name {
    /// 订阅状态发生变化时发送
    static let subscriptionStatusDidChange = Notification.Name("SubscriptionStatusDidChange")
    /// 订阅验证失败时发送
    static let subscriptionValidationFailed = Notification.Name("SubscriptionValidationFailed")
}

// MARK: - SubscriptionManager

/// 订阅管理器 - 集中管理订阅状态验证和缓存
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // MARK: - Published Properties

    /// 当前是否为 Pro 用户
    @Published private(set) var isPro: Bool = false

    /// 是否正在验证订阅状态
    @Published private(set) var isValidating: Bool = false

    /// 最后一次验证错误
    @Published private(set) var lastValidationError: Error?

    // MARK: - Private Properties

    private let proStatusChecker = ProStatusChecker.shared
    private let deviceManager = DeviceManager.shared
    private var cancellables = Set<AnyCancellable>()

    /// UserDefaults keys
    private let cachedProStatusKey = "cachedProStatus"

    // MARK: - Initialization

    private init() {
        // 从缓存加载初始状态
        isPro = UserDefaults.standard.bool(forKey: AppStorageKeys.isPro)

        // 监听应用激活事件，每次激活都验证订阅状态
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .debounce(for: .seconds(1), scheduler: RunLoop.main) // 防抖避免重复触发
            .sink { [weak self] _ in
                Task {
                    await self?.validateSubscriptionStatus()
                }
            }
            .store(in: &cancellables)

        // 初始验证
        Task {
            await validateSubscriptionStatus()
        }
    }

    // MARK: - Public Methods

    /// 强制验证订阅状态 (用于手动刷新/恢复购买)
    @MainActor
    func forceValidate() async {
        await validateSubscriptionStatus(force: true)
    }


    /// 恢复购买
    /// - Returns: 成功返回 isPro 状态，失败返回错误
    @MainActor
    func restorePurchase() async -> Result<Bool, Error> {
        guard !isValidating else {
            return .failure(SubscriptionError.alreadyValidating)
        }

        isValidating = true
        defer { isValidating = false }

        guard let deviceId = deviceManager.getDeviceIdentifier() else {
            let error = SubscriptionError.deviceIdUnavailable
            lastValidationError = error
            return .failure(error)
        }

        do {
            let isPro = try await proStatusChecker.checkProStatus(deviceId: deviceId)
            updateProStatus(isPro)

            return .success(isPro)
        } catch {
            lastValidationError = error
            return .failure(error)
        }
    }

    /// 手动设置 Pro 状态 (用于支付成功后立即更新)
    @MainActor
    func setProStatus(_ isPro: Bool) {
        updateProStatus(isPro)
    }

    // MARK: - Private Methods

    @MainActor
    private func validateSubscriptionStatus(force: Bool = false) async {
        guard !isValidating else { return }

        isValidating = true
        defer { isValidating = false }

        guard let deviceId = deviceManager.getDeviceIdentifier() else {
            print("❌ Failed to retrieve device identifier for subscription validation")
            lastValidationError = SubscriptionError.deviceIdUnavailable
            return
        }

        do {
            let newProStatus = try await proStatusChecker.checkProStatus(deviceId: deviceId)
            updateProStatus(newProStatus)
            lastValidationError = nil

            print("✅ Subscription status validated: isPro = \(newProStatus)")
        } catch {
            print("❌ Subscription validation failed: \(error)")
            lastValidationError = error

            // 验证失败时发送通知
            NotificationCenter.default.post(
                name: .subscriptionValidationFailed,
                object: nil,
                userInfo: ["error": error]
            )
        }
    }

    private func updateProStatus(_ newStatus: Bool) {
        let oldStatus = isPro

        // 在主线程更新
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.isPro = newStatus

            // 更新 UserDefaults
            UserDefaults.standard.set(newStatus, forKey: AppStorageKeys.isPro)
            UserDefaults.standard.set(newStatus, forKey: self.cachedProStatusKey)

            // 如果状态发生变化，发送通知
            if oldStatus != newStatus {
                NotificationCenter.default.post(
                    name: .subscriptionStatusDidChange,
                    object: nil,
                    userInfo: ["isPro": newStatus]
                )

                // 同时发送旧的通知以保持兼容性
                NotificationCenter.default.post(
                    name: NSNotification.Name("SubscriptionDidUpdate"),
                    object: nil
                )
            }
        }
    }
}

// MARK: - Error Types

enum SubscriptionError: LocalizedError {
    case deviceIdUnavailable
    case networkError(underlying: Error)
    case validationFailed
    case alreadyValidating

    var errorDescription: String? {
        switch self {
        case .deviceIdUnavailable:
            return "Unable to retrieve device identifier"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .validationFailed:
            return "Failed to validate subscription status"
        case .alreadyValidating:
            return "Validation already in progress"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .deviceIdUnavailable:
            return "Please restart the application"
        case .networkError:
            return "Please check your internet connection and try again"
        case .validationFailed:
            return "Please try again later"
        case .alreadyValidating:
            return "Please wait for the current validation to complete"
        }
    }
}
