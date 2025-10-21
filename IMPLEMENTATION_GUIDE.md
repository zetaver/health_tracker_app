# Implementation Guide - Getting Started

This guide provides practical Swift code examples to implement the HIPAA-compliant Health Tracker architecture.

---

## 1. Project Structure Setup

### 1.1 Create Folder Structure in Xcode

```
Right-click on "Health Tracker App" → New Group
Create the following groups:
- App
- Core
- Domain
  - Entities
  - UseCases
  - Repositories
- Data
  - Repositories
  - DataSources
    - Local
    - Remote
  - Models
  - Encryption
- Presentation
  - Screens
    - Dashboard
    - HealthMetrics
    - Authentication
  - Common
- Infrastructure
  - HealthKit
  - Networking
```

---

## 2. Core Domain Models

### 2.1 Domain/Entities/HealthMetric.swift

```swift
import Foundation

enum HealthMetricType: String, Codable {
    case heartRate = "heart_rate"
    case steps = "steps"
    case sleep = "sleep"
    case oxygenSaturation = "oxygen_saturation"
    case bloodPressure = "blood_pressure"
}

struct HealthMetric: Identifiable, Codable {
    let id: UUID
    let type: HealthMetricType
    let value: Double
    let unit: String
    let timestamp: Date
    let sourceId: String
    let metadata: [String: String]?

    init(
        id: UUID = UUID(),
        type: HealthMetricType,
        value: Double,
        unit: String,
        timestamp: Date = Date(),
        sourceId: String,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.type = type
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.sourceId = sourceId
        self.metadata = metadata
    }
}

// Heart rate specific model
struct HeartRateSample {
    let beatsPerMinute: Double
    let timestamp: Date
    let source: String

    func toHealthMetric() -> HealthMetric {
        HealthMetric(
            type: .heartRate,
            value: beatsPerMinute,
            unit: "bpm",
            timestamp: timestamp,
            sourceId: source
        )
    }
}
```

---

## 3. Repository Protocol (Domain Layer)

### 3.1 Domain/Repositories/HealthDataRepository.swift

```swift
import Foundation
import Combine

protocol HealthDataRepository {
    func fetchHeartRate(from startDate: Date, to endDate: Date) -> AnyPublisher<[HeartRateSample], Error>
    func fetchSteps(from startDate: Date, to endDate: Date) -> AnyPublisher<[HealthMetric], Error>
    func observeHeartRate() -> AnyPublisher<HeartRateSample, Never>
    func saveMetric(_ metric: HealthMetric) async throws
    func syncToBackend() async throws
}
```

---

## 4. HealthKit Manager (Data Layer)

### 4.1 Infrastructure/HealthKit/HealthKitManager.swift

```swift
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }

        let readTypes: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!
        ]

        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    // MARK: - Heart Rate Queries

    func fetchHeartRate(from startDate: Date, to endDate: Date) -> AnyPublisher<[HeartRateSample], Error> {
        Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(HealthKitError.managerDeallocated))
                return
            }

            let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: .strictStartDate
            )

            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }

                let heartRateSamples = (samples as? [HKQuantitySample])?.map { sample -> HeartRateSample in
                    let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    return HeartRateSample(
                        beatsPerMinute: bpm,
                        timestamp: sample.startDate,
                        source: sample.sourceRevision.source.name
                    )
                } ?? []

                promise(.success(heartRateSamples))
            }

            self.healthStore.execute(query)
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Observer Query for Real-time Updates

    func observeHeartRate() -> AnyPublisher<HeartRateSample, Never> {
        let subject = PassthroughSubject<HeartRateSample, Never>()

        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil, let self = self else {
                completionHandler()
                return
            }

            // When notified, fetch the latest sample
            let now = Date()
            let oneMinuteAgo = Calendar.current.date(byAdding: .minute, value: -1, to: now)!

            self.fetchHeartRate(from: oneMinuteAgo, to: now)
                .sink(
                    receiveCompletion: { _ in completionHandler() },
                    receiveValue: { samples in
                        if let latest = samples.first {
                            subject.send(latest)
                        }
                    }
                )
                .store(in: &self.cancellables)
        }

        healthStore.execute(query)
        return subject.eraseToAnyPublisher()
    }

    // MARK: - Steps Query

    func fetchSteps(from startDate: Date, to endDate: Date) -> AnyPublisher<[HealthMetric], Error> {
        Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(HealthKitError.managerDeallocated))
                return
            }

            let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

            let query = HKStatisticsQuery(
                quantityType: stepsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }

                guard let statistics = statistics,
                      let sum = statistics.sumQuantity() else {
                    promise(.success([]))
                    return
                }

                let steps = sum.doubleValue(for: .count())
                let metric = HealthMetric(
                    type: .steps,
                    value: steps,
                    unit: "steps",
                    timestamp: statistics.endDate,
                    sourceId: "HealthKit"
                )

                promise(.success([metric]))
            }

            self.healthStore.execute(query)
        }
        .eraseToAnyPublisher()
    }
}

enum HealthKitError: Error {
    case notAvailable
    case managerDeallocated
    case authorizationDenied
}
```

---

## 5. Encryption Service (Data Layer)

### 5.1 Data/Encryption/DataEncryptionService.swift

```swift
import Foundation
import CryptoKit

class DataEncryptionService {
    private let keychain = KeychainManager.shared

    // MARK: - Encryption

    func encrypt(_ data: Data) throws -> EncryptedData {
        let key = try getOrCreateEncryptionKey()
        let symmetricKey = SymmetricKey(data: key)

        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)

        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        return EncryptedData(
            ciphertext: combined,
            algorithm: "AES-256-GCM"
        )
    }

    func encryptString(_ string: String) throws -> EncryptedData {
        guard let data = string.data(using: .utf8) else {
            throw EncryptionError.invalidInput
        }
        return try encrypt(data)
    }

    // MARK: - Decryption

    func decrypt(_ encryptedData: EncryptedData) throws -> Data {
        let key = try getOrCreateEncryptionKey()
        let symmetricKey = SymmetricKey(data: key)

        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData.ciphertext)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    func decryptString(_ encryptedData: EncryptedData) throws -> String {
        let data = try decrypt(encryptedData)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncryptionError.invalidOutput
        }
        return string
    }

    // MARK: - Key Management

    private func getOrCreateEncryptionKey() throws -> Data {
        // Try to retrieve existing key from Keychain
        if let existingKey = try? keychain.retrieveEncryptionKey() {
            return existingKey
        }

        // Generate new 256-bit key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        // Store in Keychain
        try keychain.storeEncryptionKey(keyData)

        return keyData
    }
}

struct EncryptedData: Codable {
    let ciphertext: Data
    let algorithm: String
}

enum EncryptionError: Error {
    case encryptionFailed
    case decryptionFailed
    case invalidInput
    case invalidOutput
    case keyGenerationFailed
}
```

---

## 6. Keychain Manager

### 6.1 Data/DataSources/Local/KeychainManager.swift

```swift
import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    private init() {}

    private let serviceName = "com.healthtracker.app"

    // MARK: - Encryption Key

    func storeEncryptionKey(_ key: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "encryption_key",
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw KeychainError.unableToStore
        }
    }

    func retrieveEncryptionKey() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "encryption_key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.itemNotFound
        }

        return data
    }

    // MARK: - Auth Tokens

    func storeAuthToken(_ token: String, forKey key: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unableToStore
        }
    }

    func retrieveAuthToken(forKey key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.itemNotFound
        }

        return token
    }

    func deleteAuthToken(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete
        }
    }
}

enum KeychainError: Error {
    case unableToStore
    case itemNotFound
    case invalidData
    case unableToDelete
}
```

---

## 7. CoreData Setup with Encryption

### 7.1 Create CoreData Model

1. In Xcode: File → New → File → Data Model
2. Name it `HealthDataModel.xcdatamodeld`
3. Create entity `HealthMetricEntity`:
   - `id`: UUID
   - `type`: String
   - `value`: Double
   - `unit`: String
   - `timestamp`: Date
   - `sourceId`: String
   - `encryptedMetadata`: Binary Data (for encrypted additional data)
   - `isSynced`: Boolean
   - `serverTimestamp`: Date (optional)

### 7.2 Data/DataSources/Local/CoreDataManager.swift

```swift
import CoreData
import Combine

class CoreDataManager {
    static let shared = CoreDataManager()

    private let encryptionService = DataEncryptionService()

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "HealthDataModel")

        // Enable persistent history tracking
        let description = container.persistentStoreDescriptions.first
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // Enable file protection
        description?.setOption(
            FileProtectionType.complete as NSObject,
            forKey: NSPersistentStoreFileProtectionKey
        )

        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("CoreData stack initialization failed: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return container
    }()

    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        persistentContainer.newBackgroundContext()
    }

    // MARK: - Save

    func save(context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    // MARK: - CRUD Operations

    func saveHealthMetric(_ metric: HealthMetric, context: NSManagedObjectContext? = nil) async throws {
        let ctx = context ?? viewContext

        try await ctx.perform {
            let entity = HealthMetricEntity(context: ctx)
            entity.id = metric.id
            entity.type = metric.type.rawValue
            entity.value = metric.value
            entity.unit = metric.unit
            entity.timestamp = metric.timestamp
            entity.sourceId = metric.sourceId
            entity.isSynced = false

            // Encrypt metadata if present
            if let metadata = metric.metadata {
                let jsonData = try JSONEncoder().encode(metadata)
                let encrypted = try self.encryptionService.encrypt(jsonData)
                entity.encryptedMetadata = try JSONEncoder().encode(encrypted)
            }

            try self.save(context: ctx)

            // Create audit log
            self.logAudit(action: .write, dataType: metric.type, success: true)
        }
    }

    func fetchHealthMetrics(
        type: HealthMetricType,
        from startDate: Date,
        to endDate: Date
    ) -> AnyPublisher<[HealthMetric], Error> {
        Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(CoreDataError.managerDeallocated))
                return
            }

            let request: NSFetchRequest<HealthMetricEntity> = HealthMetricEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "type == %@ AND timestamp >= %@ AND timestamp <= %@",
                type.rawValue,
                startDate as NSDate,
                endDate as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

            do {
                let entities = try self.viewContext.fetch(request)
                let metrics = try entities.compactMap { try self.toHealthMetric($0) }
                promise(.success(metrics))
            } catch {
                promise(.failure(error))
            }
        }
        .eraseToAnyPublisher()
    }

    private func toHealthMetric(_ entity: HealthMetricEntity) throws -> HealthMetric? {
        guard let id = entity.id,
              let typeString = entity.type,
              let type = HealthMetricType(rawValue: typeString),
              let unit = entity.unit,
              let timestamp = entity.timestamp,
              let sourceId = entity.sourceId else {
            return nil
        }

        var metadata: [String: String]?
        if let encryptedData = entity.encryptedMetadata {
            let encryptedObj = try JSONDecoder().decode(EncryptedData.self, from: encryptedData)
            let decryptedData = try encryptionService.decrypt(encryptedObj)
            metadata = try JSONDecoder().decode([String: String].self, from: decryptedData)
        }

        return HealthMetric(
            id: id,
            type: type,
            value: entity.value,
            unit: unit,
            timestamp: timestamp,
            sourceId: sourceId,
            metadata: metadata
        )
    }

    // MARK: - Audit Logging

    private func logAudit(action: AuditAction, dataType: HealthMetricType, success: Bool) {
        // Implement audit logging
        print("AUDIT: \(action) on \(dataType) - Success: \(success)")
    }
}

enum CoreDataError: Error {
    case managerDeallocated
    case saveFailed
}

enum AuditAction: String {
    case read, write, delete, sync
}
```

---

## 8. ViewModel Example (Presentation Layer)

### 8.1 Presentation/Screens/HealthMetrics/HeartRateViewModel.swift

```swift
import Foundation
import Combine

@MainActor
class HeartRateViewModel: ObservableObject {
    @Published var heartRateSamples: [HeartRateSample] = []
    @Published var currentHeartRate: Double?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let fetchHeartRateUseCase: FetchHeartRateUseCase
    private let observeHeartRateUseCase: ObserveHeartRateUseCase
    private var cancellables = Set<AnyCancellable>()

    init(
        fetchHeartRateUseCase: FetchHeartRateUseCase,
        observeHeartRateUseCase: ObserveHeartRateUseCase
    ) {
        self.fetchHeartRateUseCase = fetchHeartRateUseCase
        self.observeHeartRateUseCase = observeHeartRateUseCase
    }

    func fetchTodayHeartRate() {
        isLoading = true
        errorMessage = nil

        let today = Calendar.current.startOfDay(for: Date())
        let now = Date()

        fetchHeartRateUseCase.execute(from: today, to: now)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] samples in
                self?.heartRateSamples = samples
                self?.currentHeartRate = samples.first?.beatsPerMinute
            }
            .store(in: &cancellables)
    }

    func startRealtimeMonitoring() {
        observeHeartRateUseCase.execute()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample in
                self?.currentHeartRate = sample.beatsPerMinute
                self?.heartRateSamples.insert(sample, at: 0)
            }
            .store(in: &cancellables)
    }
}
```

---

## 9. Use Case Example (Domain Layer)

### 9.1 Domain/UseCases/FetchHeartRateUseCase.swift

```swift
import Foundation
import Combine

class FetchHeartRateUseCase {
    private let repository: HealthDataRepository

    init(repository: HealthDataRepository) {
        self.repository = repository
    }

    func execute(from startDate: Date, to endDate: Date) -> AnyPublisher<[HeartRateSample], Error> {
        repository.fetchHeartRate(from: startDate, to: endDate)
    }
}

class ObserveHeartRateUseCase {
    private let repository: HealthDataRepository

    init(repository: HealthDataRepository) {
        self.repository = repository
    }

    func execute() -> AnyPublisher<HeartRateSample, Never> {
        repository.observeHeartRate()
    }
}
```

---

## 10. Info.plist Configuration

Add these keys to your `Info.plist`:

```xml
<key>NSHealthShareUsageDescription</key>
<string>We need access to your health data to track your vital signs and provide personalized health insights.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>We need permission to save your health metrics to the Health app.</string>

<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.healthtracker.sync</string>
</array>
```

---

## 11. Dependency Injection Container

### 11.1 App/DependencyContainer.swift

```swift
import Foundation

class DependencyContainer {
    static let shared = DependencyContainer()

    private init() {}

    // MARK: - Managers

    lazy var healthKitManager: HealthKitManager = {
        HealthKitManager()
    }()

    lazy var coreDataManager: CoreDataManager = {
        CoreDataManager.shared
    }()

    lazy var encryptionService: DataEncryptionService = {
        DataEncryptionService()
    }()

    // MARK: - Repositories

    lazy var healthDataRepository: HealthDataRepository = {
        HealthKitRepositoryImpl(
            healthKitManager: healthKitManager,
            coreDataManager: coreDataManager
        )
    }()

    // MARK: - Use Cases

    lazy var fetchHeartRateUseCase: FetchHeartRateUseCase = {
        FetchHeartRateUseCase(repository: healthDataRepository)
    }()

    lazy var observeHeartRateUseCase: ObserveHeartRateUseCase = {
        ObserveHeartRateUseCase(repository: healthDataRepository)
    }()

    // MARK: - ViewModels

    func makeHeartRateViewModel() -> HeartRateViewModel {
        HeartRateViewModel(
            fetchHeartRateUseCase: fetchHeartRateUseCase,
            observeHeartRateUseCase: observeHeartRateUseCase
        )
    }
}
```

---

## 12. SwiftUI View Example

### 12.1 Presentation/Screens/HealthMetrics/HeartRateView.swift

```swift
import SwiftUI

struct HeartRateView: View {
    @StateObject private var viewModel: HeartRateViewModel

    init(viewModel: HeartRateViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 20) {
            if viewModel.isLoading {
                ProgressView("Loading heart rate data...")
            } else if let errorMessage = viewModel.errorMessage {
                ErrorView(message: errorMessage) {
                    viewModel.fetchTodayHeartRate()
                }
            } else {
                currentHeartRateCard
                historyList
            }
        }
        .padding()
        .navigationTitle("Heart Rate")
        .onAppear {
            viewModel.fetchTodayHeartRate()
            viewModel.startRealtimeMonitoring()
        }
    }

    private var currentHeartRateCard: some View {
        VStack {
            Text("Current Heart Rate")
                .font(.headline)
                .foregroundColor(.secondary)

            if let current = viewModel.currentHeartRate {
                Text("\(Int(current))")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(.red)

                Text("BPM")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("--")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 4)
    }

    private var historyList: some View {
        List(viewModel.heartRateSamples, id: \.timestamp) { sample in
            HStack {
                VStack(alignment: .leading) {
                    Text("\(Int(sample.beatsPerMinute)) BPM")
                        .font(.headline)

                    Text(sample.source)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(sample.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ErrorView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)

            Text(message)
                .multilineTextAlignment(.center)

            Button("Retry", action: retryAction)
                .buttonStyle(.bordered)
        }
    }
}
```

---

## 13. Next Implementation Steps

1. **Set up HealthKit authorization** on app launch
2. **Implement remaining metrics** (Steps, Sleep, Oxygen, BP) following the heart rate pattern
3. **Build API client** for backend sync
4. **Add biometric authentication**
5. **Implement background sync tasks**
6. **Write unit tests** for ViewModels and Use Cases
7. **Add UI tests** for critical flows

---

## 14. Quick Start Checklist

- [ ] Create folder structure in Xcode
- [ ] Add Info.plist permissions
- [ ] Create CoreData model
- [ ] Implement HealthKitManager
- [ ] Implement CoreDataManager
- [ ] Implement KeychainManager
- [ ] Implement DataEncryptionService
- [ ] Create domain entities and protocols
- [ ] Implement repository pattern
- [ ] Build first ViewModel (HeartRate)
- [ ] Create SwiftUI views
- [ ] Test HealthKit authorization
- [ ] Test data encryption/decryption

---

**Ready to start building!** Follow the architecture document and this implementation guide step by step.
