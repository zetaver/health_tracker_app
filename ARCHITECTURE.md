# HIPAA-Compliant Health Tracker iOS App - Architecture

## Executive Summary

This document outlines the architecture for a next-generation, HIPAA-compliant Health Tracker iOS application that integrates with Apple HealthKit to sync vital health data (heart rate, steps, sleep, oxygen saturation, blood pressure) while ensuring maximum security, scalability, and regulatory compliance.

---

## 1. Architecture Pattern: MVVM + Clean Architecture

### Recommended Pattern: **MVVM (Model-View-ViewModel) with Clean Architecture**

**Why MVVM over VIPER:**
- **Better SwiftUI Integration**: MVVM pairs naturally with SwiftUI's declarative paradigm
- **Reduced Complexity**: VIPER adds unnecessary layers for most health apps
- **Combine Framework Synergy**: ViewModels work seamlessly with Combine publishers
- **Easier Testing**: Clear separation of concerns without VIPER's verbosity
- **Apple Ecosystem Alignment**: Apple's recommended pattern for SwiftUI apps

**Clean Architecture Layers:**
```
┌─────────────────────────────────────────┐
│         Presentation Layer              │
│    (SwiftUI Views + ViewModels)         │
└─────────────────────────────────────────┘
              ↓ ↑
┌─────────────────────────────────────────┐
│          Domain Layer                   │
│   (Use Cases, Entities, Protocols)      │
└─────────────────────────────────────────┘
              ↓ ↑
┌─────────────────────────────────────────┐
│           Data Layer                    │
│  (Repositories, Data Sources, APIs)     │
└─────────────────────────────────────────┘
```

---

## 2. iOS Frameworks & Technologies

### 2.1 Core Frameworks

| Framework | Purpose | Justification |
|-----------|---------|---------------|
| **SwiftUI** | UI Layer | Modern declarative UI, better performance, native iOS 14+ support |
| **Combine** | Reactive Programming | Built-in async data streams, perfect for HealthKit real-time updates |
| **HealthKit** | Health Data Access | Official Apple framework for health data (HKHealthStore, HKSampleQuery, HKObserverQuery) |
| **CoreData** | Local Persistence | Encrypted local storage, iCloud sync support, proven reliability |
| **CryptoKit** | Encryption | Hardware-accelerated encryption (AES-256-GCM), HIPAA-compliant |
| **Keychain Services** | Secure Credential Storage | Hardware-backed secure enclave for tokens, keys, PHI identifiers |

### 2.2 Networking

| Technology | Purpose | Recommendation |
|------------|---------|----------------|
| **URLSession** | Primary API Client | ✅ **Recommended** - Native, Combine integration, certificate pinning support |
| **Alamofire** | Alternative | ❌ Avoid - Adds unnecessary dependency for standard REST/GraphQL APIs |

**Why URLSession:**
- Native certificate pinning for MITM protection
- Built-in Combine publishers
- Lower attack surface (no third-party dependencies)
- Better App Store review compliance

### 2.3 Additional Security Frameworks

- **LocalAuthentication**: Biometric authentication (Face ID/Touch ID)
- **Network**: Monitor network connectivity for offline-first architecture
- **BackgroundTasks**: Secure background sync for health data

---

## 3. Modular Architecture Design

### 3.1 Module Structure

```
HealthTrackerApp/
├── App/
│   ├── HealthTrackerApp.swift         # App entry point
│   ├── AppCoordinator.swift           # Navigation coordination
│   └── DependencyContainer.swift      # Dependency injection
│
├── Core/                              # Shared utilities
│   ├── Extensions/
│   ├── Constants/
│   └── Utilities/
│
├── Domain/                            # Business logic (framework-independent)
│   ├── Entities/
│   │   ├── HealthMetric.swift
│   │   ├── UserProfile.swift
│   │   └── SyncStatus.swift
│   ├── UseCases/
│   │   ├── FetchHeartRateUseCase.swift
│   │   ├── SyncHealthDataUseCase.swift
│   │   └── AuthenticateUserUseCase.swift
│   └── Repositories/                  # Protocol definitions
│       ├── HealthDataRepository.swift
│       └── UserRepository.swift
│
├── Data/                              # Data access layer
│   ├── Repositories/                  # Protocol implementations
│   │   ├── HealthKitRepository.swift
│   │   └── RemoteHealthRepository.swift
│   ├── DataSources/
│   │   ├── Local/
│   │   │   ├── CoreDataManager.swift
│   │   │   ├── HealthKitManager.swift
│   │   │   └── KeychainManager.swift
│   │   └── Remote/
│   │       ├── APIClient.swift
│   │       └── APIEndpoints.swift
│   ├── Models/
│   │   ├── DTOs/                      # Data transfer objects
│   │   └── CoreDataModels/
│   └── Encryption/
│       ├── DataEncryptionService.swift
│       └── CertificatePinningManager.swift
│
├── Presentation/                      # UI layer
│   ├── Common/
│   │   ├── Components/                # Reusable UI components
│   │   └── Modifiers/
│   ├── Screens/
│   │   ├── Dashboard/
│   │   │   ├── DashboardView.swift
│   │   │   └── DashboardViewModel.swift
│   │   ├── HealthMetrics/
│   │   │   ├── HeartRateView.swift
│   │   │   ├── HeartRateViewModel.swift
│   │   │   └── (Steps, Sleep, Oxygen, BP...)
│   │   ├── Authentication/
│   │   │   ├── LoginView.swift
│   │   │   └── BiometricAuthView.swift
│   │   └── Settings/
│   │       └── PrivacySettingsView.swift
│   └── Navigation/
│       └── AppRouter.swift
│
└── Infrastructure/                    # External integrations
    ├── HealthKit/
    │   ├── HealthKitService.swift
    │   ├── HealthKitQueryBuilder.swift
    │   └── HealthKitAuthorization.swift
    ├── Networking/
    │   ├── NetworkMonitor.swift
    │   └── RequestInterceptor.swift
    └── Analytics/
        └── AnalyticsService.swift     # HIPAA-compliant analytics
```

---

## 4. HIPAA Compliance & Security Architecture

### 4.1 Data Encryption Strategy

#### At Rest (Local Storage)
```swift
// Three-tier encryption strategy

1. CoreData Encryption
   - NSPersistentContainer with encryption enabled
   - SQLite database file encryption (AES-256)

2. Field-level Encryption (CryptoKit)
   - Sensitive PHI fields encrypted individually
   - Key derivation using PBKDF2/Argon2

3. Keychain Storage
   - User credentials, API tokens, encryption keys
   - Hardware-backed secure enclave (when available)
```

#### In Transit
```swift
// TLS 1.3 + Certificate Pinning

- URLSession with custom TLS configuration
- Public key pinning for API endpoints
- Certificate rotation strategy
- Perfect Forward Secrecy (PFS)
```

### 4.2 Data Minimization & Anonymization

```swift
// Only store necessary PHI
struct HealthMetricDTO {
    let timestamp: Date
    let value: Double
    let type: HealthMetricType
    // NO user identifiers at this level
}

// Separate user-metric association
struct SecureUserMetricAssociation {
    let encryptedUserId: Data      // Encrypted user ID
    let metricId: UUID
}
```

### 4.3 Authentication & Authorization

```
┌─────────────────────────────────────────┐
│   User Authentication Flow              │
└─────────────────────────────────────────┘

1. Biometric (Face ID/Touch ID)
         ↓
2. OAuth 2.0 + PKCE with Backend
         ↓
3. JWT Token Storage (Keychain)
         ↓
4. Refresh Token Rotation
         ↓
5. Session Management (15-min timeout)
```

**Implementation:**
```swift
protocol AuthenticationService {
    func authenticateWithBiometric() async throws -> Bool
    func authenticateWithBackend(code: String) async throws -> AuthToken
    func refreshToken() async throws -> AuthToken
    func logout()
}
```

### 4.4 Audit Logging

```swift
// HIPAA requires audit trails for PHI access

struct AuditLog: Codable {
    let timestamp: Date
    let action: AuditAction  // .read, .write, .delete, .sync
    let dataType: HealthMetricType
    let userId: String       // Hashed
    let success: Bool
}

// Store encrypted audit logs locally + sync to backend
```

---

## 5. HealthKit Integration Architecture

### 5.1 HealthKit Manager

```swift
class HealthKitManager {
    private let healthStore = HKHealthStore()

    // Request permissions
    func requestAuthorization() async throws

    // Query methods
    func fetchHeartRate(from: Date, to: Date) -> AnyPublisher<[HeartRateSample], Error>
    func fetchSteps(from: Date, to: Date) -> AnyPublisher<[StepsSample], Error>
    func fetchSleep(from: Date, to: Date) -> AnyPublisher<[SleepSample], Error>
    func fetchOxygenSaturation(from: Date, to: Date) -> AnyPublisher<[OxygenSample], Error>
    func fetchBloodPressure(from: Date, to: Date) -> AnyPublisher<[BPSample], Error>

    // Observer queries for real-time updates
    func observeHeartRate() -> AnyPublisher<HeartRateSample, Never>
}
```

### 5.2 Query Strategy

```swift
// Use HKStatisticsCollectionQuery for aggregated data
// Use HKSampleQuery for detailed samples
// Use HKObserverQuery for real-time notifications
// Use HKAnchoredObjectQuery for incremental sync

protocol HealthKitQueryBuilder {
    func buildSampleQuery(type: HKSampleType, predicate: NSPredicate) -> HKSampleQuery
    func buildObserverQuery(type: HKSampleType) -> HKObserverQuery
    func buildAnchoredQuery(type: HKSampleType, anchor: HKQueryAnchor?) -> HKAnchoredObjectQuery
}
```

### 5.3 Background Sync

```swift
// Use HKObserverQuery + BackgroundTasks framework

import BackgroundTasks

class BackgroundSyncManager {
    func scheduleBackgroundSync() {
        let request = BGProcessingTaskRequest(identifier: "com.app.healthsync")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        BGTaskScheduler.shared.submit(request)
    }
}
```

---

## 6. Backend Integration Architecture

### 6.1 API Communication Layer

```swift
protocol APIClient {
    func request<T: Decodable>(
        endpoint: APIEndpoint,
        method: HTTPMethod,
        body: Encodable?
    ) async throws -> T
}

enum APIEndpoint {
    case syncHealthData
    case fetchUserProfile
    case uploadMetrics(type: HealthMetricType)

    var path: String { /* ... */ }
}

class SecureAPIClient: APIClient {
    private let session: URLSession
    private let certificatePinner: CertificatePinningManager
    private let tokenManager: TokenManager

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true

        self.session = URLSession(configuration: config, delegate: certificatePinner, delegateQueue: nil)
    }
}
```

### 6.2 Sync Strategy

```swift
// Offline-first architecture with eventual consistency

class HealthDataSyncService {
    func syncToBackend() async {
        // 1. Fetch unsynchronized records from CoreData
        // 2. Encrypt sensitive fields
        // 3. Batch upload to backend (max 100 records/request)
        // 4. Handle conflicts with server-side timestamps
        // 5. Mark records as synced
        // 6. Retry failed uploads with exponential backoff
    }
}
```

### 6.3 Recommended Backend Stack (HIPAA-Compliant)

#### Option 1: Azure Health Data Services
```
Architecture:
├── Azure FHIR Service (HIPAA-compliant storage)
├── Azure API Management (rate limiting, auth)
├── Azure Functions (serverless processing)
├── Azure Key Vault (encryption key management)
├── Azure Monitor (audit logging)
└── Azure AD B2C (user authentication)

Benefits:
✅ HIPAA BAA available
✅ Built-in FHIR support
✅ Seamless compliance tools
✅ 99.9% SLA
```

#### Option 2: Google Cloud Healthcare API
```
Architecture:
├── Google Cloud Healthcare API (FHIR/HL7 store)
├── Cloud Functions (data processing)
├── Secret Manager (key storage)
├── Cloud Logging (audit trails)
└── Firebase Auth (user management)

Benefits:
✅ HIPAA compliance
✅ FHIR R4 support
✅ De-identification tools
✅ ML/AI integrations
```

### 6.4 API Contract Example

```json
// POST /api/v1/health/metrics/sync

Request:
{
  "userId": "encrypted_user_id",
  "metrics": [
    {
      "type": "heart_rate",
      "value": 72,
      "unit": "bpm",
      "timestamp": "2025-10-21T10:30:00Z",
      "sourceId": "apple_watch_series_9"
    }
  ],
  "encryptionMetadata": {
    "algorithm": "AES-256-GCM",
    "keyVersion": "v2"
  }
}

Response:
{
  "syncedCount": 1,
  "failedCount": 0,
  "conflicts": [],
  "serverTimestamp": "2025-10-21T10:30:05Z"
}
```

---

## 7. Data Flow Architecture

### 7.1 Health Data Sync Flow

```
┌──────────────┐
│  Apple Watch │
│  iPhone      │
└──────┬───────┘
       │
       ↓
┌──────────────────────────────────────┐
│         HealthKit Store              │
└──────┬───────────────────────────────┘
       │
       ↓ (HKObserverQuery)
┌──────────────────────────────────────┐
│     HealthKitManager (Data Layer)    │
│  - Fetch samples                     │
│  - Transform to domain entities      │
└──────┬───────────────────────────────┘
       │
       ↓
┌──────────────────────────────────────┐
│  HealthDataRepository (Domain)       │
│  - Validate data                     │
│  - Apply business rules              │
└──────┬───────────────────────────────┘
       │
       ↓
┌──────────────────────────────────────┐
│      CoreDataManager                 │
│  - Encrypt PHI fields (CryptoKit)    │
│  - Save to encrypted database        │
│  - Create audit log                  │
└──────┬───────────────────────────────┘
       │
       ↓ (Background Task)
┌──────────────────────────────────────┐
│    BackgroundSyncManager             │
│  - Queue for upload                  │
└──────┬───────────────────────────────┘
       │
       ↓
┌──────────────────────────────────────┐
│         APIClient                    │
│  - Add auth headers                  │
│  - Certificate pinning               │
│  - TLS 1.3 encryption                │
└──────┬───────────────────────────────┘
       │
       ↓
┌──────────────────────────────────────┐
│   Backend API (Azure/GCP)            │
│  - Validate JWT token                │
│  - Store in FHIR-compliant format    │
│  - Create audit trail                │
│  - Send push notification (optional) │
└──────────────────────────────────────┘
```

---

## 8. Security Checklist

### 8.1 HIPAA Technical Safeguards

- [x] **Access Control**: Biometric + OAuth 2.0
- [x] **Audit Controls**: Encrypted audit logs
- [x] **Integrity Controls**: Data checksums/signatures
- [x] **Transmission Security**: TLS 1.3 + certificate pinning
- [x] **Encryption**: At-rest (AES-256) + in-transit (TLS)

### 8.2 iOS-Specific Security

```swift
// 1. Prevent screenshots of sensitive screens
.onAppear {
    NotificationCenter.default.addObserver(
        forName: UIApplication.userDidTakeScreenshotNotification
    ) { _ in
        // Log security event, alert user
    }
}

// 2. Clear sensitive data on app backgrounding
.onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
    clearSensitiveDataFromMemory()
}

// 3. Require authentication on app foreground
.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
    requireAuthentication()
}

// 4. Disable pasteboard for PHI fields
TextField("Blood Pressure", text: $bloodPressure)
    .textContentType(.none)
    .disableAutocorrection(true)
```

---

## 9. Scalability Considerations

### 9.1 Local Storage Optimization

```swift
// Implement data retention policy
class DataRetentionPolicy {
    func purgeOldRecords(olderThan days: Int) {
        // Keep last 90 days locally
        // Archive older data to backend only
    }
}

// Implement pagination for large datasets
class HealthDataViewModel {
    func fetchHealthData(page: Int, pageSize: Int = 50) {
        // Paginate queries to HealthKit and CoreData
    }
}
```

### 9.2 Performance Optimization

```swift
// Use background contexts for heavy operations
let backgroundContext = persistentContainer.newBackgroundContext()
backgroundContext.perform {
    // Bulk insert operations
}

// Batch HealthKit queries
let batchSize = 1000
let query = HKSampleQuery(
    sampleType: heartRateType,
    predicate: predicate,
    limit: batchSize,
    sortDescriptors: [sortDescriptor]
) { query, samples, error in
    // Process in batches
}
```

### 9.3 Caching Strategy

```swift
// Multi-layer caching
protocol CacheService {
    func cache(_ data: Data, forKey key: String, ttl: TimeInterval)
    func retrieve(forKey key: String) -> Data?
}

// Layer 1: In-memory cache (NSCache)
// Layer 2: Encrypted disk cache (CoreData)
// Layer 3: Backend API
```

---

## 10. Testing Strategy

### 10.1 Test Pyramid

```
         ┌──────────┐
         │    UI    │ (10% - SwiftUI Previews + UI Tests)
         └──────────┘
       ┌──────────────┐
       │ Integration  │ (30% - HealthKit mocking, API mocking)
       └──────────────┘
   ┌────────────────────┐
   │   Unit Tests       │ (60% - ViewModels, UseCases, Repositories)
   └────────────────────┘
```

### 10.2 HIPAA Testing Requirements

```swift
// Security tests
func testDataEncryption() {
    // Verify PHI is encrypted in CoreData
}

func testAuthenticationTimeout() {
    // Verify session expires after 15 minutes
}

func testAuditLogging() {
    // Verify all PHI access is logged
}

// HealthKit integration tests
func testHealthKitAuthorization() {
    // Mock HKHealthStore
}

func testBackgroundSync() {
    // Mock background task execution
}
```

---

## 11. Dependency Management

### Recommended Approach: Swift Package Manager (SPM)

```swift
// Package.swift dependencies

.package(url: "https://github.com/apple/swift-crypto", from: "3.0.0")
// For backward compatibility with iOS < 13

// Optional (use sparingly):
// .package(url: "https://github.com/auth0/Auth0.swift", from: "2.0.0")
```

**Avoid CocoaPods/Carthage** - SPM is Apple's official solution with better security.

---

## 12. Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
- [ ] Set up project structure
- [ ] Implement authentication layer
- [ ] Configure CoreData + encryption
- [ ] Set up HealthKit permissions

### Phase 2: Core Features (Weeks 3-5)
- [ ] Implement HealthKit data fetching
- [ ] Build MVVM architecture for each metric
- [ ] Create SwiftUI views
- [ ] Implement local caching

### Phase 3: Backend Integration (Weeks 6-7)
- [ ] Build API client with certificate pinning
- [ ] Implement sync service
- [ ] Add offline support
- [ ] Configure background tasks

### Phase 4: Security & Compliance (Week 8)
- [ ] Security audit
- [ ] Penetration testing
- [ ] HIPAA compliance review
- [ ] Audit logging validation

### Phase 5: Testing & Release (Weeks 9-10)
- [ ] Unit + integration tests
- [ ] UI testing
- [ ] Performance optimization
- [ ] App Store submission

---

## 13. Key Takeaways

✅ **Use MVVM + Clean Architecture** for SwiftUI apps
✅ **URLSession over Alamofire** for better security control
✅ **CryptoKit + Keychain** for HIPAA-compliant encryption
✅ **CoreData with encryption** for local persistence
✅ **Certificate pinning** is mandatory
✅ **Offline-first architecture** for better UX
✅ **Azure/GCP Health APIs** for backend compliance
✅ **Biometric auth + OAuth 2.0** for user authentication
✅ **Audit all PHI access** per HIPAA requirements
✅ **Background sync** using HKObserverQuery + BackgroundTasks

---

## 14. Next Steps

1. Review and approve this architecture
2. Set up Xcode project structure according to module design
3. Configure Info.plist with HealthKit permissions
4. Implement core data models and repositories
5. Build authentication flow
6. Integrate HealthKit step-by-step (heart rate → steps → sleep → oxygen → BP)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-21
**Author**: Senior iOS Architect
**Compliance**: HIPAA, GDPR-ready
