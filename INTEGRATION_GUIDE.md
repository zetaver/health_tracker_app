# HealthKit Integration Guide

Complete guide for integrating and using the HealthKit pipeline in your Health Tracker App.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Architecture Overview](#architecture-overview)
3. [Basic Usage](#basic-usage)
4. [Advanced Features](#advanced-features)
5. [Battery Optimization](#battery-optimization)
6. [Error Handling](#error-handling)
7. [Best Practices](#best-practices)

---

## Quick Start

### Step 1: Initialize HealthKitManager

In your main app file or view model:

```swift
import SwiftUI

@main
struct HealthTrackerApp: App {
    @StateObject private var healthManager: HealthKitManager

    init() {
        // Configure HealthKit with your user ID
        let config = HealthKitManager.Configuration.default(userId: "user123")
        _healthManager = StateObject(wrappedValue: HealthKitManager(configuration: config))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthManager)
                .task {
                    // Initialize HealthKit pipeline
                    do {
                        try await healthManager.initialize()
                    } catch {
                        print("HealthKit initialization failed: \(error)")
                    }
                }
        }
    }
}
```

### Step 2: Request Permissions

```swift
struct PermissionView: View {
    @EnvironmentObject var healthManager: HealthKitManager

    var body: some View {
        VStack {
            if healthManager.isAuthorized {
                Text("HealthKit Authorized ✓")
                    .foregroundColor(.green)
            } else {
                Button("Grant HealthKit Permissions") {
                    Task {
                        try? await healthManager.requestPermissions()
                    }
                }
            }
        }
    }
}
```

### Step 3: Fetch Health Data

```swift
struct DashboardView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @State private var todaySteps: Int?
    @State private var heartRateData: [HeartRateMetric] = []

    var body: some View {
        VStack {
            if let steps = todaySteps {
                Text("Steps Today: \(steps)")
            }

            Button("Fetch Health Data") {
                Task {
                    do {
                        todaySteps = try await healthManager.fetchTodaySteps()
                        heartRateData = try await healthManager.fetchTodayHeartRate()
                    } catch {
                        print("Failed to fetch: \(error)")
                    }
                }
            }
        }
        .task {
            // Auto-fetch on appear
            todaySteps = try? await healthManager.fetchTodaySteps()
        }
    }
}
```

---

## Architecture Overview

### Component Structure

```
┌─────────────────────────────────────┐
│      HealthKitManager (Main)        │
│         Coordinator                 │
└───────────┬─────────────────────────┘
            │
    ┌───────┴────────┐
    │                │
┌───▼────────┐  ┌───▼──────────┐
│ Permission │  │ Data Fetcher │
│  Manager   │  │              │
└────────────┘  └──────────────┘
    │                │
┌───▼────────┐  ┌───▼──────────┐
│  Observer  │  │    Cache     │
│  Manager   │  │   Service    │
└────────────┘  └──────────────┘
    │                │
┌───▼────────┐  ┌───▼──────────┐
│   Sync     │  │  API Client  │
│  Service   │  │              │
└────────────┘  └──────────────┘
```

### Data Flow

1. **User Request** → HealthKitManager
2. **Check Cache** → CacheService (if available)
3. **Check Throttle** → CacheService (prevent excessive queries)
4. **Fetch Data** → HealthKitDataFetcher → HealthKit
5. **Cache Result** → CacheService
6. **Background Observer** → Detects new data
7. **Auto Sync** → SyncService → API Client → Backend

---

## Basic Usage

### 1. Requesting Permissions

#### Request All Permissions

```swift
// Request all supported health data types
try await healthManager.requestPermissions()
```

#### Request Specific Permissions

```swift
// Request only specific metrics
let metrics: [HealthMetricType] = [.heartRate, .steps]
try await healthManager.requestPermissions(for: metrics)
```

#### Check Permission Status

```swift
// Check if authorized
if healthManager.isAuthorized {
    print("HealthKit is authorized")
}

// Get detailed permission state
if let state = healthManager.getPermissionState() {
    print("Unauthorized types: \(state.unauthorizedTypes)")
}
```

### 2. Fetching Health Data

#### Heart Rate

```swift
// Fetch heart rate for a date range
let calendar = Calendar.current
let startDate = calendar.date(byAdding: .day, value: -7, to: Date())!
let endDate = Date()

let heartRateData = try await healthManager.fetchHeartRate(
    from: startDate,
    to: endDate,
    useCache: true  // Use cached data if available
)

for metric in heartRateData {
    print("BPM: \(metric.beatsPerMinute) at \(metric.timestamp)")
}
```

#### Steps

```swift
// Total steps today
let todaySteps = try await healthManager.fetchTodaySteps()
print("Steps: \(todaySteps ?? 0)")

// Detailed step metrics
let stepMetrics = try await healthManager.fetchSteps(
    from: startDate,
    to: endDate
)

for metric in stepMetrics {
    print("Steps: \(metric.count) at \(metric.timestamp)")
}
```

#### Blood Pressure

```swift
// Fetch blood pressure readings
let bpData = try await healthManager.fetchBloodPressure(
    from: startDate,
    to: endDate
)

for metric in bpData {
    print("BP: \(metric.systolic)/\(metric.diastolic) mmHg")
    print("Classification: \(metric.classification)")
}
```

#### Sleep

```swift
// Fetch last night's sleep
let sleepData = try await healthManager.fetchLastNightSleep()

let totalSleep = sleepData
    .filter { $0.stage == .asleep || $0.stage == .deep || $0.stage == .rem }
    .reduce(0.0) { $0 + $1.duration }

let hours = totalSleep / 3600
print("Total sleep: \(hours) hours")
```

#### Aggregated Data

```swift
// Fetch aggregated metrics for a week
let aggregated = try await healthManager.fetchAggregatedData(
    from: startDate,
    to: endDate
)

print("Avg Heart Rate: \(aggregated.heartRateAverage ?? 0) BPM")
print("Total Steps: \(aggregated.totalSteps ?? 0)")
print("Sleep Duration: \(aggregated.sleepDuration ?? 0) seconds")
```

### 3. Background Observers

#### Start Observing

```swift
// Start observing specific metrics
let metricsToObserve: [HealthMetricType] = [.heartRate, .steps, .bloodPressure]

try await healthManager.startObserving(metricsToObserve)

// The manager will automatically sync when new data arrives
```

#### Stop Observing

```swift
// Stop all observers
healthManager.stopObserving()
```

### 4. Data Synchronization

#### Manual Sync

```swift
// Sync all data to backend
try await healthManager.syncNow()
```

#### Sync Specific Metrics

```swift
// Sync only heart rate and steps
try await healthManager.syncMetrics([.heartRate, .steps])
```

#### Retry Failed Uploads

```swift
// Retry any failed uploads
try await healthManager.retryFailedUploads()
```

#### Check Sync Status

```swift
let stats = healthManager.getSyncStatistics()
print("Total synced: \(stats.totalSynced)")
print("Last sync: \(stats.lastSync ?? Date.distantPast)")
print("Failed attempts: \(stats.failedAttempts)")
print("Pending batches: \(stats.pendingBatches)")
```

---

## Advanced Features

### Custom Configuration

#### Battery-Aware Configuration

```swift
// Configure based on device battery state
let batteryLevel = UIDevice.current.batteryLevel
let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

let syncConfig: HealthDataSyncService.SyncConfiguration
let cacheConfig: HealthDataCacheService.CacheConfiguration

if isLowPowerMode || batteryLevel < 0.2 {
    // Conservative settings for low battery
    syncConfig = .conservative
    cacheConfig = .aggressive
} else if batteryLevel > 0.5 {
    // Aggressive settings when battery is good
    syncConfig = .aggressive
    cacheConfig = .realtime
} else {
    // Default balanced settings
    syncConfig = .default
    cacheConfig = .default
}

let config = HealthKitManager.Configuration(
    userId: "user123",
    enableAutoSync: true,
    syncConfiguration: syncConfig,
    cacheConfiguration: cacheConfig,
    observedMetrics: [.heartRate, .steps, .bloodPressure, .sleep]
)

let healthManager = HealthKitManager(configuration: config)
```

#### WiFi-Only Sync

```swift
// Configure to sync only on WiFi
var syncConfig = HealthDataSyncService.SyncConfiguration.default
syncConfig.wifiOnly = true
syncConfig.minimumBatteryLevel = 0.3

let config = HealthKitManager.Configuration(
    userId: "user123",
    enableAutoSync: true,
    syncConfiguration: syncConfig,
    cacheConfiguration: .default,
    observedMetrics: [.heartRate, .steps]
)
```

### Cache Management

#### Clear Cache

```swift
// Clear all cached data
await healthManager.clearCache()
```

#### Cache Statistics

```swift
let cacheStats = await healthManager.getCacheStatistics()
print("Cache hit rate: \(cacheStats.hitRate * 100)%")
print("Throttle rate: \(cacheStats.throttleRate * 100)%")
print("Total queries: \(cacheStats.totalQueries)")
```

#### Bypass Cache

```swift
// Force fresh data from HealthKit (bypass cache)
let freshData = try await healthManager.fetchHeartRate(
    from: startDate,
    to: endDate,
    useCache: false  // Don't use cache
)
```

### Custom API Configuration

```swift
// Configure API client with custom settings
let apiConfig = HealthAPIClient.APIConfiguration(
    baseURL: URL(string: "https://your-api.example.com")!,
    apiKey: "your_secure_api_key",
    timeout: 30,
    maxRetries: 3,
    enableEncryption: true,
    enableCertificatePinning: true
)

let apiClient = HealthAPIClient(configuration: apiConfig)

// Use custom API client
let syncService = HealthDataSyncService(
    userId: "user123",
    apiClient: apiClient,
    configuration: .default
)
```

---

## Battery Optimization

### Automatic Optimization

The pipeline automatically optimizes battery usage through:

1. **Intelligent Caching** - Reduces HealthKit queries
2. **Throttling** - Prevents excessive data fetches
3. **Batched Uploads** - Groups multiple data points
4. **Background Delivery** - Efficient HealthKit updates
5. **Adaptive Sync** - Adjusts frequency based on battery

### Manual Optimization

#### Throttle Configuration

```swift
// Aggressive throttling for battery saving
let cacheConfig = HealthDataCacheService.CacheConfiguration(
    cacheDuration: 900,      // 15 minutes
    throttleInterval: 180,   // 3 minutes minimum between fetches
    maxCacheSize: 500,
    persistToDisk: true
)
```

#### Sync Frequency

```swift
// Reduce sync frequency to save battery
let syncConfig = HealthDataSyncService.SyncConfiguration(
    maxBatchSize: 50,
    syncInterval: 7200,  // Sync every 2 hours instead of 1
    wifiOnly: true,
    minimumBatteryLevel: 0.3,
    backgroundSyncEnabled: false  // Disable background sync
)
```

#### Selective Observation

```swift
// Only observe critical metrics
let criticalMetrics: [HealthMetricType] = [.heartRate]  // Only heart rate
try await healthManager.startObserving(criticalMetrics)
```

---

## Error Handling

### Common Errors

```swift
do {
    try await healthManager.fetchHeartRate(from: startDate, to: endDate)
} catch HealthKitError.notAvailable {
    // HealthKit not available on this device
    showAlert("HealthKit is not available on this device")

} catch HealthKitError.permissionDenied(let metricType) {
    // Permission denied for specific metric
    showAlert("Permission denied for \(metricType.displayName)")
    // Prompt user to grant permission

} catch HealthKitError.queryFailed(let underlying) {
    // Query failed
    print("Query failed: \(underlying.localizedDescription)")

} catch ThrottleError.rateLimited(let remainingTime) {
    // Request was throttled
    showAlert("Please wait \(Int(remainingTime)) seconds")

} catch {
    // Generic error handling
    print("Error: \(error.localizedDescription)")
}
```

### Sync Errors

```swift
do {
    try await healthManager.syncNow()
} catch SyncError.lowBattery(let level) {
    // Battery too low for sync
    showAlert("Battery too low (\(Int(level * 100))%)")

} catch SyncError.wifiRequired {
    // WiFi required but not connected
    showAlert("Please connect to WiFi to sync")

} catch SyncError.uploadFailed(let message) {
    // Upload to backend failed
    print("Upload failed: \(message)")
    // Will auto-retry later

} catch {
    print("Sync error: \(error)")
}
```

---

## Best Practices

### 1. Initialize Early

```swift
// Initialize HealthKit as early as possible
.task {
    try? await healthManager.initialize()
}
```

### 2. Handle Permissions Gracefully

```swift
// Check permissions before fetching
if !healthManager.isAuthorized {
    // Show permission request UI
    showPermissionPrompt()
} else {
    // Fetch data
    fetchHealthData()
}
```

### 3. Use Caching Wisely

```swift
// Use cache for UI display
let cachedData = try await healthManager.fetchHeartRate(
    from: startDate,
    to: endDate,
    useCache: true  // Fast, battery-friendly
)

// Bypass cache for critical updates
let freshData = try await healthManager.fetchHeartRate(
    from: startDate,
    to: endDate,
    useCache: false  // Fresh data from HealthKit
)
```

### 4. Monitor Battery State

```swift
// Adjust behavior based on battery
UIDevice.current.isBatteryMonitoringEnabled = true

NotificationCenter.default.addObserver(
    forName: UIDevice.batteryLevelDidChangeNotification,
    object: nil,
    queue: .main
) { _ in
    let level = UIDevice.current.batteryLevel
    if level < 0.2 {
        // Switch to conservative mode
        healthManager.stopObserving()
    }
}
```

### 5. Sync During Idle Time

```swift
// Sync when app goes to background
.onReceive(NotificationCenter.default.publisher(
    for: UIApplication.didEnterBackgroundNotification
)) { _ in
    Task {
        try? await healthManager.syncNow()
    }
}
```

### 6. Secure API Keys

```swift
// NEVER hardcode API keys
// ❌ Bad
let apiKey = "sk_live_abc123"

// ✅ Good - Use environment variables or secure storage
let apiKey = ProcessInfo.processInfo.environment["HEALTH_API_KEY"] ?? ""

// ✅ Better - Use Keychain
let apiKey = KeychainHelper.retrieve(key: "health_api_key") ?? ""
```

### 7. Handle Network Errors

```swift
// Sync failures are automatically retried
// Access pending batches for manual retry
let stats = healthManager.getSyncStatistics()
if stats.pendingBatches > 0 {
    // Retry when network is available
    try? await healthManager.retryFailedUploads()
}
```

---

## Example: Complete ViewModel

```swift
import SwiftUI
import Combine

@MainActor
class HealthDashboardViewModel: ObservableObject {
    @Published var todaySteps: Int = 0
    @Published var avgHeartRate: Double = 0
    @Published var lastNightSleep: TimeInterval = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let healthManager: HealthKitManager

    init(healthManager: HealthKitManager) {
        self.healthManager = healthManager
    }

    func loadDashboardData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch all metrics in parallel
            async let steps = healthManager.fetchTodaySteps()
            async let heartRate = healthManager.fetchAggregatedData(
                from: Calendar.current.startOfDay(for: Date()),
                to: Date()
            )
            async let sleep = healthManager.fetchLastNightSleep()

            // Wait for all results
            let (stepsResult, hrResult, sleepResult) = try await (steps, heartRate, sleep)

            // Update UI
            self.todaySteps = stepsResult ?? 0
            self.avgHeartRate = hrResult.heartRateAverage ?? 0

            let totalSleep = sleepResult
                .filter { $0.stage == .asleep || $0.stage == .deep || $0.stage == .rem }
                .reduce(0.0) { $0 + $1.duration }
            self.lastNightSleep = totalSleep

        } catch {
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func syncData() async {
        do {
            try await healthManager.syncNow()
        } catch {
            errorMessage = "Sync failed: \(error.localizedDescription)"
        }
    }
}
```

---

## Next Steps

1. ✅ Configure Info.plist (see [HEALTHKIT_CONFIGURATION.md](HEALTHKIT_CONFIGURATION.md))
2. ✅ Enable HealthKit capability in Xcode
3. ✅ Initialize HealthKitManager in your app
4. ✅ Request permissions from user
5. ✅ Start fetching and displaying health data
6. ✅ Configure backend API endpoint
7. ✅ Test on a real device

For configuration details, see [HEALTHKIT_CONFIGURATION.md](HEALTHKIT_CONFIGURATION.md).
