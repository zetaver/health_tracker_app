# Testing and Validation Plan

Comprehensive testing strategy for HealthKit integration, data security, and HIPAA compliance.

## Table of Contents

1. [Testing Strategy Overview](#testing-strategy-overview)
2. [Unit Testing](#unit-testing)
3. [Integration Testing](#integration-testing)
4. [Security Testing](#security-testing)
5. [HIPAA Compliance Testing](#hipaa-compliance-testing)
6. [Performance Testing](#performance-testing)
7. [Background Testing](#background-testing)
8. [App Store Submission](#app-store-submission)

---

## Testing Strategy Overview

### Testing Pyramid

```
                    ┌─────────────────┐
                    │  E2E Tests      │  10%
                    │  (Manual)       │
                ┌───┴─────────────────┴───┐
                │  Integration Tests      │  20%
                │  (XCTest)               │
            ┌───┴─────────────────────────┴───┐
            │  Unit Tests                     │  70%
            │  (XCTest, Quick/Nimble)         │
        ┌───┴─────────────────────────────────┴───┐
```

### Test Coverage Goals

| Component | Target Coverage | Priority |
|-----------|----------------|----------|
| **HealthKitManager** | 90% | Critical |
| **HealthKitDataFetcher** | 85% | Critical |
| **AuthenticationManager** | 90% | Critical |
| **SSLPinningManager** | 95% | Critical |
| **HealthDataPreprocessor** | 85% | High |
| **SecureAPIClient** | 90% | Critical |
| **Data Models** | 80% | Medium |

### Testing Tools

| Tool | Purpose | Required |
|------|---------|----------|
| **XCTest** | Unit & Integration tests | ✅ Yes |
| **Quick/Nimble** | BDD-style testing | Recommended |
| **OHHTTPStubs** | Network mocking | ✅ Yes |
| **HealthKit Test Data** | Mock health data | ✅ Yes |
| **Charles Proxy** | Network inspection | ✅ Yes |
| **OWASP ZAP** | Security scanning | ✅ Yes |
| **Burp Suite** | Penetration testing | Recommended |
| **SonarQube** | Code quality | Recommended |

---

## Unit Testing

### Test Structure

```swift
import XCTest
@testable import Health_Tracker_App

class ComponentNameTests: XCTestCase {

    // MARK: - Properties
    var sut: ComponentName!  // System Under Test
    var mockDependency: MockDependency!

    // MARK: - Setup & Teardown
    override func setUp() {
        super.setUp()
        mockDependency = MockDependency()
        sut = ComponentName(dependency: mockDependency)
    }

    override func tearDown() {
        sut = nil
        mockDependency = nil
        super.tearDown()
    }

    // MARK: - Tests
    func test_methodName_whenCondition_shouldExpectedBehavior() {
        // Given (Arrange)
        let input = ...

        // When (Act)
        let result = sut.method(input)

        // Then (Assert)
        XCTAssertEqual(result, expected)
    }
}
```

### HealthKit Permission Manager Tests

```swift
class HealthKitPermissionManagerTests: XCTestCase {

    var sut: HealthKitPermissionManager!
    var mockHealthStore: MockHKHealthStore!

    override func setUp() {
        super.setUp()
        mockHealthStore = MockHKHealthStore()
        sut = HealthKitPermissionManager(healthStore: mockHealthStore)
    }

    // MARK: - Authorization Tests

    func test_requestAuthorization_whenHealthKitAvailable_shouldSucceed() async throws {
        // Given
        mockHealthStore.isHealthDataAvailable = true
        mockHealthStore.authorizationResult = .success(())

        // When
        let result = try await sut.requestAuthorization()

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(mockHealthStore.requestAuthorizationCallCount, 1)
    }

    func test_requestAuthorization_whenHealthKitNotAvailable_shouldThrowError() async {
        // Given
        mockHealthStore.isHealthDataAvailable = false

        // When/Then
        await XCTAssertThrowsError(
            try await sut.requestAuthorization()
        ) { error in
            XCTAssertEqual(error as? HealthKitError, .notAvailable)
        }
    }

    func test_authorizationStatus_forHeartRate_shouldReturnCorrectStatus() {
        // Given
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        mockHealthStore.authorizationStatusForType = .sharingAuthorized

        // When
        let status = sut.authorizationStatus(for: .heartRate)

        // Then
        XCTAssertEqual(status, .sharingAuthorized)
    }

    func test_hasAllPermissions_whenAllGranted_shouldReturnTrue() {
        // Given
        mockHealthStore.authorizationStatusForType = .sharingAuthorized

        // When
        let result = sut.hasAllPermissions()

        // Then
        XCTAssertTrue(result)
    }

    func test_unauthorizedMetricTypes_whenSomeDenied_shouldReturnDeniedTypes() {
        // Given
        mockHealthStore.authorizationStatusMap = [
            .heartRate: .sharingAuthorized,
            .steps: .sharingDenied,
            .bloodPressure: .notDetermined
        ]

        // When
        let unauthorized = sut.unauthorizedMetricTypes()

        // Then
        XCTAssertEqual(unauthorized.count, 2)
        XCTAssertTrue(unauthorized.contains(.steps))
        XCTAssertTrue(unauthorized.contains(.bloodPressure))
    }
}
```

### HealthKit Data Fetcher Tests

```swift
class HealthKitDataFetcherTests: XCTestCase {

    var sut: HealthKitDataFetcher!
    var mockHealthStore: MockHKHealthStore!

    override func setUp() {
        super.setUp()
        mockHealthStore = MockHKHealthStore()
        sut = HealthKitDataFetcher(healthStore: mockHealthStore)
    }

    // MARK: - Heart Rate Tests

    func test_fetchHeartRate_withValidData_shouldReturnMetrics() async throws {
        // Given
        let startDate = Date().addingTimeInterval(-3600)
        let endDate = Date()
        let mockSamples = createMockHeartRateSamples(count: 10)
        mockHealthStore.queryResult = .success(mockSamples)

        // When
        let result = try await sut.fetchHeartRate(from: startDate, to: endDate)

        // Then
        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(result.first?.beatsPerMinute, 72.0)
    }

    func test_fetchHeartRate_withNoData_shouldReturnEmptyArray() async throws {
        // Given
        mockHealthStore.queryResult = .success([])

        // When
        let result = try await sut.fetchHeartRate(from: Date(), to: Date())

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_fetchHeartRate_withQueryError_shouldThrowError() async {
        // Given
        let expectedError = NSError(domain: "HKError", code: 5)
        mockHealthStore.queryResult = .failure(expectedError)

        // When/Then
        await XCTAssertThrowsError(
            try await sut.fetchHeartRate(from: Date(), to: Date())
        ) { error in
            XCTAssertEqual((error as NSError).code, 5)
        }
    }

    func test_fetchAverageHeartRate_withValidData_shouldCalculateCorrectly() async throws {
        // Given
        let mockSamples = createMockHeartRateSamples(values: [70, 75, 80])
        mockHealthStore.statisticsResult = .success(75.0)

        // When
        let average = try await sut.fetchAverageHeartRate(from: Date(), to: Date())

        // Then
        XCTAssertEqual(average, 75.0)
    }

    // MARK: - Steps Tests

    func test_fetchSteps_withValidData_shouldReturnMetrics() async throws {
        // Given
        let mockSamples = createMockStepsSamples(count: 5)
        mockHealthStore.queryResult = .success(mockSamples)

        // When
        let result = try await sut.fetchSteps(from: Date(), to: Date())

        // Then
        XCTAssertEqual(result.count, 5)
        XCTAssertGreaterThan(result.first?.count ?? 0, 0)
    }

    func test_fetchTotalSteps_withValidData_shouldSumCorrectly() async throws {
        // Given
        mockHealthStore.statisticsResult = .success(10000.0)

        // When
        let total = try await sut.fetchTotalSteps(from: Date(), to: Date())

        // Then
        XCTAssertEqual(total, 10000)
    }

    // MARK: - Blood Pressure Tests

    func test_fetchBloodPressure_withValidCorrelation_shouldReturnMetrics() async throws {
        // Given
        let mockCorrelations = createMockBloodPressureCorrelations(count: 3)
        mockHealthStore.queryResult = .success(mockCorrelations)

        // When
        let result = try await sut.fetchBloodPressure(from: Date(), to: Date())

        // Then
        XCTAssertEqual(result.count, 3)
        XCTAssertGreaterThan(result.first?.systolic ?? 0, 0)
        XCTAssertGreaterThan(result.first?.diastolic ?? 0, 0)
    }

    // MARK: - Sleep Tests

    func test_fetchSleep_withValidData_shouldReturnSessions() async throws {
        // Given
        let mockSamples = createMockSleepSamples(count: 8)
        mockHealthStore.queryResult = .success(mockSamples)

        // When
        let result = try await sut.fetchSleep(from: Date(), to: Date())

        // Then
        XCTAssertEqual(result.count, 8)
        XCTAssertNotNil(result.first?.stage)
    }

    func test_fetchTotalSleepDuration_withMultipleSessions_shouldSumCorrectly() async throws {
        // Given
        let mockSamples = createMockSleepSamples(durations: [3600, 7200, 14400])
        mockHealthStore.queryResult = .success(mockSamples)

        // When
        let duration = try await sut.fetchTotalSleepDuration(from: Date(), to: Date())

        // Then
        XCTAssertEqual(duration, 25200) // 7 hours total
    }

    // MARK: - Helper Methods

    private func createMockHeartRateSamples(count: Int) -> [HKQuantitySample] {
        // Implementation
        return []
    }

    private func createMockStepsSamples(count: Int) -> [HKQuantitySample] {
        // Implementation
        return []
    }
}
```

### Authentication Manager Tests

```swift
class AuthenticationManagerTests: XCTestCase {

    var sut: AuthenticationManager!
    var mockKeychainService: MockKeychainService!
    var mockURLSession: MockURLSession!

    override func setUp() {
        super.setUp()
        mockKeychainService = MockKeychainService()
        mockURLSession = MockURLSession()
        sut = AuthenticationManager(
            configuration: .default,
            keychainService: mockKeychainService,
            session: mockURLSession
        )
    }

    // MARK: - Login Tests

    func test_loginWithPassword_withValidCredentials_shouldSucceed() async throws {
        // Given
        let email = "test@example.com"
        let password = "password123"
        let mockTokenResponse = createMockTokenResponse()
        mockURLSession.mockResponse = .success(mockTokenResponse)

        // When
        try await sut.loginWithPassword(email: email, password: password)

        // Then
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertNotNil(sut.currentUser)
        XCTAssertEqual(mockKeychainService.saveCallCount, 2) // Access + refresh token
    }

    func test_loginWithPassword_withInvalidCredentials_shouldFail() async {
        // Given
        mockURLSession.mockResponse = .failure(NSError(domain: "Auth", code: 401))

        // When/Then
        await XCTAssertThrowsError(
            try await sut.loginWithPassword(email: "test@example.com", password: "wrong")
        ) { error in
            XCTAssertEqual(error as? AuthenticationError, .loginFailed)
        }
    }

    // MARK: - Token Management Tests

    func test_getAccessToken_whenTokenValid_shouldReturnToken() async throws {
        // Given
        try await setupAuthenticatedState()

        // When
        let token = try await sut.getAccessToken()

        // Then
        XCTAssertNotNil(token)
        XCTAssertFalse(token.isEmpty)
    }

    func test_getAccessToken_whenTokenExpired_shouldRefreshAndReturnNewToken() async throws {
        // Given
        try await setupAuthenticatedState(tokenExpired: true)
        mockURLSession.mockResponse = .success(createMockTokenResponse())

        // When
        let token = try await sut.getAccessToken()

        // Then
        XCTAssertNotNil(token)
        XCTAssertEqual(mockURLSession.requestCallCount, 1) // Refresh request
    }

    func test_refreshAccessToken_withValidRefreshToken_shouldUpdateTokens() async throws {
        // Given
        try await setupAuthenticatedState()
        let newTokenResponse = createMockTokenResponse(accessToken: "new_token")
        mockURLSession.mockResponse = .success(newTokenResponse)

        // When
        try await sut.refreshAccessToken()

        // Then
        let token = try await sut.getAccessToken()
        XCTAssertEqual(token, "new_token")
    }

    func test_refreshAccessToken_withExpiredRefreshToken_shouldLogout() async throws {
        // Given
        try await setupAuthenticatedState()
        mockURLSession.mockResponse = .failure(NSError(domain: "Auth", code: 401))

        // When/Then
        await XCTAssertThrowsError(
            try await sut.refreshAccessToken()
        )
        XCTAssertFalse(sut.isAuthenticated)
    }

    // MARK: - Logout Tests

    func test_logout_shouldClearAllTokensAndState() async {
        // Given
        try? await setupAuthenticatedState()

        // When
        await sut.logout()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertEqual(mockKeychainService.deleteCallCount, 3) // All tokens
    }

    // MARK: - Token Validation Tests

    func test_decodeAccessToken_withValidJWT_shouldExtractUserInfo() throws {
        // Given
        let validJWT = createMockJWT(userId: "123", email: "test@example.com")

        // When
        let user = try sut.decodeAccessToken(validJWT)

        // Then
        XCTAssertEqual(user.id, "123")
        XCTAssertEqual(user.email, "test@example.com")
    }

    func test_decodeAccessToken_withInvalidJWT_shouldThrowError() {
        // Given
        let invalidJWT = "invalid.jwt.token"

        // When/Then
        XCTAssertThrowsError(
            try sut.decodeAccessToken(invalidJWT)
        ) { error in
            XCTAssertEqual(error as? AuthenticationError, .invalidToken)
        }
    }

    // MARK: - Helper Methods

    private func setupAuthenticatedState(tokenExpired: Bool = false) async throws {
        let tokenResponse = createMockTokenResponse()
        mockKeychainService.mockStoredTokens = [
            "access_token": tokenResponse.accessToken,
            "refresh_token": tokenResponse.refreshToken!,
            "token_expiration": String(Date().addingTimeInterval(tokenExpired ? -3600 : 3600).timeIntervalSince1970)
        ]
    }

    private func createMockTokenResponse(accessToken: String = "mock_access_token") -> TokenResponse {
        return TokenResponse(
            accessToken: accessToken,
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "mock_refresh_token",
            scope: "read:health write:health"
        )
    }
}
```

### SSL Pinning Manager Tests

```swift
class SSLPinningManagerTests: XCTestCase {

    var sut: SSLPinningManager!
    var testCertificate: SecCertificate!

    override func setUp() {
        super.setUp()
        testCertificate = loadTestCertificate()
    }

    // MARK: - Pin Validation Tests

    func test_validateServerTrust_withValidPin_shouldSucceed() {
        // Given
        let validPin = extractPublicKeyHash(from: testCertificate)
        let config = SSLPinningManager.PinConfiguration(
            pins: [validPin],
            backupPins: [],
            pinningMode: .publicKeyHash,
            allowExpiredCertificates: false,
            validateCertificateChain: true
        )
        sut = SSLPinningManager(configuration: config)
        let serverTrust = createMockServerTrust(with: testCertificate)

        // When
        let result = sut.validateServerTrust(serverTrust, forHost: "api.test.com")

        // Then
        XCTAssertTrue(result)
    }

    func test_validateServerTrust_withInvalidPin_shouldFail() {
        // Given
        let invalidPin = "invalid_pin_hash"
        let config = SSLPinningManager.PinConfiguration(
            pins: [invalidPin],
            backupPins: [],
            pinningMode: .publicKeyHash,
            allowExpiredCertificates: false,
            validateCertificateChain: true
        )
        sut = SSLPinningManager(configuration: config)
        let serverTrust = createMockServerTrust(with: testCertificate)

        // When
        let result = sut.validateServerTrust(serverTrust, forHost: "api.test.com")

        // Then
        XCTAssertFalse(result)
    }

    func test_validateServerTrust_withBackupPin_shouldSucceed() {
        // Given
        let validPin = extractPublicKeyHash(from: testCertificate)
        let config = SSLPinningManager.PinConfiguration(
            pins: ["wrong_pin"],
            backupPins: [validPin],
            pinningMode: .publicKeyHash,
            allowExpiredCertificates: false,
            validateCertificateChain: true
        )
        sut = SSLPinningManager(configuration: config)
        let serverTrust = createMockServerTrust(with: testCertificate)

        // When
        let result = sut.validateServerTrust(serverTrust, forHost: "api.test.com")

        // Then
        XCTAssertTrue(result)
    }

    // MARK: - Certificate Extraction Tests

    func test_extractPublicKey_fromValidCertificate_shouldReturnKey() {
        // Given
        let certificate = testCertificate!

        // When
        let publicKey = sut.extractPublicKey(from: certificate)

        // Then
        XCTAssertNotNil(publicKey)
    }

    // MARK: - Pin Generation Tests

    func test_generatePinFromCertificate_shouldReturnValidHash() {
        // Given
        let certPath = Bundle(for: type(of: self)).path(forResource: "test_cert", ofType: "cer")!

        // When
        let pin = SSLPinningManager.generatePinFromCertificate(at: certPath)

        // Then
        XCTAssertNotNil(pin)
        XCTAssertEqual(pin?.count, 64) // SHA-256 hash length
    }

    // MARK: - Helper Methods

    private func loadTestCertificate() -> SecCertificate? {
        // Load test certificate from bundle
        return nil
    }

    private func extractPublicKeyHash(from certificate: SecCertificate) -> String {
        // Extract and hash public key
        return ""
    }
}
```

### Data Preprocessor Tests

```swift
class HealthDataPreprocessorTests: XCTestCase {

    var sut: HealthDataPreprocessor!

    override func setUp() {
        super.setUp()
        sut = HealthDataPreprocessor(config: .default)
    }

    // MARK: - Normalization Tests

    func test_normalize_withZScore_shouldStandardizeValues() async {
        // Given
        let values = [70.0, 75.0, 80.0, 85.0, 90.0]
        let mean = 80.0
        let stdDev = 7.07

        // When
        let normalized = await sut.normalize(
            values: values,
            method: .zScore,
            parameters: nil
        )

        // Then
        XCTAssertEqual(normalized[2], 0.0, accuracy: 0.01) // Mean should be 0
        XCTAssertLessThan(normalized[0], 0) // Below mean should be negative
        XCTAssertGreaterThan(normalized[4], 0) // Above mean should be positive
    }

    func test_normalize_withMinMax_shouldScaleTo01Range() async {
        // Given
        let values = [50.0, 75.0, 100.0]

        // When
        let normalized = await sut.normalize(
            values: values,
            method: .minMax,
            parameters: nil
        )

        // Then
        XCTAssertEqual(normalized[0], 0.0)
        XCTAssertEqual(normalized[2], 1.0)
        XCTAssertEqual(normalized[1], 0.5)
    }

    // MARK: - Outlier Detection Tests

    func test_handleOutliers_withZScoreMethod_shouldDetectOutliers() async {
        // Given
        let values = [70.0, 72.0, 74.0, 76.0, 78.0, 150.0] // 150 is outlier

        // When
        let (cleaned, outlierIndices) = await sut.handleOutliers(
            values: values,
            threshold: 3.0
        )

        // Then
        XCTAssertEqual(outlierIndices.count, 1)
        XCTAssertTrue(outlierIndices.contains(5))
    }

    func test_handleOutliers_withCapStrategy_shouldCapOutliers() async {
        // Given
        let config = HealthDataPreprocessor.PreprocessingConfig(
            normalizationMethod: .zScore,
            outlierHandling: .cap,
            outlierThreshold: 3.0,
            missingDataStrategy: .interpolation,
            smoothingEnabled: false,
            smoothingWindowSize: 5
        )
        sut = HealthDataPreprocessor(config: config)
        let values = [70.0, 72.0, 74.0, 76.0, 78.0, 150.0]

        // When
        let (cleaned, _) = await sut.handleOutliers(values: values, threshold: 3.0)

        // Then
        XCTAssertLessThan(cleaned[5], 150.0) // Outlier should be capped
    }

    // MARK: - Statistics Calculation Tests

    func test_calculateStatistics_withValidData_shouldReturnCorrectStats() async {
        // Given
        let values = [60.0, 70.0, 80.0, 90.0, 100.0]

        // When
        let stats = await sut.calculateStatistics(values: values)

        // Then
        XCTAssertEqual(stats.count, 5)
        XCTAssertEqual(stats.mean, 80.0)
        XCTAssertEqual(stats.median, 80.0)
        XCTAssertEqual(stats.min, 60.0)
        XCTAssertEqual(stats.max, 100.0)
    }

    // MARK: - Feature Engineering Tests

    func test_calculateCardiovascularScore_withLowRestingHR_shouldReturnHighScore() async {
        // Given
        let heartRateData = createMockProcessedHeartRateData(mean: 58.0, stdDev: 10.0)

        // When
        let score = await sut.calculateCardiovascularScore(heartRate: heartRateData)

        // Then
        XCTAssertGreaterThan(score, 80.0)
    }

    func test_calculateSleepQualityIndex_withHighEfficiency_shouldReturnHighScore() async {
        // Given
        let sleepData = createMockProcessedSleepData(efficiency: 0.95, duration: 8.0)

        // When
        let score = await sut.calculateSleepQualityIndex(sleep: sleepData)

        // Then
        XCTAssertGreaterThan(score, 90.0)
    }
}
```

---

## Integration Testing

### Integration Test Structure

```swift
class HealthKitIntegrationTests: XCTestCase {

    var healthManager: HealthKitManager!

    override func setUp() {
        super.setUp()

        // Skip if running on simulator (HealthKit not available)
        guard HKHealthStore.isHealthDataAvailable() else {
            return
        }

        let config = HealthKitManager.Configuration.default(userId: "test_user")
        healthManager = HealthKitManager(configuration: config)
    }

    // MARK: - End-to-End Tests

    func test_completeHealthDataFlow_fromPermissionToFetch() async throws {
        try XCTSkipIf(!HKHealthStore.isHealthDataAvailable(), "HealthKit not available")

        // 1. Request permissions
        try await healthManager.requestPermissions()
        XCTAssertTrue(healthManager.isAuthorized)

        // 2. Fetch heart rate
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!
        let heartRate = try await healthManager.fetchHeartRate(from: startDate, to: endDate)

        // 3. Verify data
        XCTAssertNotNil(heartRate)
    }

    func test_cacheIntegration_shouldReduceHealthKitQueries() async throws {
        try XCTSkipIf(!HKHealthStore.isHealthDataAvailable(), "HealthKit not available")

        // First fetch (cache miss)
        let startTime1 = Date()
        let data1 = try await healthManager.fetchHeartRate(from: Date(), to: Date(), useCache: true)
        let duration1 = Date().timeIntervalSince(startTime1)

        // Second fetch (cache hit)
        let startTime2 = Date()
        let data2 = try await healthManager.fetchHeartRate(from: Date(), to: Date(), useCache: true)
        let duration2 = Date().timeIntervalSince(startTime2)

        // Cache should be significantly faster
        XCTAssertLessThan(duration2, duration1 * 0.5)
    }
}
```

### API Integration Tests

```swift
class APIIntegrationTests: XCTestCase {

    var apiClient: SecureAPIClient!
    var authManager: AuthenticationManager!

    override func setUp() {
        super.setUp()
        authManager = AuthenticationManager(configuration: .staging)
        apiClient = SecureAPIClient(authenticationManager: authManager)
    }

    // MARK: - Authentication Flow Tests

    func test_authenticationFlow_withValidCredentials_shouldCompleteSuccessfully() async throws {
        // 1. Login
        try await authManager.loginWithPassword(
            email: ProcessInfo.processInfo.environment["TEST_EMAIL"]!,
            password: ProcessInfo.processInfo.environment["TEST_PASSWORD"]!
        )

        // 2. Verify authenticated
        XCTAssertTrue(authManager.isAuthenticated)

        // 3. Make API call
        let profile: UserProfile = try await apiClient.getUserProfile(
            userId: authManager.currentUser!.id
        )

        // 4. Verify response
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile.userId, authManager.currentUser!.id)
    }

    // MARK: - Token Refresh Tests

    func test_tokenRefresh_when401Error_shouldRefreshAndRetry() async throws {
        // Setup authenticated state with expired token
        try await setupExpiredTokenState()

        // Make API call (should trigger refresh)
        let profile: UserProfile = try await apiClient.getUserProfile(userId: "test")

        // Verify successful response after refresh
        XCTAssertNotNil(profile)
    }

    // MARK: - Health Data Upload Tests

    func test_healthDataUpload_withEncryption_shouldSucceed() async throws {
        // Login first
        try await authManager.loginWithPassword(
            email: testEmail,
            password: testPassword
        )

        // Create test health data
        let healthData = createTestHealthDataBatch()

        // Upload
        let response: UploadResponse = try await apiClient.uploadHealthData(healthData)

        // Verify
        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.uploadId)
    }
}
```

---

## Security Testing

### Network Security Tests

```swift
class NetworkSecurityTests: XCTestCase {

    // MARK: - SSL Pinning Tests

    func test_sslPinning_withInvalidCertificate_shouldRejectConnection() async {
        // Given
        let invalidPinConfig = SSLPinningManager.PinConfiguration(
            pins: ["invalid_pin_hash"],
            backupPins: [],
            pinningMode: .publicKeyHash,
            allowExpiredCertificates: false,
            validateCertificateChain: true
        )

        let pinningManager = SSLPinningManager(configuration: invalidPinConfig)
        let authManager = AuthenticationManager(configuration: .production)
        let apiClient = SecureAPIClient(
            authenticationManager: authManager,
            pinningManager: pinningManager
        )

        // When/Then
        await XCTAssertThrowsError(
            try await apiClient.get(endpoint: "/test", queryParams: nil)
        ) { error in
            // Should fail due to pinning validation
            XCTAssertTrue(error is URLError || error is APIError)
        }
    }

    // MARK: - Encryption Tests

    func test_dataEncryption_shouldEncryptAndDecryptCorrectly() throws {
        // Given
        let plainData = "Sensitive health data".data(using: .utf8)!
        let apiClient = SecureAPIClient(authenticationManager: mockAuthManager)

        // When
        let (encryptedData, metadata) = try apiClient.encryptData(plainData)

        // Then
        XCTAssertNotEqual(encryptedData, plainData)
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.algorithm, "AES-GCM-256")

        // Decrypt
        let decryptedData = try apiClient.decryptData(encryptedData, metadata: metadata)
        XCTAssertEqual(decryptedData, plainData)
    }

    // MARK: - Request Signing Tests

    func test_requestSigning_shouldGenerateValidSignature() throws {
        // Given
        let request = URLRequest(url: URL(string: "https://api.test.com/health")!)
        let bodyData = "test data".data(using: .utf8)!

        // When
        let signature = try apiClient.signRequest(request, body: bodyData)

        // Then
        XCTAssertFalse(signature.isEmpty)
        XCTAssertEqual(signature.count, 44) // Base64-encoded SHA-256 length
    }

    // MARK: - Keychain Security Tests

    func test_keychainStorage_shouldStoreAndRetrieveSecurely() {
        // Given
        let keychainService = KeychainService()
        let sensitiveValue = "secret_token_12345"
        let key = "test_key"

        // When - Store
        keychainService.save(key: key, value: sensitiveValue)

        // Then - Retrieve
        let retrievedValue = keychainService.retrieve(key: key)
        XCTAssertEqual(retrievedValue, sensitiveValue)

        // Cleanup
        keychainService.delete(key: key)
        let deletedValue = keychainService.retrieve(key: key)
        XCTAssertNil(deletedValue)
    }
}
```

---

## Performance Testing

### Performance Benchmarks

```swift
class PerformanceTests: XCTestCase {

    func test_heartRateFetch_performance() {
        let healthManager = HealthKitManager(configuration: .default(userId: "test"))

        measure {
            let expectation = XCTestExpectation(description: "Fetch heart rate")

            Task {
                _ = try? await healthManager.fetchHeartRate(
                    from: Date().addingTimeInterval(-86400),
                    to: Date()
                )
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }

    func test_dataPreprocessing_performance() {
        let preprocessor = HealthDataPreprocessor(config: .default)
        let largeDataset = createLargeHealthDataset(size: 10000)

        measure {
            Task {
                _ = try? await preprocessor.preprocessHealthData(
                    heartRate: largeDataset.heartRate,
                    bloodPressure: largeDataset.bloodPressure,
                    steps: largeDataset.steps,
                    sleep: largeDataset.sleep
                )
            }
        }
    }

    func test_encryption_performance() {
        let apiClient = SecureAPIClient(authenticationManager: mockAuth)
        let data = createTestData(size: 100_000) // 100KB

        measure {
            _ = try? apiClient.encryptData(data)
        }
    }
}
```

---

## Testing Checklist

### Pre-Testing

- [ ] Test devices configured (real iPhone required)
- [ ] Test Apple ID with HealthKit permissions
- [ ] Sample health data populated
- [ ] Network mocking configured
- [ ] Test certificates installed
- [ ] Environment variables set

### Unit Tests

- [ ] All HealthKit components tested
- [ ] All authentication flows tested
- [ ] All encryption methods tested
- [ ] All data models validated
- [ ] Edge cases covered
- [ ] Error paths tested
- [ ] Coverage >85%

### Integration Tests

- [ ] End-to-end HealthKit flow tested
- [ ] API authentication tested
- [ ] Data upload/download tested
- [ ] Token refresh tested
- [ ] Observer updates tested
- [ ] Background sync tested

### Security Tests

- [ ] SSL pinning validated
- [ ] Encryption verified
- [ ] Request signing tested
- [ ] Keychain security tested
- [ ] OWASP checks passed
- [ ] Penetration tests passed

### Performance Tests

- [ ] Query performance benchmarked
- [ ] Encryption performance measured
- [ ] Memory usage profiled
- [ ] Battery impact tested
- [ ] Network efficiency measured

---

## Next Steps

1. Review test coverage requirements
2. Set up CI/CD testing pipeline
3. Configure test environments
4. Run security scans
5. Complete HIPAA compliance testing

For security testing details, see [SECURITY_TESTING_GUIDE.md](SECURITY_TESTING_GUIDE.md).

For App Store submission, see [APP_STORE_CHECKLIST.md](APP_STORE_CHECKLIST.md).
