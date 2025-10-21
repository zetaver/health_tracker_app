//
//  SecureAPIClient.swift
//  Health Tracker App
//
//  Enhanced API client with authentication, SSL pinning, and encryption
//  Integrates all security layers for HIPAA-compliant communication
//

import Foundation
import CryptoKit

/// Secure API client with comprehensive security features
actor SecureAPIClient {

    // MARK: - Dependencies

    private let authenticationManager: AuthenticationManager
    private let sslPinningManager: SSLPinningManager
    private let configurationManager: SecureConfigurationManager
    private let session: URLSession
    private let encryptionKey: SymmetricKey

    // MARK: - Configuration

    struct APIConfiguration {
        let enableEncryption: Bool
        let enableRequestSigning: Bool
        let enableReplayPrevention: Bool
        let maxRetries: Int
        let retryDelay: TimeInterval

        static let `default` = APIConfiguration(
            enableEncryption: true,
            enableRequestSigning: true,
            enableReplayPrevention: true,
            maxRetries: 3,
            retryDelay: 2.0
        )
    }

    private let configuration: APIConfiguration

    // Replay prevention
    private var usedNonces: Set<String> = []

    // Device information
    private let deviceID: String

    // MARK: - Initialization

    init(
        authenticationManager: AuthenticationManager,
        configuration: APIConfiguration = .default
    ) {
        self.authenticationManager = authenticationManager
        self.configuration = configuration
        self.configurationManager = SecureConfigurationManager.shared
        self.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        // Set up SSL pinning
        let pinConfig: SSLPinningManager.PinConfiguration
        if configurationManager.enableSSLPinning {
            pinConfig = SSLPinningManager.PinConfiguration(
                pins: configurationManager.sslPins,
                backupPins: configurationManager.sslBackupPins,
                pinningMode: .publicKeyHash,
                allowExpiredCertificates: false,
                validateCertificateChain: true
            )
        } else {
            pinConfig = .development
        }
        self.sslPinningManager = SSLPinningManager(configuration: pinConfig)

        // Create URLSession with SSL pinning delegate
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configurationManager.apiTimeout
        sessionConfig.timeoutIntervalForResource = configurationManager.apiTimeout * 2
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfig.urlCache = nil  // No caching for sensitive health data

        let delegate = PinnedURLSessionDelegate(pinningManager: sslPinningManager)
        self.session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)

        // Load or generate encryption key
        self.encryptionKey = Self.loadOrGenerateEncryptionKey()
    }

    // MARK: - Public API Methods

    /// Uploads health data batch with full security
    func uploadHealthData<T: Encodable>(_ data: T) async throws -> UploadResponse {
        let endpoint = "/api/v1/health/upload"
        return try await post(endpoint: endpoint, body: data)
    }

    /// Gets user profile
    func getUserProfile(userId: String) async throws -> UserProfile {
        let endpoint = "/api/v1/user/\(userId)/profile"
        return try await get(endpoint: endpoint)
    }

    /// Deletes user data (HIPAA requirement)
    func deleteUserData(userId: String) async throws {
        let endpoint = "/api/v1/user/\(userId)/data"
        let _: EmptyResponse = try await delete(endpoint: endpoint)
    }

    // MARK: - HTTP Methods

    func get<T: Decodable>(endpoint: String, queryParams: [String: String]? = nil) async throws -> T {
        var urlComponents = URLComponents(string: configurationManager.apiBaseURL + endpoint)!

        if let queryParams = queryParams {
            urlComponents.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        try await addAuthenticationHeaders(to: &request)
        try await addSecurityHeaders(to: &request, body: nil)

        return try await sendRequest(request: request, retryCount: 0)
    }

    func post<T: Encodable, R: Decodable>(endpoint: String, body: T) async throws -> R {
        let url = URL(string: configurationManager.apiBaseURL + endpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Encode body
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bodyData = try encoder.encode(body)

        // Encrypt if enabled
        let (finalBodyData, encryptionMetadata) = try encryptIfEnabled(bodyData)
        request.httpBody = finalBodyData

        try await addAuthenticationHeaders(to: &request)
        try await addSecurityHeaders(to: &request, body: bodyData)

        // Add encryption metadata if present
        if let metadata = encryptionMetadata {
            request.setValue(metadata.algorithm, forHTTPHeaderField: "X-Encryption-Algorithm")
            request.setValue(metadata.keyId, forHTTPHeaderField: "X-Encryption-KeyId")
            request.setValue(metadata.iv, forHTTPHeaderField: "X-Encryption-IV")
        }

        return try await sendRequest(request: request, retryCount: 0)
    }

    func delete<T: Decodable>(endpoint: String) async throws -> T {
        let url = URL(string: configurationManager.apiBaseURL + endpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        try await addAuthenticationHeaders(to: &request)
        try await addSecurityHeaders(to: &request, body: nil)

        return try await sendRequest(request: request, retryCount: 0)
    }

    // MARK: - Request Building

    private func addAuthenticationHeaders(to request: inout URLRequest) async throws {
        // Get access token (will refresh if needed)
        let accessToken = try await authenticationManager.getAccessToken()

        // Add Bearer token
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    private func addSecurityHeaders(to request: inout URLRequest, body: Data?) async throws {
        // Standard headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-App-ID")
        request.setValue(getAppVersion(), forHTTPHeaderField: "X-App-Version")
        request.setValue("iOS", forHTTPHeaderField: "X-Platform")

        // Request ID for tracing
        let requestID = UUID().uuidString
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")

        // Timestamp for replay prevention
        let timestamp = Date().timeIntervalSince1970
        request.setValue("\(Int(timestamp))", forHTTPHeaderField: "X-Timestamp")

        // Nonce for replay prevention
        if configuration.enableReplayPrevention {
            let nonce = UUID().uuidString
            request.setValue(nonce, forHTTPHeaderField: "X-Nonce")
            usedNonces.insert(nonce)
        }

        // Request signature
        if configuration.enableRequestSigning, let signature = try? signRequest(request, body: body) {
            request.setValue(signature, forHTTPHeaderField: "X-Signature")
        }
    }

    // MARK: - Request Signing

    private func signRequest(_ request: URLRequest, body: Data?) throws -> String {
        // Create signature payload
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? ""
        let timestamp = request.value(forHTTPHeaderField: "X-Timestamp") ?? ""

        var signatureData = "\(method)\n\(url)\n\(timestamp)".data(using: .utf8)!

        if let body = body {
            signatureData.append(body)
        }

        // Sign using HMAC-SHA256
        let key = SymmetricKey(data: encryptionKey.withUnsafeBytes { Data($0) })
        let signature = HMAC<SHA256>.authenticationCode(for: signatureData, using: key)

        return Data(signature).base64EncodedString()
    }

    // MARK: - Encryption

    private func encryptIfEnabled(_ data: Data) throws -> (Data, EncryptionMetadata?) {
        guard configuration.enableEncryption else {
            return (data, nil)
        }

        // Generate random IV
        let nonce = AES.GCM.Nonce()

        // Encrypt using AES-GCM
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey, nonce: nonce)

        guard let encryptedData = sealedBox.combined else {
            throw APIError.encryptionFailed
        }

        let metadata = EncryptionMetadata(
            algorithm: "AES-GCM-256",
            keyId: "app-encryption-key-v1",
            iv: Data(nonce).base64EncodedString()
        )

        return (encryptedData, metadata)
    }

    private func decryptIfNeeded(_ data: Data, metadata: EncryptionMetadata?) throws -> Data {
        guard let metadata = metadata, configuration.enableEncryption else {
            return data
        }

        // Decrypt using AES-GCM
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)

        return decryptedData
    }

    // MARK: - Request Execution

    private func sendRequest<T: Decodable>(request: URLRequest, retryCount: Int) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)

            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            // Log response for debugging
            if configurationManager.enableLogging {
                logResponse(httpResponse, data: data)
            }

            // Handle different status codes
            switch httpResponse.statusCode {
            case 200...299:
                // Success - decode response
                return try decodeResponse(data: data, response: httpResponse)

            case 401:
                // Unauthorized - token might be expired
                if retryCount == 0 {
                    // Try refreshing token
                    try await authenticationManager.refreshAccessToken()
                    // Retry request with new token
                    var newRequest = request
                    try await addAuthenticationHeaders(to: &newRequest)
                    return try await sendRequest(request: newRequest, retryCount: retryCount + 1)
                } else {
                    throw APIError.unauthorized
                }

            case 429:
                // Rate limited
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                let delay = retryAfter.flatMap(TimeInterval.init) ?? configuration.retryDelay
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                if retryCount < configuration.maxRetries {
                    return try await sendRequest(request: request, retryCount: retryCount + 1)
                } else {
                    throw APIError.rateLimited
                }

            case 500...599:
                // Server error - retry with exponential backoff
                if retryCount < configuration.maxRetries {
                    let delay = configuration.retryDelay * pow(2.0, Double(retryCount))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await sendRequest(request: request, retryCount: retryCount + 1)
                } else {
                    throw APIError.serverError(statusCode: httpResponse.statusCode, data: data)
                }

            default:
                throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
            }

        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(underlying: error)
        }
    }

    private func decodeResponse<T: Decodable>(data: Data, response: HTTPURLResponse) throws -> T {
        // Check for encryption metadata in response
        let encryptionMetadata: EncryptionMetadata?
        if let algorithm = response.value(forHTTPHeaderField: "X-Encryption-Algorithm"),
           let keyId = response.value(forHTTPHeaderField: "X-Encryption-KeyId"),
           let iv = response.value(forHTTPHeaderField: "X-Encryption-IV") {
            encryptionMetadata = EncryptionMetadata(algorithm: algorithm, keyId: keyId, iv: iv)
        } else {
            encryptionMetadata = nil
        }

        // Decrypt if needed
        let decryptedData = try decryptIfNeeded(data, metadata: encryptionMetadata)

        // Decode JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(T.self, from: decryptedData)
        } catch {
            throw APIError.decodingError(underlying: error)
        }
    }

    // MARK: - Logging

    private func logResponse(_ response: HTTPURLResponse, data: Data) {
        print("📡 API Response")
        print("Status: \(response.statusCode)")
        print("URL: \(response.url?.absoluteString ?? "unknown")")

        if let jsonString = String(data: data, encoding: .utf8) {
            print("Body: \(jsonString.prefix(200))...")  // First 200 chars
        }
    }

    // MARK: - Utilities

    private func getAppVersion() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Key Management

    private static func loadOrGenerateEncryptionKey() -> SymmetricKey {
        let keyIdentifier = "com.health.tracker.encryption.key"
        let keychainService = KeychainService()

        // Try to load from keychain
        if let keyData = keychainService.retrieve(key: keyIdentifier),
           let data = Data(base64Encoded: keyData) {
            return SymmetricKey(data: data)
        }

        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        // Save to keychain (base64 encoded)
        keychainService.save(key: keyIdentifier, value: keyData.base64EncodedString())

        return newKey
    }
}

// MARK: - Supporting Models

struct EncryptionMetadata {
    let algorithm: String
    let keyId: String
    let iv: String
}

struct UploadResponse: Codable {
    let success: Bool
    let uploadId: String?
    let timestamp: Date
    let message: String?
}

struct UserProfile: Codable {
    let userId: String
    let email: String
    let name: String?
    let createdAt: Date
}

struct EmptyResponse: Codable {
    // Empty response for DELETE requests
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(statusCode: Int, data: Data?)
    case httpError(statusCode: Int, data: Data?)
    case networkError(underlying: Error)
    case decodingError(underlying: Error)
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "Unauthorized - please log in again"
        case .rateLimited:
            return "Too many requests - please try again later"
        case .serverError(let statusCode, _):
            return "Server error (\(statusCode))"
        case .httpError(let statusCode, _):
            return "HTTP error (\(statusCode))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encryptionFailed:
            return "Encryption failed"
        }
    }
}

// MARK: - Usage Example

/*
 // Initialize the secure API client

 let authManager = AuthenticationManager(
     configuration: .azureB2C(tenantName: "healthtracker", policyName: "B2C_1_signupsignin")
 )

 let apiClient = SecureAPIClient(
     authenticationManager: authManager,
     configuration: .default
 )

 // Upload health data
 let healthData = HealthDataBatch(userId: "user123", dataPoints: [...])

 do {
     let response = try await apiClient.uploadHealthData(healthData)
     print("Upload successful: \(response.uploadId ?? "unknown")")
 } catch {
     print("Upload failed: \(error)")
 }

 // Get user profile
 do {
     let profile = try await apiClient.getUserProfile(userId: "user123")
     print("User: \(profile.name ?? profile.email)")
 } catch {
     print("Failed to fetch profile: \(error)")
 }
 */
