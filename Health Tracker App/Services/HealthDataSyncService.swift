//
//  HealthDataSyncService.swift
//  Health Tracker App
//
//  Coordinates batched uploads and synchronization of health data
//  Implements smart batching, retry logic, and battery-aware syncing
//

import Foundation
import UIKit

/// Manages synchronization of health data with backend server
@MainActor
class HealthDataSyncService {

    // MARK: - Sync Configuration

    struct SyncConfiguration {
        /// Maximum number of data points per batch
        let maxBatchSize: Int

        /// Time interval between automatic syncs (in seconds)
        let syncInterval: TimeInterval

        /// Whether to sync only on WiFi
        let wifiOnly: Bool

        /// Minimum battery level required for sync (0.0 - 1.0)
        let minimumBatteryLevel: Float

        /// Whether to sync in background
        let backgroundSyncEnabled: Bool

        static let `default` = SyncConfiguration(
            maxBatchSize: 100,
            syncInterval: 3600, // 1 hour
            wifiOnly: false,
            minimumBatteryLevel: 0.2,
            backgroundSyncEnabled: true
        )

        static let conservative = SyncConfiguration(
            maxBatchSize: 50,
            syncInterval: 7200, // 2 hours
            wifiOnly: true,
            minimumBatteryLevel: 0.3,
            backgroundSyncEnabled: false
        )

        static let aggressive = SyncConfiguration(
            maxBatchSize: 200,
            syncInterval: 900, // 15 minutes
            wifiOnly: false,
            minimumBatteryLevel: 0.1,
            backgroundSyncEnabled: true
        )
    }

    // MARK: - Sync State

    enum SyncState {
        case idle
        case syncing
        case success
        case failed(Error)

        var isActive: Bool {
            if case .syncing = self {
                return true
            }
            return false
        }
    }

    // MARK: - Properties

    private let apiClient: HealthAPIClient
    private let dataFetcher: HealthKitDataFetcher
    private let cacheService: HealthDataCacheService
    private let configuration: SyncConfiguration

    private(set) var currentState: SyncState = .idle
    private var syncTimer: Timer?
    private var pendingBatches: [HealthDataBatch] = []
    private var userId: String

    // Sync statistics
    private(set) var totalSyncedDataPoints: Int = 0
    private(set) var lastSuccessfulSync: Date?
    private(set) var failedSyncAttempts: Int = 0

    // MARK: - Initialization

    init(
        userId: String,
        apiClient: HealthAPIClient = HealthAPIClient(),
        dataFetcher: HealthKitDataFetcher = HealthKitDataFetcher(),
        cacheService: HealthDataCacheService = HealthDataCacheService(),
        configuration: SyncConfiguration = .default
    ) {
        self.userId = userId
        self.apiClient = apiClient
        self.dataFetcher = dataFetcher
        self.cacheService = cacheService
        self.configuration = configuration

        setupAutomaticSync()
    }

    // MARK: - Public Sync Methods

    /// Performs a manual sync of all health data
    func syncNow() async throws {
        guard !currentState.isActive else {
            print("Sync already in progress")
            return
        }

        currentState = .syncing

        do {
            // Check if conditions allow syncing
            try await validateSyncConditions()

            // Fetch data from HealthKit
            let batch = try await fetchHealthDataForSync()

            // Upload batch to backend
            try await uploadBatch(batch)

            // Update state
            currentState = .success
            lastSuccessfulSync = Date()
            failedSyncAttempts = 0

        } catch {
            currentState = .failed(error)
            failedSyncAttempts += 1
            throw error
        }
    }

    /// Syncs specific metric types
    /// - Parameter metricTypes: Array of metric types to sync
    func syncMetrics(_ metricTypes: [HealthMetricType]) async throws {
        guard !currentState.isActive else {
            print("Sync already in progress")
            return
        }

        currentState = .syncing

        do {
            // Check if conditions allow syncing
            try await validateSyncConditions()

            // Fetch specific metrics
            let batch = try await fetchMetrics(metricTypes)

            // Upload batch to backend
            try await uploadBatch(batch)

            // Update state
            currentState = .success
            lastSuccessfulSync = Date()
            failedSyncAttempts = 0

        } catch {
            currentState = .failed(error)
            failedSyncAttempts += 1
            throw error
        }
    }

    /// Retries failed uploads from pending batches
    func retryFailedUploads() async throws {
        guard !pendingBatches.isEmpty else {
            print("No pending batches to retry")
            return
        }

        currentState = .syncing

        var successCount = 0
        var errors: [Error] = []

        for batch in pendingBatches {
            do {
                try await uploadBatch(batch)
                successCount += 1
            } catch {
                errors.append(error)
            }
        }

        // Remove successfully uploaded batches
        if successCount > 0 {
            pendingBatches.removeFirst(successCount)
        }

        if errors.isEmpty {
            currentState = .success
            lastSuccessfulSync = Date()
        } else {
            currentState = .failed(errors.first!)
            throw SyncError.partialFailure(successCount: successCount, errors: errors)
        }
    }

    // MARK: - Automatic Sync

    private func setupAutomaticSync() {
        guard configuration.syncInterval > 0 else { return }

        syncTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.syncInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                do {
                    try await self.syncNow()
                } catch {
                    print("Automatic sync failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Stops automatic synchronization
    func stopAutomaticSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Data Fetching

    private func fetchHealthDataForSync() async throws -> HealthDataBatch {
        let endDate = Date()
        let startDate: Date

        // Determine start date based on last sync
        if let lastSync = lastSuccessfulSync {
            startDate = lastSync
        } else {
            // First sync - get last 7 days
            startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate
        }

        // Fetch all metric types
        return try await fetchMetrics(HealthMetricType.allCases, from: startDate, to: endDate)
    }

    private func fetchMetrics(_ metricTypes: [HealthMetricType]) async throws -> HealthDataBatch {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -1, to: endDate) ?? endDate
        return try await fetchMetrics(metricTypes, from: startDate, to: endDate)
    }

    private func fetchMetrics(
        _ metricTypes: [HealthMetricType],
        from startDate: Date,
        to endDate: Date
    ) async throws -> HealthDataBatch {
        var dataPoints: [HealthDataBatch.HealthDataPoint] = []

        for metricType in metricTypes {
            do {
                let points = try await fetchDataPoints(for: metricType, from: startDate, to: endDate)
                dataPoints.append(contentsOf: points)
            } catch {
                print("Failed to fetch \(metricType.displayName): \(error.localizedDescription)")
                // Continue with other metrics
            }
        }

        return HealthDataBatch(userId: userId, dataPoints: dataPoints)
    }

    private func fetchDataPoints(
        for metricType: HealthMetricType,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [HealthDataBatch.HealthDataPoint] {
        var dataPoints: [HealthDataBatch.HealthDataPoint] = []

        switch metricType {
        case .heartRate:
            let metrics = try await dataFetcher.fetchHeartRate(from: startDate, to: endDate, limit: configuration.maxBatchSize)
            for metric in metrics {
                if let jsonData = try? JSONEncoder().encode(metric),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    let point = HealthDataBatch.HealthDataPoint(
                        metricType: metricType.rawValue,
                        timestamp: metric.timestamp,
                        value: jsonString,
                        deviceInfo: createDeviceInfo(from: metric.sourceDevice)
                    )
                    dataPoints.append(point)
                }
            }

        case .steps:
            let metrics = try await dataFetcher.fetchSteps(from: startDate, to: endDate)
            for metric in metrics {
                if let jsonData = try? JSONEncoder().encode(metric),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    let point = HealthDataBatch.HealthDataPoint(
                        metricType: metricType.rawValue,
                        timestamp: metric.timestamp,
                        value: jsonString,
                        deviceInfo: createDeviceInfo(from: metric.sourceDevice)
                    )
                    dataPoints.append(point)
                }
            }

        case .bloodPressure:
            let metrics = try await dataFetcher.fetchBloodPressure(from: startDate, to: endDate, limit: configuration.maxBatchSize)
            for metric in metrics {
                if let jsonData = try? JSONEncoder().encode(metric),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    let point = HealthDataBatch.HealthDataPoint(
                        metricType: metricType.rawValue,
                        timestamp: metric.timestamp,
                        value: jsonString,
                        deviceInfo: createDeviceInfo(from: metric.sourceDevice)
                    )
                    dataPoints.append(point)
                }
            }

        case .sleep:
            let metrics = try await dataFetcher.fetchSleep(from: startDate, to: endDate)
            for metric in metrics {
                if let jsonData = try? JSONEncoder().encode(metric),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    let point = HealthDataBatch.HealthDataPoint(
                        metricType: metricType.rawValue,
                        timestamp: metric.timestamp,
                        value: jsonString,
                        deviceInfo: createDeviceInfo(from: metric.sourceDevice)
                    )
                    dataPoints.append(point)
                }
            }

        default:
            break
        }

        return dataPoints
    }

    private func createDeviceInfo(from deviceName: String?) -> HealthDataBatch.DeviceInfo? {
        guard let name = deviceName else { return nil }

        return HealthDataBatch.DeviceInfo(
            name: name,
            model: UIDevice.current.model,
            manufacturer: "Apple"
        )
    }

    // MARK: - Upload Methods

    private func uploadBatch(_ batch: HealthDataBatch) async throws {
        // Split into smaller batches if needed
        let batches = splitBatch(batch, maxSize: configuration.maxBatchSize)

        for singleBatch in batches {
            let response = try await apiClient.uploadBatch(singleBatch, userId: userId)

            if !response.success {
                // Add to pending batches for retry
                pendingBatches.append(singleBatch)
                throw SyncError.uploadFailed(message: response.message ?? "Unknown error")
            } else {
                totalSyncedDataPoints += singleBatch.dataPoints.count
            }
        }
    }

    private func splitBatch(_ batch: HealthDataBatch, maxSize: Int) -> [HealthDataBatch] {
        guard batch.dataPoints.count > maxSize else {
            return [batch]
        }

        var batches: [HealthDataBatch] = []
        let chunks = stride(from: 0, to: batch.dataPoints.count, by: maxSize)

        for start in chunks {
            let end = min(start + maxSize, batch.dataPoints.count)
            let chunk = Array(batch.dataPoints[start..<end])
            let newBatch = HealthDataBatch(userId: userId, dataPoints: chunk)
            batches.append(newBatch)
        }

        return batches
    }

    // MARK: - Sync Validation

    private func validateSyncConditions() async throws {
        // Check battery level
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel

        if batteryLevel >= 0 && batteryLevel < configuration.minimumBatteryLevel {
            throw SyncError.lowBattery(level: batteryLevel)
        }

        // Check network connectivity if WiFi-only is required
        if configuration.wifiOnly {
            let isWiFi = await checkWiFiConnection()
            if !isWiFi {
                throw SyncError.wifiRequired
            }
        }
    }

    private func checkWiFiConnection() async -> Bool {
        // Simplified check - in production, use NWPathMonitor
        // This is a placeholder implementation
        return true
    }

    // MARK: - Statistics

    func getSyncStatistics() -> SyncStatistics {
        return SyncStatistics(
            totalSynced: totalSyncedDataPoints,
            lastSync: lastSuccessfulSync,
            failedAttempts: failedSyncAttempts,
            pendingBatches: pendingBatches.count,
            currentState: currentState
        )
    }

    struct SyncStatistics {
        let totalSynced: Int
        let lastSync: Date?
        let failedAttempts: Int
        let pendingBatches: Int
        let currentState: SyncState
    }
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case lowBattery(level: Float)
    case wifiRequired
    case uploadFailed(message: String)
    case partialFailure(successCount: Int, errors: [Error])
    case noDataToSync

    var errorDescription: String? {
        switch self {
        case .lowBattery(let level):
            return "Battery too low for sync (\(Int(level * 100))%)"
        case .wifiRequired:
            return "WiFi connection required for sync"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .partialFailure(let successCount, let errors):
            return "Partial sync failure: \(successCount) succeeded, \(errors.count) failed"
        case .noDataToSync:
            return "No data available to sync"
        }
    }
}
