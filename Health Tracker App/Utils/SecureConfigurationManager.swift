//
//  SecureConfigurationManager.swift
//  Health Tracker App
//
//  Manages app configuration and secrets securely
//  NO secrets should be hardcoded - use environment, Keychain, or remote config
//

import Foundation

/// Centralized configuration management with security best practices
class SecureConfigurationManager {

    // MARK: - Singleton

    static let shared = SecureConfigurationManager()

    private init() {
        loadConfiguration()
    }

    // MARK: - Environment

    enum Environment {
        case development
        case staging
        case production

        var name: String {
            switch self {
            case .development: return "Development"
            case .staging: return "Staging"
            case .production: return "Production"
            }
        }
    }

    // Current environment (set based on build configuration)
    private(set) var currentEnvironment: Environment = {
        #if DEBUG
        return .development
        #elseif STAGING
        return .staging
        #else
        return .production
        #endif
    }()

    // MARK: - Configuration Properties

    private var configuration: AppConfiguration!

    struct AppConfiguration {
        let apiBaseURL: String
        let authBaseURL: String
        let clientID: String
        let sslPins: [String]
        let sslBackupPins: [String]
        let enableSSLPinning: Bool
        let enableLogging: Bool
        let apiTimeout: TimeInterval
    }

    // MARK: - Public API

    var apiBaseURL: String {
        return configuration.apiBaseURL
    }

    var authBaseURL: String {
        return configuration.authBaseURL
    }

    var clientID: String {
        return configuration.clientID
    }

    var sslPins: [String] {
        return configuration.sslPins
    }

    var sslBackupPins: [String] {
        return configuration.sslBackupPins
    }

    var enableSSLPinning: Bool {
        return configuration.enableSSLPinning
    }

    var enableLogging: Bool {
        return configuration.enableLogging
    }

    var apiTimeout: TimeInterval {
        return configuration.apiTimeout
    }

    // MARK: - Configuration Loading

    private func loadConfiguration() {
        switch currentEnvironment {
        case .development:
            configuration = loadDevelopmentConfig()
        case .staging:
            configuration = loadStagingConfig()
        case .production:
            configuration = loadProductionConfig()
        }

        print("📱 Environment: \(currentEnvironment.name)")
        print("🌐 API Base URL: \(configuration.apiBaseURL)")
    }

    // MARK: - Environment Configurations

    private func loadDevelopmentConfig() -> AppConfiguration {
        return AppConfiguration(
            apiBaseURL: getConfigValue(key: "API_BASE_URL") ?? "https://dev.api.healthtracker.com",
            authBaseURL: getConfigValue(key: "AUTH_BASE_URL") ?? "https://dev.auth.healthtracker.com",
            clientID: getConfigValue(key: "OAUTH_CLIENT_ID") ?? "dev-client-id",
            sslPins: [],  // No pinning in development
            sslBackupPins: [],
            enableSSLPinning: false,
            enableLogging: true,
            apiTimeout: 30
        )
    }

    private func loadStagingConfig() -> AppConfiguration {
        return AppConfiguration(
            apiBaseURL: getConfigValue(key: "API_BASE_URL") ?? "https://staging.api.healthtracker.com",
            authBaseURL: getConfigValue(key: "AUTH_BASE_URL") ?? "https://staging.auth.healthtracker.com",
            clientID: getConfigValue(key: "OAUTH_CLIENT_ID") ?? "staging-client-id",
            sslPins: getSSLPins(key: "SSL_PINS") ?? [],
            sslBackupPins: getSSLPins(key: "SSL_BACKUP_PINS") ?? [],
            enableSSLPinning: true,
            enableLogging: true,
            apiTimeout: 30
        )
    }

    private func loadProductionConfig() -> AppConfiguration {
        return AppConfiguration(
            apiBaseURL: getConfigValue(key: "API_BASE_URL") ?? "https://api.healthtracker.azure.com",
            authBaseURL: getConfigValue(key: "AUTH_BASE_URL") ?? "https://login.healthtracker.azure.com",
            clientID: getConfigValue(key: "OAUTH_CLIENT_ID") ?? "",
            sslPins: getSSLPins(key: "SSL_PINS") ?? [],
            sslBackupPins: getSSLPins(key: "SSL_BACKUP_PINS") ?? [],
            enableSSLPinning: true,
            enableLogging: false,
            apiTimeout: 30
        )
    }

    // MARK: - Configuration Sources

    /// Gets configuration value from multiple sources (priority order):
    /// 1. Environment variables (for CI/CD)
    /// 2. Info.plist
    /// 3. xcconfig files
    /// 4. Remote configuration (future)
    private func getConfigValue(key: String) -> String? {
        // 1. Check environment variables (ProcessInfo)
        if let envValue = ProcessInfo.processInfo.environment[key] {
            return envValue
        }

        // 2. Check Info.plist
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            return plistValue
        }

        // 3. Check Keychain (for sensitive values)
        if let keychainValue = KeychainService().retrieve(key: "config.\(key)") {
            return keychainValue
        }

        return nil
    }

    private func getSSLPins(key: String) -> [String]? {
        if let pinsString = getConfigValue(key: key) {
            return pinsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    // MARK: - Secure Value Storage

    /// Stores a sensitive configuration value in Keychain
    /// Use this for values that shouldn't be in Info.plist
    func storeSecureValue(key: String, value: String) {
        KeychainService().save(key: "config.\(key)", value: value)
    }

    /// Retrieves a sensitive configuration value from Keychain
    func getSecureValue(key: String) -> String? {
        return KeychainService().retrieve(key: "config.\(key)")
    }

    // MARK: - Remote Configuration (Future)

    /// Fetches configuration from remote source (e.g., Azure App Configuration)
    /// Use this for dynamic configuration updates without app updates
    func fetchRemoteConfiguration() async throws {
        // TODO: Implement Azure App Configuration integration
        // This would allow updating SSL pins, API endpoints, etc. remotely
    }

    // MARK: - Validation

    /// Validates that all required configuration is present
    func validateConfiguration() throws {
        guard !configuration.apiBaseURL.isEmpty else {
            throw ConfigurationError.missingAPIBaseURL
        }

        guard !configuration.clientID.isEmpty else {
            throw ConfigurationError.missingClientID
        }

        if currentEnvironment == .production {
            guard configuration.enableSSLPinning else {
                throw ConfigurationError.sslPinningDisabledInProduction
            }

            guard !configuration.sslPins.isEmpty else {
                throw ConfigurationError.missingSSLPins
            }
        }
    }
}

// MARK: - Configuration Errors

enum ConfigurationError: LocalizedError {
    case missingAPIBaseURL
    case missingClientID
    case missingSSLPins
    case sslPinningDisabledInProduction
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .missingAPIBaseURL:
            return "API Base URL is not configured"
        case .missingClientID:
            return "OAuth Client ID is not configured"
        case .missingSSLPins:
            return "SSL pins are required for production"
        case .sslPinningDisabledInProduction:
            return "SSL pinning must be enabled in production"
        case .invalidConfiguration:
            return "Invalid configuration detected"
        }
    }
}

// MARK: - xcconfig File Examples

/*
 Create separate .xcconfig files for each environment:

 ====== Development.xcconfig ======
 API_BASE_URL = https:/$()/dev.api.healthtracker.com
 AUTH_BASE_URL = https:/$()/dev.auth.healthtracker.com
 OAUTH_CLIENT_ID = dev-client-id-12345
 SSL_PINS =
 SSL_BACKUP_PINS =

 ====== Staging.xcconfig ======
 API_BASE_URL = https:/$()/staging.api.healthtracker.com
 AUTH_BASE_URL = https:/$()/staging.auth.healthtracker.com
 OAUTH_CLIENT_ID = staging-client-id-67890
 SSL_PINS = pin1hash,pin2hash
 SSL_BACKUP_PINS = backup1hash,backup2hash

 ====== Production.xcconfig ======
 API_BASE_URL = https:/$()/api.healthtracker.azure.com
 AUTH_BASE_URL = https:/$()/login.healthtracker.azure.com
 OAUTH_CLIENT_ID = $(OAUTH_CLIENT_ID_PROD)  # Set in Azure DevOps
 SSL_PINS = $(SSL_PINS_PROD)                # Set in Azure DevOps
 SSL_BACKUP_PINS = $(SSL_BACKUP_PINS_PROD)  # Set in Azure DevOps

 In Xcode:
 1. Go to Project Settings
 2. Select each Configuration (Debug, Staging, Release)
 3. Set the corresponding .xcconfig file

 Then add to Info.plist:
 <key>API_BASE_URL</key>
 <string>$(API_BASE_URL)</string>
 <key>AUTH_BASE_URL</key>
 <string>$(AUTH_BASE_URL)</string>
 <key>OAUTH_CLIENT_ID</key>
 <string>$(OAUTH_CLIENT_ID)</string>
 */

// MARK: - .gitignore

/*
 Add to your .gitignore:

 # Xcode configuration files with secrets
 Production.xcconfig
 Secrets.xcconfig

 # Environment-specific configs
 *-Secrets.xcconfig

 # Never commit
 *.mobileprovision
 *.p12
 *.cer
 *.certSigningRequest
 */

// MARK: - Azure DevOps Pipeline Example

/*
 # azure-pipelines.yml

 variables:
   - group: health-tracker-prod-secrets  # Variable group in Azure DevOps

 steps:
   - task: Bash@3
     displayName: 'Create Production Config'
     inputs:
       targetType: 'inline'
       script: |
         cat > Production.xcconfig << EOF
         API_BASE_URL = $(PROD_API_BASE_URL)
         AUTH_BASE_URL = $(PROD_AUTH_BASE_URL)
         OAUTH_CLIENT_ID = $(PROD_OAUTH_CLIENT_ID)
         SSL_PINS = $(PROD_SSL_PINS)
         SSL_BACKUP_PINS = $(PROD_SSL_BACKUP_PINS)
         EOF

   - task: Xcode@5
     displayName: 'Build iOS App'
     inputs:
       actions: 'build'
       configuration: 'Release'
       sdk: 'iphoneos'
       xcodeVersion: 'default'
 */

// MARK: - Usage Example

/*
 // In your app initialization:

 func application(_ application: UIApplication,
                  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

     // Validate configuration
     do {
         try SecureConfigurationManager.shared.validateConfiguration()
     } catch {
         fatalError("Invalid configuration: \(error)")
     }

     // Use configuration
     let config = SecureConfigurationManager.shared
     print("API URL: \(config.apiBaseURL)")
     print("SSL Pinning Enabled: \(config.enableSSLPinning)")

     return true
 }
 */
