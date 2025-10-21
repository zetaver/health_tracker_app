//
//  AuthenticationManager.swift
//  Health Tracker App
//
//  Manages OAuth 2.0 / JWT authentication with Azure AD B2C
//  Includes automatic token refresh and secure storage
//

import Foundation
import Combine

/// Manages user authentication and JWT token lifecycle
@MainActor
class AuthenticationManager: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var currentUser: User?
    @Published private(set) var authState: AuthenticationState = .notAuthenticated

    // MARK: - Authentication State

    enum AuthenticationState {
        case notAuthenticated
        case authenticating
        case authenticated
        case refreshing
        case expired
        case error(Error)
    }

    // MARK: - Configuration

    struct AuthConfiguration {
        let authEndpoint: URL
        let tokenEndpoint: URL
        let clientID: String
        let redirectURI: String
        let scope: String

        static let `default` = AuthConfiguration(
            authEndpoint: URL(string: "https://login.healthtracker.com/oauth/authorize")!,
            tokenEndpoint: URL(string: "https://login.healthtracker.com/oauth/token")!,
            clientID: "", // Load from secure config
            redirectURI: "healthtracker://oauth/callback",
            scope: "read:health write:health offline_access"
        )

        // Azure AD B2C example
        static func azureB2C(tenantName: String, policyName: String) -> AuthConfiguration {
            let baseURL = "https://\(tenantName).b2clogin.com/\(tenantName).onmicrosoft.com/\(policyName)"

            return AuthConfiguration(
                authEndpoint: URL(string: "\(baseURL)/oauth2/v2.0/authorize")!,
                tokenEndpoint: URL(string: "\(baseURL)/oauth2/v2.0/token")!,
                clientID: "", // Set from config
                redirectURI: "msauth.com.healthtracker.app://auth",
                scope: "openid offline_access https://\(tenantName).onmicrosoft.com/api/read"
            )
        }
    }

    // MARK: - Properties

    private let configuration: AuthConfiguration
    private let keychainService: KeychainService
    private let session: URLSession

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpirationDate: Date?

    // Refresh timer
    private var refreshTimer: Timer?

    // MARK: - Initialization

    init(configuration: AuthConfiguration = .default) {
        self.configuration = configuration
        self.keychainService = KeychainService()
        self.session = URLSession.shared

        // Load stored tokens
        loadStoredTokens()
    }

    // MARK: - Authentication Methods

    /// Initiates OAuth 2.0 authorization code flow
    /// - Parameters:
    ///   - presentationContext: View controller for web authentication
    /// - Returns: Authorization result
    func login() async throws {
        authState = .authenticating

        do {
            // For Azure AD B2C or OAuth 2.0, use ASWebAuthenticationSession
            let authURL = buildAuthorizationURL()
            let callbackURL = try await presentWebAuthentication(authURL: authURL)

            // Extract authorization code from callback
            guard let code = extractAuthorizationCode(from: callbackURL) else {
                throw AuthenticationError.invalidAuthorizationCode
            }

            // Exchange code for tokens
            let tokens = try await exchangeCodeForTokens(code: code)

            // Store tokens securely
            try storeTokens(tokens)

            // Decode and validate token
            let user = try decodeAccessToken(tokens.accessToken)

            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
                self.authState = .authenticated
            }

            // Schedule token refresh
            scheduleTokenRefresh()

        } catch {
            authState = .error(error)
            throw error
        }
    }

    /// Performs password-based login (Resource Owner Password Credentials flow)
    /// Note: Less secure, use only if OAuth 2.0 flow not available
    /// - Parameters:
    ///   - email: User email
    ///   - password: User password
    func loginWithPassword(email: String, password: String) async throws {
        authState = .authenticating

        // Create request
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type": "password",
            "client_id": configuration.clientID,
            "username": email,
            "password": password,
            "scope": configuration.scope
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw AuthenticationError.loginFailed
            }

            let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)

            // Store tokens
            try storeTokens(tokens)

            // Decode user info
            let user = try decodeAccessToken(tokens.accessToken)

            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
                self.authState = .authenticated
            }

            scheduleTokenRefresh()

        } catch {
            authState = .error(error)
            throw error
        }
    }

    /// Logs out the user and clears all tokens
    func logout() async {
        // Invalidate refresh timer
        refreshTimer?.invalidate()

        // Clear tokens from memory
        accessToken = nil
        refreshToken = nil
        tokenExpirationDate = nil

        // Clear tokens from Keychain
        keychainService.delete(key: KeychainKeys.accessToken)
        keychainService.delete(key: KeychainKeys.refreshToken)
        keychainService.delete(key: KeychainKeys.tokenExpiration)

        // Update state
        await MainActor.run {
            self.currentUser = nil
            self.isAuthenticated = false
            self.authState = .notAuthenticated
        }
    }

    // MARK: - Token Management

    /// Returns current access token, refreshing if necessary
    func getAccessToken() async throws -> String {
        // Check if token exists
        guard let token = accessToken else {
            throw AuthenticationError.notAuthenticated
        }

        // Check if token is expired
        if isTokenExpired() {
            try await refreshAccessToken()
            return accessToken ?? { throw AuthenticationError.tokenRefreshFailed }()
        }

        return token
    }

    /// Manually refreshes the access token
    func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw AuthenticationError.noRefreshToken
        }

        authState = .refreshing

        // Create refresh request
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type": "refresh_token",
            "client_id": configuration.clientID,
            "refresh_token": refreshToken,
            "scope": configuration.scope
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                // Refresh token expired, need to re-authenticate
                await logout()
                throw AuthenticationError.tokenRefreshFailed
            }

            let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)

            // Store new tokens
            try storeTokens(tokens)

            authState = .authenticated

        } catch {
            authState = .error(error)
            throw error
        }
    }

    // MARK: - Token Validation

    /// Checks if current access token is expired
    private func isTokenExpired() -> Bool {
        guard let expirationDate = tokenExpirationDate else {
            return true
        }

        // Add 5 minute buffer
        let bufferDate = Date().addingTimeInterval(300)
        return bufferDate >= expirationDate
    }

    /// Schedules automatic token refresh before expiration
    private func scheduleTokenRefresh() {
        refreshTimer?.invalidate()

        guard let expirationDate = tokenExpirationDate else { return }

        // Refresh 5 minutes before expiration
        let refreshDate = expirationDate.addingTimeInterval(-300)
        let timeUntilRefresh = refreshDate.timeIntervalSinceNow

        guard timeUntilRefresh > 0 else {
            // Token already expired, refresh now
            Task {
                try? await refreshAccessToken()
            }
            return
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: timeUntilRefresh, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await self?.refreshAccessToken()
            }
        }
    }

    // MARK: - Token Storage

    private func storeTokens(_ tokens: TokenResponse) throws {
        // Store in memory
        self.accessToken = tokens.accessToken
        self.refreshToken = tokens.refreshToken

        // Calculate expiration date
        let expirationDate = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        self.tokenExpirationDate = expirationDate

        // Store in Keychain
        keychainService.save(key: KeychainKeys.accessToken, value: tokens.accessToken)

        if let refreshToken = tokens.refreshToken {
            keychainService.save(key: KeychainKeys.refreshToken, value: refreshToken)
        }

        keychainService.save(key: KeychainKeys.tokenExpiration, value: "\(expirationDate.timeIntervalSince1970)")
    }

    private func loadStoredTokens() {
        // Load from Keychain
        if let accessToken = keychainService.retrieve(key: KeychainKeys.accessToken) {
            self.accessToken = accessToken
        }

        if let refreshToken = keychainService.retrieve(key: KeychainKeys.refreshToken) {
            self.refreshToken = refreshToken
        }

        if let expirationString = keychainService.retrieve(key: KeychainKeys.tokenExpiration),
           let timestamp = TimeInterval(expirationString) {
            self.tokenExpirationDate = Date(timeIntervalSince1970: timestamp)
        }

        // Check if tokens are valid
        if accessToken != nil && !isTokenExpired() {
            // Try to decode user from token
            if let user = try? decodeAccessToken(accessToken!) {
                self.currentUser = user
                self.isAuthenticated = true
                self.authState = .authenticated
                scheduleTokenRefresh()
            }
        } else if refreshToken != nil {
            // Token expired but we have refresh token
            Task {
                try? await refreshAccessToken()
            }
        }
    }

    // MARK: - JWT Decoding

    private func decodeAccessToken(_ token: String) throws -> User {
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else {
            throw AuthenticationError.invalidToken
        }

        let payloadSegment = segments[1]
        let payloadData = try base64URLDecode(payloadSegment)

        let payload = try JSONDecoder().decode(JWTPayload.self, from: payloadData)

        return User(
            id: payload.sub,
            email: payload.email ?? "",
            name: payload.name,
            roles: payload.roles ?? []
        )
    }

    private func base64URLDecode(_ base64URL: String) throws -> Data {
        var base64 = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64) else {
            throw AuthenticationError.invalidToken
        }

        return data
    }

    // MARK: - OAuth Flow Helpers

    private func buildAuthorizationURL() -> URL {
        var components = URLComponents(url: configuration.authEndpoint, resolvingAgainstBaseURL: false)!

        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: configuration.scope),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]

        return components.url!
    }

    private func presentWebAuthentication(authURL: URL) async throws -> URL {
        // Use ASWebAuthenticationSession for OAuth flow
        // This is a placeholder - actual implementation requires ASWebAuthenticationSession
        throw AuthenticationError.notImplemented
    }

    private func extractAuthorizationCode(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "code" })?.value
    }

    private func exchangeCodeForTokens(code: String) async throws -> TokenResponse {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type": "authorization_code",
            "client_id": configuration.clientID,
            "code": code,
            "redirect_uri": configuration.redirectURI
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthenticationError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

// MARK: - Models

struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

struct JWTPayload: Codable {
    let sub: String  // Subject (user ID)
    let email: String?
    let name: String?
    let iat: Int?    // Issued at
    let exp: Int     // Expiration
    let roles: [String]?
    let scope: String?

    // Azure AD B2C specific
    let oid: String?  // Object ID
    let tfp: String?  // Trust Framework Policy
}

struct User: Codable {
    let id: String
    let email: String
    let name: String?
    let roles: [String]
}

// MARK: - Keychain Keys

private enum KeychainKeys {
    static let accessToken = "auth.access_token"
    static let refreshToken = "auth.refresh_token"
    static let tokenExpiration = "auth.token_expiration"
}

// MARK: - Errors

enum AuthenticationError: LocalizedError {
    case notAuthenticated
    case loginFailed
    case invalidAuthorizationCode
    case tokenExchangeFailed
    case tokenRefreshFailed
    case noRefreshToken
    case invalidToken
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .loginFailed:
            return "Login failed. Please check your credentials."
        case .invalidAuthorizationCode:
            return "Invalid authorization code received"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for tokens"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .noRefreshToken:
            return "No refresh token available"
        case .invalidToken:
            return "Invalid JWT token format"
        case .notImplemented:
            return "Feature not yet implemented"
        }
    }
}

// MARK: - Keychain Service

class KeychainService {
    func save(key: String, value: String) {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
