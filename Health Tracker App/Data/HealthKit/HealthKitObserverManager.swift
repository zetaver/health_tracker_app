//
//  HealthKitObserverManager.swift
//  Health Tracker App
//
//  Manages background observers for HealthKit data updates
//

import Foundation
import HealthKit
import BackgroundTasks

/// Manages HealthKit observers for real-time and background data updates
@MainActor
class HealthKitObserverManager {

    // MARK: - Properties

    private let healthStore: HKHealthStore
    private var activeObservers: [HealthMetricType: HKObserverQuery] = [:]
    private var updateHandlers: [HealthMetricType: (Result<Void, Error>) -> Void] = [:]
    private var queryAnchors: [HealthMetricType: HKQueryAnchor] = [:]

    // Background task identifier
    static let backgroundTaskIdentifier = "com.health.tracker.healthkit.sync"

    // MARK: - Initialization

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
        loadAnchors()
    }

    // MARK: - Observer Setup

    /// Starts observing a specific health metric type for updates
    /// - Parameters:
    ///   - metricType: The metric type to observe
    ///   - updateHandler: Closure called when updates are detected
    func startObserving(
        _ metricType: HealthMetricType,
        updateHandler: @escaping (Result<Void, Error>) -> Void
    ) throws {
        guard let sampleType = metricType.healthKitIdentifier as? HKSampleType else {
            throw HealthKitError.invalidData
        }

        // Store the update handler
        updateHandlers[metricType] = updateHandler

        // Create observer query
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let error = error {
                    self.updateHandlers[metricType]?(.failure(HealthKitError.queryFailed(underlying: error)))
                    completionHandler()
                    return
                }

                // Notify handler of new data
                self.updateHandlers[metricType]?(.success(()))

                // Call completion handler to let HealthKit know we're done
                completionHandler()
            }
        }

        // Execute the query
        healthStore.execute(query)

        // Store the query for later cleanup
        activeObservers[metricType] = query

        // Enable background delivery for this type
        try enableBackgroundDelivery(for: sampleType)
    }

    /// Starts observing multiple health metric types
    /// - Parameters:
    ///   - metricTypes: Array of metric types to observe
    ///   - updateHandler: Closure called when updates are detected for any type
    func startObservingMultiple(
        _ metricTypes: [HealthMetricType],
        updateHandler: @escaping (HealthMetricType, Result<Void, Error>) -> Void
    ) throws {
        for metricType in metricTypes {
            try startObserving(metricType) { result in
                updateHandler(metricType, result)
            }
        }
    }

    /// Stops observing a specific health metric type
    /// - Parameter metricType: The metric type to stop observing
    func stopObserving(_ metricType: HealthMetricType) {
        guard let query = activeObservers[metricType],
              let sampleType = metricType.healthKitIdentifier as? HKSampleType else {
            return
        }

        healthStore.stop(query)
        activeObservers.removeValue(forKey: metricType)
        updateHandlers.removeValue(forKey: metricType)

        // Disable background delivery
        disableBackgroundDelivery(for: sampleType)
    }

    /// Stops all active observers
    func stopAllObservers() {
        for metricType in activeObservers.keys {
            stopObserving(metricType)
        }
    }

    // MARK: - Background Delivery

    /// Enables background delivery for a specific sample type
    /// - Parameter sampleType: The sample type to enable background delivery for
    private func enableBackgroundDelivery(for sampleType: HKSampleType) throws {
        healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { success, error in
            if let error = error {
                print("Failed to enable background delivery: \(error.localizedDescription)")
            } else if success {
                print("Background delivery enabled for \(sampleType.identifier)")
            }
        }
    }

    /// Disables background delivery for a specific sample type
    /// - Parameter sampleType: The sample type to disable background delivery for
    private func disableBackgroundDelivery(for sampleType: HKSampleType) {
        healthStore.disableBackgroundDelivery(for: sampleType) { success, error in
            if let error = error {
                print("Failed to disable background delivery: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Anchor-Based Queries

    /// Fetches new data since last query using anchored queries
    /// - Parameters:
    ///   - metricType: The metric type to fetch
    ///   - completion: Closure called with new samples and updated anchor
    func fetchNewData(
        for metricType: HealthMetricType,
        completion: @escaping (Result<[HKSample], Error>) -> Void
    ) {
        guard let sampleType = metricType.healthKitIdentifier as? HKSampleType else {
            completion(.failure(HealthKitError.invalidData))
            return
        }

        let anchor = queryAnchors[metricType]

        let query = HKAnchoredObjectQuery(
            type: sampleType,
            predicate: nil,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samplesOrNil, deletedObjectsOrNil, newAnchor, errorOrNil in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let error = errorOrNil {
                    completion(.failure(HealthKitError.queryFailed(underlying: error)))
                    return
                }

                let samples = samplesOrNil ?? []

                // Save the new anchor for next query
                if let newAnchor = newAnchor {
                    self.queryAnchors[metricType] = newAnchor
                    self.saveAnchor(newAnchor, for: metricType)
                }

                completion(.success(samples))
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Anchor Persistence

    /// Loads saved anchors from UserDefaults
    private func loadAnchors() {
        for metricType in HealthMetricType.allCases {
            if let anchorData = UserDefaults.standard.data(forKey: anchorKey(for: metricType)),
               let anchor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: anchorData) {
                queryAnchors[metricType] = anchor
            }
        }
    }

    /// Saves an anchor to UserDefaults
    /// - Parameters:
    ///   - anchor: The anchor to save
    ///   - metricType: The metric type this anchor is for
    private func saveAnchor(_ anchor: HKQueryAnchor, for metricType: HealthMetricType) {
        if let anchorData = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(anchorData, forKey: anchorKey(for: metricType))
        }
    }

    /// Generates UserDefaults key for storing anchors
    private func anchorKey(for metricType: HealthMetricType) -> String {
        return "healthkit.anchor.\(metricType.rawValue)"
    }

    /// Clears all saved anchors (useful for debugging or reset)
    func clearAllAnchors() {
        for metricType in HealthMetricType.allCases {
            UserDefaults.standard.removeObject(forKey: anchorKey(for: metricType))
        }
        queryAnchors.removeAll()
    }

    // MARK: - Background Task Registration

    /// Registers background task for HealthKit sync
    /// Call this during app initialization
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else { return }
            handleBackgroundSync(task: task)
        }
    }

    /// Schedules a background sync task
    func scheduleBackgroundSync() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600) // 1 hour from now

        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background sync scheduled")
        } catch {
            print("Failed to schedule background sync: \(error.localizedDescription)")
        }
    }

    /// Handles background sync execution
    private static func handleBackgroundSync(task: BGProcessingTask) {
        // Schedule next sync
        let manager = HealthKitObserverManager()
        manager.scheduleBackgroundSync()

        // Perform sync with expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            do {
                // Fetch new data for all observed types
                // This is a placeholder - implement actual sync logic
                try await performBackgroundDataSync()
                task.setTaskCompleted(success: true)
            } catch {
                print("Background sync failed: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }
    }

    /// Performs background data synchronization
    private static func performBackgroundDataSync() async throws {
        // Implement actual sync logic here
        // This would typically:
        // 1. Fetch new data for all observed types
        // 2. Process and cache the data
        // 3. Upload to backend if needed
        print("Background data sync executed")
    }

    // MARK: - Statistics Collection

    /// Sets up statistics collection query for continuous monitoring
    /// - Parameters:
    ///   - metricType: The metric type to collect statistics for
    ///   - interval: The time interval for statistics aggregation
    ///   - updateHandler: Closure called with new statistics
    func startStatisticsCollection(
        for metricType: HealthMetricType,
        interval: DateComponents,
        updateHandler: @escaping (HKStatistics?, Error?) -> Void
    ) throws {
        guard let quantityType = metricType.healthKitIdentifier as? HKQuantityType else {
            throw HealthKitError.invalidData
        }

        let startDate = Calendar.current.startOfDay(for: Date())

        let query = HKStatisticsCollectionQuery(
            quantityType: quantityType,
            quantitySamplePredicate: nil,
            options: [.cumulativeSum, .discreteAverage],
            anchorDate: startDate,
            intervalComponents: interval
        )

        // Set initial results handler
        query.initialResultsHandler = { query, results, error in
            if let error = error {
                updateHandler(nil, error)
                return
            }

            results?.enumerateStatistics(from: startDate, to: Date()) { statistics, _ in
                updateHandler(statistics, nil)
            }
        }

        // Set statistics update handler for continuous monitoring
        query.statisticsUpdateHandler = { query, statistics, _, error in
            updateHandler(statistics, error)
        }

        healthStore.execute(query)
    }
}

// MARK: - Observer Delegate Protocol

/// Protocol for receiving HealthKit observer updates
protocol HealthKitObserverDelegate: AnyObject {
    func healthKitObserver(didReceiveUpdate metricType: HealthMetricType)
    func healthKitObserver(didFailWithError error: Error, for metricType: HealthMetricType)
}
