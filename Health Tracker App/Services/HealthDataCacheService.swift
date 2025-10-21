//
//  HealthDataCacheService.swift
//  Health Tracker App
//
//  Provides efficient caching and throttling for HealthKit data
//  to reduce battery usage and improve performance
//

import Foundation

/// Manages caching and throttling of health data to optimize battery usage
actor HealthDataCacheService {

    // MARK: - Cache Configuration

    struct CacheConfiguration {
        /// Time interval before cached data is considered stale
        let cacheDuration: TimeInterval

        /// Minimum interval between fetches for the same metric type
        let throttleInterval: TimeInterval

        /// Maximum number of cached items per metric type
        let maxCacheSize: Int

        /// Whether to persist cache to disk
        let persistToDisk: Bool

        static let `default` = CacheConfiguration(
            cacheDuration: 300, // 5 minutes
            throttleInterval: 60, // 1 minute
            maxCacheSize: 1000,
            persistToDisk: true
        )

        static let aggressive = CacheConfiguration(
            cacheDuration: 900, // 15 minutes
            throttleInterval: 180, // 3 minutes
            maxCacheSize: 500,
            persistToDisk: true
        )

        static let realtime = CacheConfiguration(
            cacheDuration: 30, // 30 seconds
            throttleInterval: 10, // 10 seconds
            maxCacheSize: 2000,
            persistToDisk: false
        )
    }

    // MARK: - Cache Entry

    private struct CacheEntry<T: Codable>: Codable {
        let data: T
        let timestamp: Date
        let expiresAt: Date

        var isExpired: Bool {
            Date() > expiresAt
        }

        init(data: T, cacheDuration: TimeInterval) {
            self.data = data
            self.timestamp = Date()
            self.expiresAt = Date().addingTimeInterval(cacheDuration)
        }
    }

    // MARK: - Throttle Entry

    private struct ThrottleEntry {
        let lastFetchTime: Date
        let metricType: HealthMetricType

        func shouldThrottle(throttleInterval: TimeInterval) -> Bool {
            let elapsed = Date().timeIntervalSince(lastFetchTime)
            return elapsed < throttleInterval
        }

        func remainingThrottleTime(throttleInterval: TimeInterval) -> TimeInterval {
            let elapsed = Date().timeIntervalSince(lastFetchTime)
            return max(0, throttleInterval - elapsed)
        }
    }

    // MARK: - Properties

    private var heartRateCache: [CacheEntry<[HeartRateMetric]>] = []
    private var stepsCache: [CacheEntry<[StepsMetric]>] = []
    private var bloodPressureCache: [CacheEntry<[BloodPressureMetric]>] = []
    private var sleepCache: [CacheEntry<[SleepMetric]>] = []
    private var aggregatedCache: [String: CacheEntry<AggregatedHealthData>] = [:]

    private var throttleEntries: [HealthMetricType: ThrottleEntry] = [:]

    private let configuration: CacheConfiguration
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    // MARK: - Cache Statistics

    struct CacheStatistics {
        var hitCount: Int = 0
        var missCount: Int = 0
        var throttleCount: Int = 0
        var totalQueries: Int = 0

        var hitRate: Double {
            guard totalQueries > 0 else { return 0 }
            return Double(hitCount) / Double(totalQueries)
        }

        var throttleRate: Double {
            guard totalQueries > 0 else { return 0 }
            return Double(throttleCount) / Double(totalQueries)
        }

        mutating func recordHit() {
            hitCount += 1
            totalQueries += 1
        }

        mutating func recordMiss() {
            missCount += 1
            totalQueries += 1
        }

        mutating func recordThrottle() {
            throttleCount += 1
            totalQueries += 1
        }
    }

    private var statistics = CacheStatistics()

    // MARK: - Initialization

    init(configuration: CacheConfiguration = .default) {
        self.configuration = configuration

        // Set up cache directory
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        self.cacheDirectory = paths[0].appendingPathComponent("HealthDataCache", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Load persisted cache if enabled
        if configuration.persistToDisk {
            loadPersistedCache()
        }
    }

    // MARK: - Cache Operations

    /// Stores heart rate metrics in cache
    func cacheHeartRate(_ metrics: [HeartRateMetric]) {
        let entry = CacheEntry(data: metrics, cacheDuration: configuration.cacheDuration)
        heartRateCache.append(entry)
        trimCache(&heartRateCache)

        if configuration.persistToDisk {
            persistCache(metrics, key: "heartRate")
        }
    }

    /// Retrieves cached heart rate metrics if available and not expired
    func getCachedHeartRate() -> [HeartRateMetric]? {
        statistics.totalQueries += 1

        guard let latest = heartRateCache.last, !latest.isExpired else {
            statistics.recordMiss()
            return nil
        }

        statistics.recordHit()
        return latest.data
    }

    /// Stores steps metrics in cache
    func cacheSteps(_ metrics: [StepsMetric]) {
        let entry = CacheEntry(data: metrics, cacheDuration: configuration.cacheDuration)
        stepsCache.append(entry)
        trimCache(&stepsCache)

        if configuration.persistToDisk {
            persistCache(metrics, key: "steps")
        }
    }

    /// Retrieves cached steps metrics if available and not expired
    func getCachedSteps() -> [StepsMetric]? {
        statistics.totalQueries += 1

        guard let latest = stepsCache.last, !latest.isExpired else {
            statistics.recordMiss()
            return nil
        }

        statistics.recordHit()
        return latest.data
    }

    /// Stores blood pressure metrics in cache
    func cacheBloodPressure(_ metrics: [BloodPressureMetric]) {
        let entry = CacheEntry(data: metrics, cacheDuration: configuration.cacheDuration)
        bloodPressureCache.append(entry)
        trimCache(&bloodPressureCache)

        if configuration.persistToDisk {
            persistCache(metrics, key: "bloodPressure")
        }
    }

    /// Retrieves cached blood pressure metrics if available and not expired
    func getCachedBloodPressure() -> [BloodPressureMetric]? {
        statistics.totalQueries += 1

        guard let latest = bloodPressureCache.last, !latest.isExpired else {
            statistics.recordMiss()
            return nil
        }

        statistics.recordHit()
        return latest.data
    }

    /// Stores sleep metrics in cache
    func cacheSleep(_ metrics: [SleepMetric]) {
        let entry = CacheEntry(data: metrics, cacheDuration: configuration.cacheDuration)
        sleepCache.append(entry)
        trimCache(&sleepCache)

        if configuration.persistToDisk {
            persistCache(metrics, key: "sleep")
        }
    }

    /// Retrieves cached sleep metrics if available and not expired
    func getCachedSleep() -> [SleepMetric]? {
        statistics.totalQueries += 1

        guard let latest = sleepCache.last, !latest.isExpired else {
            statistics.recordMiss()
            return nil
        }

        statistics.recordHit()
        return latest.data
    }

    /// Stores aggregated data in cache with a specific key
    func cacheAggregatedData(_ data: AggregatedHealthData, key: String) {
        let entry = CacheEntry(data: data, cacheDuration: configuration.cacheDuration)
        aggregatedCache[key] = entry

        if configuration.persistToDisk {
            persistCache(data, key: "aggregated_\(key)")
        }
    }

    /// Retrieves cached aggregated data for a specific key
    func getCachedAggregatedData(key: String) -> AggregatedHealthData? {
        statistics.totalQueries += 1

        guard let entry = aggregatedCache[key], !entry.isExpired else {
            statistics.recordMiss()
            return nil
        }

        statistics.recordHit()
        return entry.data
    }

    // MARK: - Throttling

    /// Checks if a fetch request should be throttled
    /// - Parameter metricType: The metric type being requested
    /// - Returns: True if request should be throttled
    func shouldThrottle(_ metricType: HealthMetricType) -> Bool {
        guard let entry = throttleEntries[metricType] else {
            return false
        }

        let shouldThrottle = entry.shouldThrottle(throttleInterval: configuration.throttleInterval)

        if shouldThrottle {
            statistics.recordThrottle()
        }

        return shouldThrottle
    }

    /// Records that a fetch was performed for throttling purposes
    /// - Parameter metricType: The metric type that was fetched
    func recordFetch(for metricType: HealthMetricType) {
        let entry = ThrottleEntry(lastFetchTime: Date(), metricType: metricType)
        throttleEntries[metricType] = entry
    }

    /// Gets remaining throttle time for a metric type
    /// - Parameter metricType: The metric type to check
    /// - Returns: Remaining throttle time in seconds
    func getRemainingThrottleTime(for metricType: HealthMetricType) -> TimeInterval {
        guard let entry = throttleEntries[metricType] else {
            return 0
        }

        return entry.remainingThrottleTime(throttleInterval: configuration.throttleInterval)
    }

    // MARK: - Cache Management

    /// Trims cache to maximum size
    private func trimCache<T: Codable>(_ cache: inout [CacheEntry<T>]) {
        // Remove expired entries first
        cache.removeAll { $0.isExpired }

        // Trim to max size if needed
        if cache.count > configuration.maxCacheSize {
            let removeCount = cache.count - configuration.maxCacheSize
            cache.removeFirst(removeCount)
        }
    }

    /// Clears all cached data
    func clearAllCache() {
        heartRateCache.removeAll()
        stepsCache.removeAll()
        bloodPressureCache.removeAll()
        sleepCache.removeAll()
        aggregatedCache.removeAll()
        throttleEntries.removeAll()

        if configuration.persistToDisk {
            clearPersistedCache()
        }

        statistics = CacheStatistics()
    }

    /// Clears cache for a specific metric type
    func clearCache(for metricType: HealthMetricType) {
        switch metricType {
        case .heartRate, .restingHeartRate, .heartRateVariability:
            heartRateCache.removeAll()
        case .steps:
            stepsCache.removeAll()
        case .bloodPressure:
            bloodPressureCache.removeAll()
        case .sleep:
            sleepCache.removeAll()
        default:
            break
        }

        throttleEntries.removeValue(forKey: metricType)
    }

    /// Returns current cache statistics
    func getStatistics() -> CacheStatistics {
        return statistics
    }

    /// Resets cache statistics
    func resetStatistics() {
        statistics = CacheStatistics()
    }

    // MARK: - Disk Persistence

    private func persistCache<T: Codable>(_ data: T, key: String) {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: fileURL)
        } catch {
            print("Failed to persist cache for key \(key): \(error)")
        }
    }

    private func loadPersistedCache() {
        // Load each cache type from disk
        loadPersistedCache(HeartRateMetric.self, key: "heartRate") { metrics in
            if let metrics = metrics {
                self.heartRateCache.append(CacheEntry(data: metrics, cacheDuration: self.configuration.cacheDuration))
            }
        }

        loadPersistedCache(StepsMetric.self, key: "steps") { metrics in
            if let metrics = metrics {
                self.stepsCache.append(CacheEntry(data: metrics, cacheDuration: self.configuration.cacheDuration))
            }
        }

        loadPersistedCache(BloodPressureMetric.self, key: "bloodPressure") { metrics in
            if let metrics = metrics {
                self.bloodPressureCache.append(CacheEntry(data: metrics, cacheDuration: self.configuration.cacheDuration))
            }
        }

        loadPersistedCache(SleepMetric.self, key: "sleep") { metrics in
            if let metrics = metrics {
                self.sleepCache.append(CacheEntry(data: metrics, cacheDuration: self.configuration.cacheDuration))
            }
        }
    }

    private func loadPersistedCache<T: Codable>(_ type: [T].Type, key: String, completion: @escaping ([T]?) -> Void) {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")

        do {
            let jsonData = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try decoder.decode([T].self, from: jsonData)
            completion(data)
        } catch {
            completion(nil)
        }
    }

    private func clearPersistedCache() {
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
        } catch {
            print("Failed to clear persisted cache: \(error)")
        }
    }

    // MARK: - Battery Optimization Helpers

    /// Determines optimal cache configuration based on battery level and state
    static func recommendedConfiguration(batteryLevel: Float, isLowPowerMode: Bool) -> CacheConfiguration {
        if isLowPowerMode || batteryLevel < 0.2 {
            return .aggressive
        } else if batteryLevel > 0.5 {
            return .realtime
        } else {
            return .default
        }
    }
}
