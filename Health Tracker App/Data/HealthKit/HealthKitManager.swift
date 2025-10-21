//
//  HealthKitManager.swift
//  Health Tracker App
//
//  Main coordinator for all HealthKit operations
//  Provides a unified interface for the entire HealthKit integration pipeline
//

import Foundation
import HealthKit
import Combine

/// Main coordinator for HealthKit integration
/// Provides a unified interface for permissions, data fetching, observing, and syncing
@MainActor
class HealthKitManager: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var permissionState: HealthKitPermissionState?
    @Published private(set) var syncState: HealthDataSyncService.SyncState = .idle
    @Published private(set) var isObserving: Bool = false

    // MARK: - Managers and Services

    private let permissionManager: HealthKitPermissionManager
    private let dataFetcher: HealthKitDataFetcher
    private let observerManager: HealthKitObserverManager
    private let syncService: HealthDataSyncService
    private let cacheService: HealthDataCacheService

    private let healthStore: HKHealthStore

    // MARK: - Configuration

    struct Configuration {
        let userId: String
        let enableAutoSync: Bool
        let syncConfiguration: HealthDataSyncService.SyncConfiguration
        let cacheConfiguration: HealthDataCacheService.CacheConfiguration
        let observedMetrics: [HealthMetricType]

        static func `default`(userId: String) -> Configuration {
            return Configuration(
                userId: userId,
                enableAutoSync: true,
                syncConfiguration: .default,
                cacheConfiguration: .default,
                observedMetrics: [.heartRate, .steps, .bloodPressure, .sleep]
            )
        }
    }

    private let configuration: Configuration

    // MARK: - Initialization

    init(configuration: Configuration) {
        self.configuration = configuration
        self.healthStore = HKHealthStore()

        // Initialize all managers and services
        self.permissionManager = HealthKitPermissionManager(healthStore: healthStore)
        self.dataFetcher = HealthKitDataFetcher(healthStore: healthStore)
        self.observerManager = HealthKitObserverManager(healthStore: healthStore)
        self.cacheService = HealthDataCacheService(configuration: configuration.cacheConfiguration)
        self.syncService = HealthDataSyncService(
            userId: configuration.userId,
            cacheService: cacheService,
            configuration: configuration.syncConfiguration
        )

        // Check initial authorization state
        updatePermissionState()
    }

    // MARK: - Setup and Initialization

    /// Initializes the complete HealthKit pipeline
    /// Call this method during app startup or when user opts in
    func initialize() async throws {
        // 1. Request permissions
        try await requestPermissions()

        // 2. Start observing health data if enabled
        if configuration.observedMetrics.isEmpty == false {
            try await startObserving(configuration.observedMetrics)
        }

        // 3. Perform initial sync
        if configuration.enableAutoSync {
            try? await syncService.syncNow()
        }

        // 4. Register background tasks
        HealthKitObserverManager.registerBackgroundTask()
    }

    // MARK: - Permission Management

    /// Requests authorization for all required health data types
    func requestPermissions() async throws {
        let success = try await permissionManager.requestAuthorization()

        await MainActor.run {
            self.isAuthorized = success
            self.updatePermissionState()
        }
    }

    /// Requests authorization for specific metric types
    func requestPermissions(for metricTypes: [HealthMetricType]) async throws {
        let success = try await permissionManager.requestAuthorization(for: metricTypes)

        await MainActor.run {
            self.isAuthorized = success
            self.updatePermissionState()
        }
    }

    /// Updates the current permission state
    private func updatePermissionState() {
        let state = HealthKitPermissionState(
            isAvailable: HealthKitPermissionManager.isHealthKitAvailable,
            hasAllPermissions: permissionManager.hasAllPermissions(),
            unauthorizedTypes: permissionManager.unauthorizedMetricTypes()
        )
        self.permissionState = state
        self.isAuthorized = state.hasAllPermissions
    }

    // MARK: - Data Fetching (with Caching)

    /// Fetches heart rate data with intelligent caching
    func fetchHeartRate(from startDate: Date, to endDate: Date, useCache: Bool = true) async throws -> [HeartRateMetric] {
        // Check cache first if enabled
        if useCache, let cached = await cacheService.getCachedHeartRate() {
            return cached
        }

        // Check throttling
        if await cacheService.shouldThrottle(.heartRate) {
            // Return cached data or throw error
            if let cached = await cacheService.getCachedHeartRate() {
                return cached
            }
            let remaining = await cacheService.getRemainingThrottleTime(for: .heartRate)
            throw HealthKitError.queryFailed(underlying: ThrottleError.rateLimited(remainingTime: remaining))
        }

        // Fetch from HealthKit
        let metrics = try await dataFetcher.fetchHeartRate(from: startDate, to: endDate)

        // Cache results
        await cacheService.cacheHeartRate(metrics)
        await cacheService.recordFetch(for: .heartRate)

        return metrics
    }

    /// Fetches step count data with intelligent caching
    func fetchSteps(from startDate: Date, to endDate: Date, useCache: Bool = true) async throws -> [StepsMetric] {
        // Check cache first if enabled
        if useCache, let cached = await cacheService.getCachedSteps() {
            return cached
        }

        // Check throttling
        if await cacheService.shouldThrottle(.steps) {
            if let cached = await cacheService.getCachedSteps() {
                return cached
            }
            let remaining = await cacheService.getRemainingThrottleTime(for: .steps)
            throw HealthKitError.queryFailed(underlying: ThrottleError.rateLimited(remainingTime: remaining))
        }

        // Fetch from HealthKit
        let metrics = try await dataFetcher.fetchSteps(from: startDate, to: endDate)

        // Cache results
        await cacheService.cacheSteps(metrics)
        await cacheService.recordFetch(for: .steps)

        return metrics
    }

    /// Fetches blood pressure data with intelligent caching
    func fetchBloodPressure(from startDate: Date, to endDate: Date, useCache: Bool = true) async throws -> [BloodPressureMetric] {
        // Check cache first if enabled
        if useCache, let cached = await cacheService.getCachedBloodPressure() {
            return cached
        }

        // Check throttling
        if await cacheService.shouldThrottle(.bloodPressure) {
            if let cached = await cacheService.getCachedBloodPressure() {
                return cached
            }
            let remaining = await cacheService.getRemainingThrottleTime(for: .bloodPressure)
            throw HealthKitError.queryFailed(underlying: ThrottleError.rateLimited(remainingTime: remaining))
        }

        // Fetch from HealthKit
        let metrics = try await dataFetcher.fetchBloodPressure(from: startDate, to: endDate)

        // Cache results
        await cacheService.cacheBloodPressure(metrics)
        await cacheService.recordFetch(for: .bloodPressure)

        return metrics
    }

    /// Fetches sleep data with intelligent caching
    func fetchSleep(from startDate: Date, to endDate: Date, useCache: Bool = true) async throws -> [SleepMetric] {
        // Check cache first if enabled
        if useCache, let cached = await cacheService.getCachedSleep() {
            return cached
        }

        // Check throttling
        if await cacheService.shouldThrottle(.sleep) {
            if let cached = await cacheService.getCachedSleep() {
                return cached
            }
            let remaining = await cacheService.getRemainingThrottleTime(for: .sleep)
            throw HealthKitError.queryFailed(underlying: ThrottleError.rateLimited(remainingTime: remaining))
        }

        // Fetch from HealthKit
        let metrics = try await dataFetcher.fetchSleep(from: startDate, to: endDate)

        // Cache results
        await cacheService.cacheSleep(metrics)
        await cacheService.recordFetch(for: .sleep)

        return metrics
    }

    /// Fetches aggregated health data for a time period
    func fetchAggregatedData(from startDate: Date, to endDate: Date, useCache: Bool = true) async throws -> AggregatedHealthData {
        let cacheKey = "\(startDate.timeIntervalSince1970)-\(endDate.timeIntervalSince1970)"

        // Check cache first if enabled
        if useCache, let cached = await cacheService.getCachedAggregatedData(key: cacheKey) {
            return cached
        }

        // Fetch from HealthKit
        let data = try await dataFetcher.fetchAggregatedData(from: startDate, to: endDate)

        // Cache results
        await cacheService.cacheAggregatedData(data, key: cacheKey)

        return data
    }

    // MARK: - Convenience Methods

    /// Fetches today's heart rate data
    func fetchTodayHeartRate() async throws -> [HeartRateMetric] {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        return try await fetchHeartRate(from: startDate, to: endDate)
    }

    /// Fetches today's step count
    func fetchTodaySteps() async throws -> Int? {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        return try await dataFetcher.fetchTotalSteps(from: startDate, to: endDate)
    }

    /// Fetches last night's sleep data
    func fetchLastNightSleep() async throws -> [SleepMetric] {
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let startDate = calendar.startOfDay(for: yesterday)
        let endDate = calendar.startOfDay(for: now)
        return try await fetchSleep(from: startDate, to: endDate)
    }

    // MARK: - Observer Management

    /// Starts observing health data updates
    func startObserving(_ metricTypes: [HealthMetricType]) async throws {
        try observerManager.startObservingMultiple(metricTypes) { [weak self] metricType, result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                switch result {
                case .success:
                    print("Received update for \(metricType.displayName)")
                    // Trigger sync for updated data
                    if self.configuration.enableAutoSync {
                        try? await self.syncService.syncMetrics([metricType])
                    }

                case .failure(let error):
                    print("Observer error for \(metricType.displayName): \(error.localizedDescription)")
                }
            }
        }

        self.isObserving = true
    }

    /// Stops observing all health data updates
    func stopObserving() {
        observerManager.stopAllObservers()
        self.isObserving = false
    }

    // MARK: - Sync Management

    /// Manually triggers a sync
    func syncNow() async throws {
        try await syncService.syncNow()
        self.syncState = syncService.currentState
    }

    /// Syncs specific metric types
    func syncMetrics(_ metricTypes: [HealthMetricType]) async throws {
        try await syncService.syncMetrics(metricTypes)
        self.syncState = syncService.currentState
    }

    /// Retries failed uploads
    func retryFailedUploads() async throws {
        try await syncService.retryFailedUploads()
        self.syncState = syncService.currentState
    }

    /// Gets sync statistics
    func getSyncStatistics() -> HealthDataSyncService.SyncStatistics {
        return syncService.getSyncStatistics()
    }

    // MARK: - Cache Management

    /// Clears all cached data
    func clearCache() async {
        await cacheService.clearAllCache()
    }

    /// Gets cache statistics
    func getCacheStatistics() async -> HealthDataCacheService.CacheStatistics {
        return await cacheService.getStatistics()
    }

    // MARK: - Utility Methods

    /// Checks if HealthKit is available on this device
    static var isHealthKitAvailable: Bool {
        return HealthKitPermissionManager.isHealthKitAvailable
    }

    /// Gets the current health permission state
    func getPermissionState() -> HealthKitPermissionState? {
        return permissionState
    }
}

// MARK: - Throttle Error

enum ThrottleError: LocalizedError {
    case rateLimited(remainingTime: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let remaining):
            return "Rate limited. Please wait \(Int(remaining)) seconds before retrying."
        }
    }
}
