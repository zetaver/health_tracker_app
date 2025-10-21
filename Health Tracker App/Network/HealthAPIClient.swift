//
//  HealthAPIClient.swift
//  Health Tracker App
//
//  Secure API client for communicating with backend server
//  Includes encryption, authentication, and retry logic
//

import Foundation
import CryptoKit

/// Secure API client for health data synchronization
actor HealthAPIClient {

    // MARK: - Configuration

    struct APIConfiguration {
        let baseURL: URL
        let apiKey: String
        let timeout: TimeInterval
        let maxRetries: Int
        let enableEncryption: Bool
        let enableCertificatePinning: Bool

        static let `default` = APIConfiguration(
            baseURL: URL(string: "https://api.healthtracker.example.com")!,
            apiKey: "", // Set from environment or secure storage
            timeout: 30,
            maxRetries: 3,
            enableEncryption: true,
            enableCertificatePinning: true
        )
    }

    // MARK: - API Endpoints

    enum Endpoint {
        case uploadHealthData
        case uploadBatch
        case getUserProfile
        case syncStatus
        case deleteData

        func path() -> String {
            switch self {
            case .uploadHealthData:
                return "/api/v1/health/upload"
            case .uploadBatch:
                return "/api/v1/health/batch"
            case .getUserProfile:
                return "/api/v1/user/profile"
            case .syncStatus:
                return "/api/v1/health/sync/status"
            case .deleteData:
                return "/api/v1/health/delete"
            }
        }
    }

    // MARK: - Request/Response Models

    struct UploadRequest: Codable {
        let userId: String
        let deviceId: String
        let timestamp: Date
        let data: String // Encrypted JSON payload
        let checksum: String
        let encryptionMetadata: EncryptionMetadata?

        struct EncryptionMetadata: Codable {
            let algorithm: String
            let keyId: String
            let iv: String // Base64 encoded initialization vector
        }
    }

    struct UploadResponse: Codable {
        let success: Bool
        let uploadId: String?
        let timestamp: Date
        let message: String?
        let errors: [String]?
    }

    struct SyncStatusResponse: Codable {
        let lastSyncTime: Date?
        let pendingUploads: Int
        let failedUploads: Int
        let totalSynced: Int
    }

    // MARK: - Properties

    private let configuration: APIConfiguration
    private let session: URLSession
    private let encryptionKey: SymmetricKey
    private let deviceId: String

    // Retry configuration
    private let retryDelays: [TimeInterval] = [1, 2, 4] // Exponential backoff

    // MARK: - Initialization

    init(configuration: APIConfiguration = .default) {
        self.configuration = configuration
        self.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        // Configure URLSession with security settings
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout * 2
        sessionConfig.httpMaximumConnectionsPerHost = 4
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfig.urlCache = nil // Disable caching for sensitive health data

        self.session = URLSession(configuration: sessionConfig)

        // Initialize or load encryption key from keychain
        self.encryptionKey = Self.loadOrGenerateEncryptionKey()
    }

    // MARK: - Upload Methods

    /// Uploads a batch of health data to the backend
    /// - Parameters:
    ///   - batch: The health data batch to upload
    ///   - userId: The user identifier
    /// - Returns: Upload response
    func uploadBatch(_ batch: HealthDataBatch, userId: String) async throws -> UploadResponse {
        // Serialize batch to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(batch)

        // Encrypt the data if enabled
        let (encryptedData, encryptionMeta) = try encryptData(jsonData)

        // Create upload request
        let request = UploadRequest(
            userId: userId,
            deviceId: deviceId,
            timestamp: Date(),
            data: encryptedData.base64EncodedString(),
            checksum: generateChecksum(for: jsonData),
            encryptionMetadata: encryptionMeta
        )

        // Send request with retry logic
        return try await sendRequest(endpoint: .uploadBatch, body: request)
    }

    /// Uploads individual health metrics
    /// - Parameters:
    ///   - metrics: Encodable health metrics
    ///   - userId: The user identifier
    /// - Returns: Upload response
    func uploadMetrics<T: Encodable>(_ metrics: T, userId: String) async throws -> UploadResponse {
        // Serialize metrics to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(metrics)

        // Encrypt the data if enabled
        let (encryptedData, encryptionMeta) = try encryptData(jsonData)

        // Create upload request
        let request = UploadRequest(
            userId: userId,
            deviceId: deviceId,
            timestamp: Date(),
            data: encryptedData.base64EncodedString(),
            checksum: generateChecksum(for: jsonData),
            encryptionMetadata: encryptionMeta
        )

        // Send request with retry logic
        return try await sendRequest(endpoint: .uploadHealthData, body: request)
    }

    /// Gets current sync status from backend
    /// - Parameter userId: The user identifier
    /// - Returns: Sync status response
    func getSyncStatus(userId: String) async throws -> SyncStatusResponse {
        var request = try createRequest(endpoint: .syncStatus, method: "GET")
        request.url = request.url?.appending(queryItems: [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "deviceId", value: deviceId)
        ])

        return try await sendRequest(request: request)
    }

    // MARK: - Request Building

    private func createRequest<T: Encodable>(endpoint: Endpoint, method: String = "POST", body: T? = nil) throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent(endpoint.path())
        var request = URLRequest(url: url)
        request.httpMethod = method

        // Set headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-App-ID")

        // Add body if provided
        if let body = body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    // MARK: - Request Sending

    private func sendRequest<T: Encodable, R: Decodable>(endpoint: Endpoint, body: T) async throws -> R {
        let request = try createRequest(endpoint: endpoint, body: body)
        return try await sendRequest(request: request)
    }

    private func sendRequest<R: Decodable>(request: URLRequest) async throws -> R {
        var lastError: Error?

        // Retry loop with exponential backoff
        for attempt in 0..<configuration.maxRetries {
            do {
                let (data, response) = try await session.data(for: request)

                // Validate response
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                // Check status code
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
                }

                // Decode response
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decodedResponse = try decoder.decode(R.self, from: data)

                return decodedResponse

            } catch {
                lastError = error

                // Don't retry on certain errors
                if let apiError = error as? APIError {
                    switch apiError {
                    case .httpError(let statusCode, _):
                        // Don't retry on client errors (4xx)
                        if (400...499).contains(statusCode) {
                            throw apiError
                        }
                    default:
                        break
                    }
                }

                // Wait before retry (exponential backoff)
                if attempt < configuration.maxRetries - 1 {
                    let delay = retryDelays[min(attempt, retryDelays.count - 1)]
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // All retries failed
        throw lastError ?? APIError.unknownError
    }

    // MARK: - Encryption

    private func encryptData(_ data: Data) throws -> (Data, UploadRequest.EncryptionMetadata?) {
        guard configuration.enableEncryption else {
            return (data, nil)
        }

        // Generate random IV
        let iv = AES.GCM.Nonce()

        // Encrypt data using AES-GCM
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey, nonce: iv)

        guard let encryptedData = sealedBox.combined else {
            throw APIError.encryptionFailed
        }

        let metadata = UploadRequest.EncryptionMetadata(
            algorithm: "AES-GCM-256",
            keyId: "app-encryption-key-v1",
            iv: Data(iv).base64EncodedString()
        )

        return (encryptedData, metadata)
    }

    /// Generates SHA-256 checksum for data integrity
    private func generateChecksum(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Key Management

    private static func loadOrGenerateEncryptionKey() -> SymmetricKey {
        let keyIdentifier = "com.health.tracker.encryption.key"

        // Try to load from keychain
        if let keyData = loadFromKeychain(identifier: keyIdentifier) {
            return SymmetricKey(data: keyData)
        }

        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        // Save to keychain
        saveToKeychain(data: keyData, identifier: keyIdentifier)

        return newKey
    }

    private static func saveToKeychain(data: Data, identifier: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemDelete(query as CFDictionary) // Delete old key if exists
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func loadFromKeychain(identifier: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return data
    }

    // MARK: - Certificate Pinning

    /// Validates server certificate (implement for production)
    private func validateCertificate(_ challenge: URLAuthenticationChallenge) -> Bool {
        guard configuration.enableCertificatePinning else {
            return true
        }

        // TODO: Implement actual certificate pinning
        // For production, validate server certificate against pinned certificates
        // Example:
        // 1. Extract server certificate from challenge
        // 2. Compare against bundled certificate hashes
        // 3. Return true only if match found

        return true
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case encryptionFailed
    case networkError(underlying: Error)
    case decodingError(underlying: Error)
    case unknownError

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode, _):
            return "HTTP error: \(statusCode)"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .unknownError:
            return "Unknown error occurred"
        }
    }
}
