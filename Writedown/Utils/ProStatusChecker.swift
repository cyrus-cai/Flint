//
//  ProStatusChecker.swift
//  Writedown
//
//  Created by LC John on 2/1/25.
//  Enhanced with retry mechanism
//

import Foundation
import IOKit

// MARK: - ProStatusChecker

class ProStatusChecker {
    static let shared = ProStatusChecker()
    private let baseURL = "https://www.writedown.space/api/proStatus"

    /// 默认重试次数
    private let defaultRetryCount = 3

    /// 请求超时时间
    private let requestTimeout: TimeInterval = 15

    struct ProStatusResponse: Codable {
        let isPro: Bool
    }

    /// 检查 Pro 状态（带自动重试）
    /// - Parameters:
    ///   - deviceId: 设备 ID
    ///   - retryCount: 重试次数，默认 3 次
    /// - Returns: 是否为 Pro 用户
    func checkProStatus(deviceId: String, retryCount: Int? = nil) async throws -> Bool {
        let maxRetries = retryCount ?? defaultRetryCount
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                return try await performProStatusCheck(deviceId: deviceId)
            } catch {
                lastError = error
                print("⚠️ Pro status check attempt \(attempt)/\(maxRetries) failed: \(error.localizedDescription)")

                // 如果不是最后一次尝试，等待后重试
                if attempt < maxRetries {
                    // 指数退避: 1s, 2s, 4s
                    let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }

        throw lastError ?? ProStatusError.requestFailed
    }

    /// 执行单次 Pro 状态检查
    private func performProStatusCheck(deviceId: String) async throws -> Bool {
        var urlComponents = URLComponents(string: baseURL)
        urlComponents?.queryItems = [URLQueryItem(name: "device_id", value: deviceId)]

        guard let url = urlComponents?.url else {
            print("❌ URL configuration failed")
            throw ProStatusError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout

        #if DEBUG
        print("🔍 Checking pro status for device: \(deviceId)")
        print("📡 Request URL: \(url.absoluteString)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw ProStatusError.invalidResponse
        }

        #if DEBUG
        print("📥 Response status code: \(httpResponse.statusCode)")
        #endif

        if httpResponse.statusCode != 200 {
            #if DEBUG
            if let responseData = String(data: data, encoding: .utf8) {
                print("❌ Request failed with status code: \(httpResponse.statusCode)")
                print("📄 Response body: \(responseData)")
            }
            #endif
            throw ProStatusError.requestFailed
        }

        do {
            let proStatus = try JSONDecoder().decode(ProStatusResponse.self, from: data)
            #if DEBUG
            print("✅ Pro status response: \(proStatus.isPro)")
            #endif
            return proStatus.isPro
        } catch {
            #if DEBUG
            print("❌ JSON decoding failed: \(error)")
            if let responseData = String(data: data, encoding: .utf8) {
                print("📄 Raw response data: \(responseData)")
            }
            #endif
            throw ProStatusError.decodingFailed
        }
    }
}

// MARK: - ProStatusError

enum ProStatusError: LocalizedError {
    case invalidConfiguration
    case requestFailed
    case invalidResponse
    case decodingFailed
    case networkError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The pro status checker is not properly configured"
        case .requestFailed:
            return "Failed to check pro status"
        case .invalidResponse:
            return "Received an invalid response from the server"
        case .decodingFailed:
            return "Failed to parse server response"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidConfiguration:
            return "Please contact support"
        case .requestFailed, .invalidResponse, .decodingFailed:
            return "Please try again later"
        case .networkError:
            return "Please check your internet connection"
        }
    }
}

// MARK: - DeviceManager

class DeviceManager {
    static let shared = DeviceManager()

    /// 缓存的设备 ID
    private var cachedDeviceId: String?

    /// Retrieves the hardware UUID of the Mac.
    /// This identifier is tied to the physical logic board of the device.
    func getDeviceIdentifier() -> String? {
        // 使用缓存避免重复 IOKit 调用
        if let cached = cachedDeviceId {
            return cached
        }

        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )

        guard platformExpert > 0 else {
            return nil
        }

        defer { IOObjectRelease(platformExpert) }

        guard let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ).takeRetainedValue() as? String else {
            return nil
        }

        cachedDeviceId = uuid
        return uuid
    }
}
