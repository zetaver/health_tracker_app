# Backend Integration Implementation Guide

Step-by-step guide for integrating the iOS app with your HIPAA-compliant Azure backend.

## Table of Contents

1. [Setup and Configuration](#setup-and-configuration)
2. [Authentication Flow](#authentication-flow)
3. [SSL Certificate Pinning](#ssl-certificate-pinning)
4. [Making Secure API Calls](#making-secure-api-calls)
5. [Error Handling](#error-handling)
6. [Testing](#testing)
7. [Production Checklist](#production-checklist)

---

## Setup and Configuration

### Step 1: Configure Azure AD B2C

```swift
// In your App Delegate or main app file
import SwiftUI

@main
struct HealthTrackerApp: App {
    @StateObject private var authManager: AuthenticationManager
    @StateObject private var healthManager: HealthKitManager

    init() {
        // Configure Azure AD B2C authentication
        let authConfig = AuthenticationManager.AuthConfiguration.azureB2C(
            tenantName: "healthtracker",          // Your Azure tenant name
            policyName: "B2C_1_signupsignin"      // Your sign-in policy
        )

        let authManager = AuthenticationManager(configuration: authConfig)
        _authManager = StateObject(wrappedValue: authManager)

        // Configure HealthKit
        let healthConfig = HealthKitManager.Configuration.default(userId: "user123")
        _healthManager = StateObject(wrappedValue: HealthKitManager(configuration: healthConfig))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(healthManager)
                .task {
                    // Validate configuration on startup
                    do {
                        try SecureConfigurationManager.shared.validateConfiguration()
                    } catch {
                        print("Configuration error: \(error)")
                    }
                }
        }
    }
}
```

### Step 2: Create Configuration Files

Create `.xcconfig` files for each environment (add to `.gitignore`):

**Development.xcconfig:**
```
// Development environment
API_BASE_URL = https:/$()/dev.api.healthtracker.com
AUTH_BASE_URL = https:/$()/dev.auth.healthtracker.com
OAUTH_CLIENT_ID = dev-abc123
SSL_PINS =
SSL_BACKUP_PINS =
```

**Production.xcconfig:**
```
// Production environment - DO NOT COMMIT
API_BASE_URL = https:/$()/api.healthtracker.azure.com
AUTH_BASE_URL = https:/$()/login.healthtracker.azure.com
OAUTH_CLIENT_ID = $(PROD_CLIENT_ID)        // From Azure DevOps
SSL_PINS = $(PROD_SSL_PINS)                // From Azure DevOps
SSL_BACKUP_PINS = $(PROD_SSL_BACKUP_PINS)  // From Azure DevOps
```

### Step 3: Update Info.plist

Add to `Info.plist`:

```xml
<!-- API Configuration -->
<key>API_BASE_URL</key>
<string>$(API_BASE_URL)</string>

<key>AUTH_BASE_URL</key>
<string>$(AUTH_BASE_URL)</string>

<key>OAUTH_CLIENT_ID</key>
<string>$(OAUTH_CLIENT_ID)</string>

<!-- App Transport Security -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>api.healthtracker.azure.com</key>
        <dict>
            <key>NSExceptionRequiresForwardSecrecy</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionMinimumTLSVersion</key>
            <string>TLSv1.2</string>
        </dict>
    </dict>
</dict>
```

---

## Authentication Flow

### Login with Azure AD B2C

```swift
struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 20) {
            TextField("Email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .keyboardType(.emailAddress)

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button(action: login) {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Login")
                }
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
        }
        .padding()
    }

    private func login() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.loginWithPassword(
                    email: email,
                    password: password
                )
                // Login successful - navigate to main app
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
```

### Check Authentication Status

```swift
struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainDashboardView()
            } else {
                LoginView()
            }
        }
    }
}
```

### Logout

```swift
Button("Logout") {
    Task {
        await authManager.logout()
    }
}
```

---

## SSL Certificate Pinning

### Step 1: Extract Public Key Hash from Azure Certificate

**Option A: Using OpenSSL (Recommended)**

```bash
# Download your Azure certificate
# Go to Azure Portal → App Service → TLS/SSL settings → Download certificate

# Extract public key
openssl x509 -in azure_certificate.cer -pubkey -noout > pubkey.pem

# Generate SHA-256 hash
openssl pkey -pubin -in pubkey.pem -outform DER | \
    openssl dgst -sha256 -binary | \
    openssl enc -base64

# Output example: "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
```

**Option B: Using iOS App**

```swift
// In a debug/test environment only
let certPath = "/path/to/azure_certificate.cer"
if let pin = SSLPinningManager.generatePinFromCertificate(at: certPath) {
    print("SSL Pin: \(pin)")
}
```

### Step 2: Add Pins to Configuration

**In Production.xcconfig:**

```
SSL_PINS = 47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=
SSL_BACKUP_PINS = BackupHashHere123456789ABCDEF=,AnotherBackupHash=
```

### Step 3: Test SSL Pinning

```swift
// Test in a development/staging environment first!
func testSSLPinning() async {
    let authManager = AuthenticationManager(configuration: .default)
    let apiClient = SecureAPIClient(authenticationManager: authManager)

    do {
        // Try to fetch something from your API
        let profile: UserProfile = try await apiClient.getUserProfile(userId: "test")
        print("✅ SSL Pinning validated successfully")
    } catch {
        print("❌ SSL Pinning failed: \(error)")
    }
}
```

---

## Making Secure API Calls

### Example 1: Upload Health Data

```swift
import SwiftUI

struct HealthDataUploadView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var isUploading = false
    @State private var uploadStatus: String?

    var body: some View {
        VStack {
            Button("Upload Health Data") {
                uploadHealthData()
            }
            .disabled(isUploading)

            if let status = uploadStatus {
                Text(status)
                    .padding()
            }
        }
    }

    private func uploadHealthData() {
        isUploading = true
        uploadStatus = "Uploading..."

        Task {
            do {
                // Create API client
                let apiClient = SecureAPIClient(authenticationManager: authManager)

                // Fetch health data
                let endDate = Date()
                let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!

                let heartRateData = try await healthManager.fetchHeartRate(
                    from: startDate,
                    to: endDate
                )

                // Create batch
                let dataPoints = heartRateData.map { metric in
                    HealthDataBatch.HealthDataPoint(
                        metricType: "heartRate",
                        timestamp: metric.timestamp,
                        value: String(metric.beatsPerMinute),
                        deviceInfo: nil
                    )
                }

                let batch = HealthDataBatch(
                    userId: authManager.currentUser?.id ?? "",
                    dataPoints: dataPoints
                )

                // Upload
                let response: UploadResponse = try await apiClient.uploadHealthData(batch)

                uploadStatus = "✅ Uploaded \(dataPoints.count) data points"

            } catch {
                uploadStatus = "❌ Upload failed: \(error.localizedDescription)"
            }

            isUploading = false
        }
    }
}
```

### Example 2: Fetch User Profile

```swift
func fetchUserProfile() async throws -> UserProfile {
    let apiClient = SecureAPIClient(authenticationManager: authManager)

    let profile = try await apiClient.getUserProfile(
        userId: authManager.currentUser?.id ?? ""
    )

    return profile
}
```

### Example 3: Custom API Endpoint

```swift
extension SecureAPIClient {
    /// Custom endpoint: Get health insights
    func getHealthInsights(userId: String, startDate: Date, endDate: Date) async throws -> HealthInsights {
        let dateFormatter = ISO8601DateFormatter()

        let queryParams = [
            "startDate": dateFormatter.string(from: startDate),
            "endDate": dateFormatter.string(from: endDate)
        ]

        return try await get(
            endpoint: "/api/v1/user/\(userId)/insights",
            queryParams: queryParams
        )
    }
}

struct HealthInsights: Codable {
    let averageHeartRate: Double
    let totalSteps: Int
    let sleepQualityScore: Double
    let recommendations: [String]
}
```

---

## Error Handling

### Comprehensive Error Handling

```swift
func uploadWithErrorHandling() async {
    do {
        let apiClient = SecureAPIClient(authenticationManager: authManager)
        let response: UploadResponse = try await apiClient.uploadHealthData(healthData)

        print("Success: \(response.uploadId ?? "unknown")")

    } catch AuthenticationError.notAuthenticated {
        // User not logged in
        showLoginScreen()

    } catch AuthenticationError.tokenRefreshFailed {
        // Refresh token expired, need to re-authenticate
        await authManager.logout()
        showLoginScreen()

    } catch APIError.unauthorized {
        // Token invalid or expired
        try? await authManager.refreshAccessToken()
        // Retry upload

    } catch APIError.rateLimited {
        // Too many requests
        showAlert("Please wait before trying again")

    } catch APIError.serverError(let statusCode, _) {
        // Server error (500+)
        showAlert("Server error: \(statusCode). Please try again later.")

    } catch APIError.networkError(let underlying) {
        // Network issue
        showAlert("Network error: \(underlying.localizedDescription)")

    } catch {
        // Generic error
        showAlert("Upload failed: \(error.localizedDescription)")
    }
}
```

### Retry Logic Example

```swift
func uploadWithRetry(maxRetries: Int = 3) async throws {
    var lastError: Error?

    for attempt in 0..<maxRetries {
        do {
            let apiClient = SecureAPIClient(authenticationManager: authManager)
            let response: UploadResponse = try await apiClient.uploadHealthData(healthData)
            return  // Success!

        } catch APIError.networkError(let error) {
            lastError = error
            print("Attempt \(attempt + 1) failed, retrying...")

            // Exponential backoff
            let delay = pow(2.0, Double(attempt))
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        } catch {
            // Non-retryable error
            throw error
        }
    }

    throw lastError ?? APIError.invalidResponse
}
```

---

## Testing

### Unit Tests

```swift
import XCTest
@testable import Health_Tracker_App

class SecureAPIClientTests: XCTestCase {

    func testAuthenticationHeadersAdded() async throws {
        // Mock authentication manager
        let authManager = MockAuthenticationManager()
        authManager.mockAccessToken = "test-token-123"

        let apiClient = SecureAPIClient(authenticationManager: authManager)

        // Create request
        var request = URLRequest(url: URL(string: "https://api.test.com/test")!)

        // Add headers
        try await apiClient.addAuthenticationHeaders(to: &request)

        // Verify
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-token-123"
        )
    }

    func testSSLPinningValidation() {
        // Test with valid pin
        let validConfig = SSLPinningManager.PinConfiguration(
            pins: ["valid-hash-here"],
            backupPins: [],
            pinningMode: .publicKeyHash,
            allowExpiredCertificates: false,
            validateCertificateChain: true
        )

        let pinningManager = SSLPinningManager(configuration: validConfig)

        // Create mock server trust
        // ... (requires certificate mocking)
    }
}
```

### Integration Tests

```swift
class BackendIntegrationTests: XCTestCase {

    func testEndToEndUpload() async throws {
        // Use staging environment
        let authConfig = AuthenticationManager.AuthConfiguration.azureB2C(
            tenantName: "healthtracker-staging",
            policyName: "B2C_1_signupsignin"
        )

        let authManager = AuthenticationManager(configuration: authConfig)

        // Login with test account
        try await authManager.loginWithPassword(
            email: "test@example.com",
            password: "TestPassword123!"
        )

        // Create API client
        let apiClient = SecureAPIClient(authenticationManager: authManager)

        // Upload test data
        let testData = HealthDataBatch(
            userId: "test-user",
            dataPoints: [
                HealthDataBatch.HealthDataPoint(
                    metricType: "heartRate",
                    timestamp: Date(),
                    value: "75.0",
                    deviceInfo: nil
                )
            ]
        )

        let response: UploadResponse = try await apiClient.uploadHealthData(testData)

        // Verify
        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.uploadId)
    }
}
```

---

## Production Checklist

Before deploying to production:

### Security

- [ ] SSL certificate pinning configured with valid pins
- [ ] Backup pins configured for certificate rotation
- [ ] All secrets removed from code
- [ ] Production `.xcconfig` file gitignored
- [ ] API keys stored in Azure DevOps variable groups
- [ ] Keychain used for token storage
- [ ] Code obfuscation applied
- [ ] Request signing enabled
- [ ] Replay prevention enabled

### Authentication

- [ ] Azure AD B2C properly configured
- [ ] Token refresh working correctly
- [ ] Logout clears all sensitive data
- [ ] Session timeout configured (15-60 minutes)
- [ ] MFA enabled for production users

### API Integration

- [ ] All endpoints tested in staging
- [ ] Error handling comprehensive
- [ ] Retry logic implemented
- [ ] Rate limiting handled gracefully
- [ ] Timeout values appropriate
- [ ] Response validation working

### HIPAA Compliance

- [ ] End-to-end encryption verified
- [ ] Audit logging implemented
- [ ] User consent tracking in place
- [ ] Data deletion endpoint working
- [ ] PHI minimization implemented
- [ ] Secure data transmission verified

### Testing

- [ ] Unit tests passing
- [ ] Integration tests passing
- [ ] SSL pinning tested
- [ ] Token refresh tested
- [ ] Error scenarios tested
- [ ] Performance testing completed
- [ ] Security audit completed

### Monitoring

- [ ] Application Insights configured
- [ ] Error tracking set up
- [ ] API latency monitoring
- [ ] Authentication failures tracked
- [ ] SSL pinning failures alerted

### Documentation

- [ ] API documentation reviewed
- [ ] Security procedures documented
- [ ] Incident response plan created
- [ ] Certificate rotation process documented
- [ ] Emergency contact list updated

---

## Common Issues and Solutions

### Issue 1: SSL Pinning Failure

**Symptoms:**
```
❌ No public key hash match found
```

**Solutions:**
1. Verify pin hash is correct (re-extract from certificate)
2. Check certificate hasn't been rotated
3. Ensure backup pins are configured
4. Verify using correct certificate (not self-signed in production)

### Issue 2: Token Refresh Fails

**Symptoms:**
```
Failed to refresh access token
```

**Solutions:**
1. Check refresh token hasn't expired (30 days default)
2. Verify OAuth client configuration in Azure
3. Check network connectivity
4. Verify token endpoint URL is correct

### Issue 3: Unauthorized Errors

**Symptoms:**
```
HTTP 401 Unauthorized
```

**Solutions:**
1. Check access token is present
2. Verify token hasn't expired
3. Check Bearer token format
4. Verify user has required permissions

### Issue 4: Rate Limiting

**Symptoms:**
```
HTTP 429 Too Many Requests
```

**Solutions:**
1. Implement exponential backoff
2. Check `Retry-After` header
3. Review rate limits with backend team
4. Implement request queuing

---

## Example: Complete Integration

```swift
@MainActor
class HealthDataService: ObservableObject {
    @Published var uploadStatus: UploadStatus = .idle
    @Published var errorMessage: String?

    enum UploadStatus {
        case idle
        case uploading
        case success
        case failed
    }

    private let authManager: AuthenticationManager
    private let healthManager: HealthKitManager
    private let apiClient: SecureAPIClient

    init(authManager: AuthenticationManager, healthManager: HealthKitManager) {
        self.authManager = authManager
        self.healthManager = healthManager
        self.apiClient = SecureAPIClient(authenticationManager: authManager)
    }

    func uploadHealthData() async {
        uploadStatus = .uploading
        errorMessage = nil

        do {
            // 1. Fetch health data from HealthKit
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate)!

            async let heartRate = healthManager.fetchHeartRate(from: startDate, to: endDate)
            async let steps = healthManager.fetchSteps(from: startDate, to: endDate)
            async let sleep = healthManager.fetchSleep(from: startDate, to: endDate)

            let (heartRateData, stepsData, sleepData) = try await (heartRate, steps, sleep)

            // 2. Create batch
            var dataPoints: [HealthDataBatch.HealthDataPoint] = []

            // Add heart rate
            dataPoints += heartRateData.map { metric in
                HealthDataBatch.HealthDataPoint(
                    metricType: "heartRate",
                    timestamp: metric.timestamp,
                    value: "\(metric.beatsPerMinute)",
                    deviceInfo: nil
                )
            }

            // Add steps
            dataPoints += stepsData.map { metric in
                HealthDataBatch.HealthDataPoint(
                    metricType: "steps",
                    timestamp: metric.timestamp,
                    value: "\(metric.count)",
                    deviceInfo: nil
                )
            }

            // Add sleep
            dataPoints += sleepData.map { metric in
                HealthDataBatch.HealthDataPoint(
                    metricType: "sleep",
                    timestamp: metric.timestamp,
                    value: metric.stage.rawValue,
                    deviceInfo: nil
                )
            }

            let batch = HealthDataBatch(
                userId: authManager.currentUser?.id ?? "",
                dataPoints: dataPoints
            )

            // 3. Upload to backend
            let response: UploadResponse = try await apiClient.uploadHealthData(batch)

            // 4. Success
            uploadStatus = .success
            print("Uploaded \(dataPoints.count) data points. ID: \(response.uploadId ?? "unknown")")

        } catch {
            uploadStatus = .failed
            errorMessage = error.localizedDescription
            print("Upload failed: \(error)")
        }
    }
}
```

---

## Next Steps

1. **Configure Azure AD B2C** - Set up authentication
2. **Extract SSL pins** - Get certificate public key hashes
3. **Test in staging** - Verify all security features
4. **Review HIPAA compliance** - Ensure all requirements met
5. **Deploy to production** - Follow production checklist

For more details:
- [BACKEND_SECURITY_PLAN.md](BACKEND_SECURITY_PLAN.md) - Comprehensive security architecture
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture overview
- [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md) - HealthKit integration guide
