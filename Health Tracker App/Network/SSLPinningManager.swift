//
//  SSLPinningManager.swift
//  Health Tracker App
//
//  Implements SSL certificate/public key pinning for secure communication
//  Prevents man-in-the-middle attacks
//

import Foundation
import Security
import CryptoKit

/// Manages SSL certificate and public key pinning
class SSLPinningManager: NSObject {

    // MARK: - Pin Configuration

    struct PinConfiguration {
        let pins: [String]              // SHA-256 hashes of public keys
        let backupPins: [String]        // Backup pins for rotation
        let pinningMode: PinningMode
        let allowExpiredCertificates: Bool  // For development only
        let validateCertificateChain: Bool

        enum PinningMode {
            case certificate        // Pin entire certificate
            case publicKey         // Pin public key (recommended)
            case publicKeyHash     // Pin SHA-256 hash of public key
        }

        /// Production configuration for Azure API
        static func azure(primaryHash: String, backupHashes: [String]) -> PinConfiguration {
            return PinConfiguration(
                pins: [primaryHash],
                backupPins: backupHashes,
                pinningMode: .publicKeyHash,
                allowExpiredCertificates: false,
                validateCertificateChain: true
            )
        }

        /// Development configuration (less strict)
        static let development = PinConfiguration(
            pins: [],
            backupPins: [],
            pinningMode: .publicKeyHash,
            allowExpiredCertificates: true,  // Allow self-signed certs
            validateCertificateChain: false
        )
    }

    // MARK: - Properties

    private let configuration: PinConfiguration
    private var validationCache: [String: Bool] = [:]  // Cache validation results

    // MARK: - Initialization

    init(configuration: PinConfiguration) {
        self.configuration = configuration
        super.init()
    }

    // MARK: - URLSession Delegate

    /// Handles authentication challenges for SSL pinning
    /// Use this method in your URLSessionDelegate
    func handleAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only handle server trust challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Validate the server trust
        let isValid = validateServerTrust(serverTrust, forHost: challenge.protectionSpace.host)

        if isValid {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Validation

    /// Validates server trust against pinned certificates/keys
    /// - Parameters:
    ///   - serverTrust: The server trust to validate
    ///   - host: The host being connected to
    /// - Returns: True if validation successful
    func validateServerTrust(_ serverTrust: SecTrust, forHost host: String) -> Bool {
        // Check cache first
        let cacheKey = "\(host)-\(serverTrust.hashValue)"
        if let cachedResult = validationCache[cacheKey] {
            return cachedResult
        }

        var result = false

        // Step 1: Perform standard validation if enabled
        if configuration.validateCertificateChain {
            result = performStandardValidation(serverTrust)
            guard result else {
                validationCache[cacheKey] = false
                return false
            }
        }

        // Step 2: Perform pin validation
        switch configuration.pinningMode {
        case .certificate:
            result = validateCertificatePin(serverTrust)
        case .publicKey:
            result = validatePublicKeyPin(serverTrust)
        case .publicKeyHash:
            result = validatePublicKeyHashPin(serverTrust)
        }

        // Cache result
        validationCache[cacheKey] = result

        return result
    }

    // MARK: - Standard Validation

    private func performStandardValidation(_ serverTrust: SecTrust) -> Bool {
        // Set SSL policy
        let policy = SecPolicyCreateSSL(true, nil)
        SecTrustSetPolicies(serverTrust, policy)

        // Evaluate trust
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)

        if let error = error {
            print("❌ SSL Validation Error: \(error)")
        }

        // Allow expired certificates in development
        if configuration.allowExpiredCertificates && !isValid {
            print("⚠️ Allowing expired certificate (development mode)")
            return true
        }

        return isValid
    }

    // MARK: - Certificate Pinning

    private func validateCertificatePin(_ serverTrust: SecTrust) -> Bool {
        // Get server certificates
        guard let certificates = extractCertificates(from: serverTrust) else {
            return false
        }

        // Compare each certificate against pins
        for certificate in certificates {
            let certificateData = SecCertificateCopyData(certificate) as Data
            let certificateHash = sha256(data: certificateData)

            if configuration.pins.contains(certificateHash) ||
               configuration.backupPins.contains(certificateHash) {
                print("✅ Certificate pin matched")
                return true
            }
        }

        print("❌ No certificate pin match found")
        return false
    }

    // MARK: - Public Key Pinning

    private func validatePublicKeyPin(_ serverTrust: SecTrust) -> Bool {
        // Get server certificates
        guard let certificates = extractCertificates(from: serverTrust) else {
            return false
        }

        // Extract public keys from certificates
        for certificate in certificates {
            guard let publicKey = extractPublicKey(from: certificate) else {
                continue
            }

            let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data

            // Compare against pins
            for pin in configuration.pins + configuration.backupPins {
                if let pinData = Data(base64Encoded: pin), pinData == publicKeyData {
                    print("✅ Public key pin matched")
                    return true
                }
            }
        }

        print("❌ No public key pin match found")
        return false
    }

    // MARK: - Public Key Hash Pinning (Recommended)

    private func validatePublicKeyHashPin(_ serverTrust: SecTrust) -> Bool {
        // Get server certificates
        guard let certificates = extractCertificates(from: serverTrust) else {
            return false
        }

        // Extract and hash public keys
        for certificate in certificates {
            guard let publicKey = extractPublicKey(from: certificate) else {
                continue
            }

            let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data
            let publicKeyHash = sha256(data: publicKeyData)

            print("🔍 Checking public key hash: \(publicKeyHash)")

            // Compare against pins
            if configuration.pins.contains(publicKeyHash) {
                print("✅ Primary public key hash matched")
                return true
            }

            if configuration.backupPins.contains(publicKeyHash) {
                print("✅ Backup public key hash matched")
                return true
            }
        }

        print("❌ No public key hash match found")
        print("Available pins: \(configuration.pins + configuration.backupPins)")
        return false
    }

    // MARK: - Helper Methods

    private func extractCertificates(from serverTrust: SecTrust) -> [SecCertificate]? {
        var certificates: [SecCertificate] = []

        // Get certificate count
        let count = SecTrustGetCertificateCount(serverTrust)
        guard count > 0 else { return nil }

        // Extract all certificates in chain
        for i in 0..<count {
            if let certificate = SecTrustGetCertificateAtIndex(serverTrust, i) {
                certificates.append(certificate)
            }
        }

        return certificates.isEmpty ? nil : certificates
    }

    private func extractPublicKey(from certificate: SecCertificate) -> SecKey? {
        // Create policy
        let policy = SecPolicyCreateBasicX509()

        // Create trust
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, policy, &trust)

        guard status == errSecSuccess, let trust = trust else {
            return nil
        }

        // Evaluate trust
        var error: CFError?
        SecTrustEvaluateWithError(trust, &error)

        // Extract public key
        return SecTrustCopyKey(trust)
    }

    private func sha256(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Pin Generation Utilities

    /// Utility to generate pin from certificate file
    /// Use this during development to generate pins
    static func generatePinFromCertificate(at path: String) -> String? {
        guard let certificateData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("❌ Failed to load certificate from path: \(path)")
            return nil
        }

        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            print("❌ Failed to create certificate from data")
            return nil
        }

        let manager = SSLPinningManager(configuration: .development)
        guard let publicKey = manager.extractPublicKey(from: certificate) else {
            print("❌ Failed to extract public key")
            return nil
        }

        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            print("❌ Failed to get public key data")
            return nil
        }

        let hash = manager.sha256(data: publicKeyData)
        print("✅ Generated pin: \(hash)")
        return hash
    }

    /// Generates pin from a PEM-encoded certificate string
    static func generatePinFromPEM(_ pemString: String) -> String? {
        // Remove header and footer
        let base64String = pemString
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        guard let certificateData = Data(base64Encoded: base64String) else {
            print("❌ Failed to decode PEM certificate")
            return nil
        }

        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            print("❌ Failed to create certificate from PEM data")
            return nil
        }

        let manager = SSLPinningManager(configuration: .development)
        guard let publicKey = manager.extractPublicKey(from: certificate) else {
            print("❌ Failed to extract public key from PEM")
            return nil
        }

        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            print("❌ Failed to get public key data from PEM")
            return nil
        }

        let hash = manager.sha256(data: publicKeyData)
        print("✅ Generated pin from PEM: \(hash)")
        return hash
    }
}

// MARK: - URLSessionDelegate Extension

/// Extension to easily integrate SSL pinning with URLSession
class PinnedURLSessionDelegate: NSObject, URLSessionDelegate {

    private let pinningManager: SSLPinningManager

    init(pinningManager: SSLPinningManager) {
        self.pinningManager = pinningManager
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        pinningManager.handleAuthenticationChallenge(challenge, completionHandler: completionHandler)
    }
}

// MARK: - Pin Configuration Examples

extension SSLPinningManager.PinConfiguration {

    /// Example Azure production configuration
    static let azureProduction = SSLPinningManager.PinConfiguration(
        pins: [
            // Replace with your actual Azure certificate public key hash
            "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
        ],
        backupPins: [
            // Backup pin for certificate rotation
            "backup-hash-here"
        ],
        pinningMode: .publicKeyHash,
        allowExpiredCertificates: false,
        validateCertificateChain: true
    )

    /// Example for development/staging
    static let azureDevelopment = SSLPinningManager.PinConfiguration(
        pins: [
            "dev-primary-hash"
        ],
        backupPins: [],
        pinningMode: .publicKeyHash,
        allowExpiredCertificates: true,
        validateCertificateChain: false
    )
}

// MARK: - Pin Extraction Guide

/*
 HOW TO EXTRACT PUBLIC KEY HASH FROM AZURE CERTIFICATE:

 1. Download your Azure certificate:
    - Go to Azure Portal
    - Navigate to your App Service or API Management
    - Go to TLS/SSL settings
    - Download the certificate (.cer or .crt file)

 2. Extract public key using OpenSSL:
    ```bash
    # Extract public key
    openssl x509 -in certificate.crt -pubkey -noout > pubkey.pem

    # Generate SHA-256 hash
    openssl pkey -pubin -in pubkey.pem -outform DER | openssl dgst -sha256 -binary | openssl enc -base64
    ```

 3. Alternative: Use the iOS app to generate hash
    ```swift
    let pin = SSLPinningManager.generatePinFromCertificate(at: "/path/to/cert.cer")
    print("Pin: \(pin ?? "failed")")
    ```

 4. Add the hash to your configuration:
    ```swift
    static let production = SSLPinningManager.PinConfiguration(
        pins: ["YOUR_HASH_HERE"],
        backupPins: ["BACKUP_HASH_HERE"],
        pinningMode: .publicKeyHash,
        allowExpiredCertificates: false,
        validateCertificateChain: true
    )
    ```

 IMPORTANT: Always include backup pins for certificate rotation!
 */
