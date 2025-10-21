//
//  HealthKitDataFetcher.swift
//  Health Tracker App
//
//  Handles fetching health data from HealthKit using various query types
//

import Foundation
import HealthKit

/// Fetches health data from HealthKit using optimized queries
@MainActor
class HealthKitDataFetcher {

    // MARK: - Properties

    private let healthStore: HKHealthStore

    // MARK: - Initialization

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    // MARK: - Heart Rate Fetching

    /// Fetches heart rate samples within a date range
    /// - Parameters:
    ///   - startDate: Start of the query range
    ///   - endDate: End of the query range
    ///   - limit: Maximum number of samples to return (nil for no limit)
    /// - Returns: Array of heart rate metrics
    func fetchHeartRate(from startDate: Date, to endDate: Date, limit: Int? = nil) async throws -> [HeartRateMetric] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitError.invalidData
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: limit ?? HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(underlying: error))
                    return
                }

                guard let quantitySamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }

                let metrics = quantitySamples.map { sample in
                    HeartRateMetric(
                        timestamp: sample.startDate,
                        beatsPerMinute: sample.quantity.doubleValue(for: HKUnit(from: "count/min")),
                        sourceDevice: sample.device?.name
                    )
                }

                continuation.resume(returning: metrics)
            }

            healthStore.execute(query)
        }
    }

    /// Fetches average heart rate for a specific time period
    /// - Parameters:
    ///   - startDate: Start of the query range
    ///   - endDate: End of the query range
    /// - Returns: Average heart rate in BPM, or nil if no data
    func fetchAverageHeartRate(from startDate: Date, to endDate: Date) async throws -> Double? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitError.invalidData
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(underlying: error))
                    return
                }

                let averageQuantity = statistics?.averageQuantity()
                let value = averageQuantity?.doubleValue(for: HKUnit(from: "count/min"))
                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Steps Fetching

    /// Fetches step count samples within a date range
    /// - Parameters:
    ///   - startDate: Start of the query range
    ///   - endDate: End of the query range
    /// - Returns: Array of step metrics
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> [StepsMetric] {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.invalidData
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: stepsType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(underlying: error))
                    return
                }

                guard let quantitySamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }

                let metrics = quantitySamples.map { sample in
                    StepsMetric(
                        timestamp: sample.startDate,
                        count: Int(sample.quantity.doubleValue(for: HKUnit.count())),
                        sourceDevice: sample.device?.name,
                        duration: sample.endDate.timeIntervalSince(sample.startDate)
                    )
                }

                continuation.resume(returning: metrics)
            }

            healthStore.execute(query)
        }
    }

    /// Fetches total step count for a specific time period
    /// - Parameters:
    ///   - startDate: Start of the query range
    ///   - endDate: End of the query range
    /// - Returns: Total step count, or nil if no data
    func fetchTotalSteps(from startDate: Date, to endDate: Date) async throws -> Int? {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.invalidData
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(underlying: error))
                    return
                }

                let sum = statistics?.sumQuantity()
                let value = sum?.doubleValue(for: HKUnit.count())
                continuation.resume(returning: value.map { Int($0) })
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Blood Pressure Fetching

    /// Fetches blood pressure samples within a date range
    /// - Parameters:
    ///   - startDate: Start of the query range
    ///   - endDate: End of the query range
    ///   - limit: Maximum number of samples to return (nil for no limit)
    /// - Returns: Array of blood pressure metrics
    func fetchBloodPressure(from startDate: Date, to endDate: Date, limit: Int? = nil) async throws -> [BloodPressureMetric] {
        guard let bloodPressureType = HKCorrelationType.correlationType(forIdentifier: .bloodPressure) else {
            throw HealthKitError.invalidData
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bloodPressureType,
                predicate: predicate,
                limit: limit ?? HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(underlying: error))
                    return
                }

                guard let correlations = samples as? [HKCorrelation] else {
                    continuation.resume(returning: [])
                    return
                }

                var metrics: [BloodPressureMetric] = []

                for correlation in correlations {
                    guard let systolicSample = correlation.objects(for: HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)!).first as? HKQuantitySample,
                          let diastolicSample = correlation.objects(for: HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic)!).first as? HKQuantitySample else {
                        continue
                    }

                    let systolic = systolicSample.quantity.doubleValue(for: HKUnit.millimeterOfMercury())
                    let diastolic = diastolicSample.quantity.doubleValue(for: HKUnit.millimeterOfMercury())

                    let metric = BloodPressureMetric(
                        timestamp: correlation.startDate,
                        systolic: systolic,
                        diastolic: diastolic,
                        sourceDevice: correlation.device?.name
                    )
                    metrics.append(metric)
                }

                continuation.resume(returning: metrics)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Sleep Fetching

    /// Fetches sleep analysis samples within a date range
    /// - Parameters:
    ///   - startDate: Start of the query range
    ///   - endDate: End of the query range
    /// - Returns: Array of sleep metrics
    func fetchSleep(from startDate: Date, to endDate: Date) async throws -> [SleepMetric] {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.invalidData
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(underlying: error))
                    return
                }

                guard let categorySamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }

                let metrics = categorySamples.compactMap { sample -> SleepMetric? in
                    guard let sleepValue = HKCategoryValueSleepAnalysis(rawValue: sample.value) else {
                        return nil
                    }

                    return SleepMetric(
                        timestamp: sample.startDate,
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        stage: SleepMetric.SleepStage(from: sleepValue),
                        sourceDevice: sample.device?.name
                    )
                }

                continuation.resume(returning: metrics)
            }

            healthStore.execute(query)
        }
    }

    /// Calculates total sleep duration for a specific time period
    /// - Parameters:
    ///   - startDate: Start of the query range
    ///   - endDate: End of the query range
    /// - Returns: Total sleep duration in seconds
    func fetchTotalSleepDuration(from startDate: Date, to endDate: Date) async throws -> TimeInterval {
        let sleepMetrics = try await fetchSleep(from: startDate, to: endDate)

        let asleepMetrics = sleepMetrics.filter {
            $0.stage == .asleep || $0.stage == .core || $0.stage == .deep || $0.stage == .rem
        }

        return asleepMetrics.reduce(0) { $0 + $1.duration }
    }

    // MARK: - Aggregated Data Fetching

    /// Fetches aggregated health data for a specific time period
    /// - Parameters:
    ///   - startDate: Start of the query range
    ///   - endDate: End of the query range
    /// - Returns: Aggregated health data
    func fetchAggregatedData(from startDate: Date, to endDate: Date) async throws -> AggregatedHealthData {
        async let heartRateAvg = try? fetchAverageHeartRate(from: startDate, to: endDate)
        async let totalSteps = try? fetchTotalSteps(from: startDate, to: endDate)
        async let sleepDuration = try? fetchTotalSleepDuration(from: startDate, to: endDate)
        async let restingHR = try? fetchRestingHeartRate(from: startDate, to: endDate)

        let (avgHR, steps, sleep, rhr) = await (heartRateAvg, totalSteps, sleepDuration, restingHR)

        return AggregatedHealthData(
            startDate: startDate,
            endDate: endDate,
            heartRateAverage: avgHR,
            totalSteps: steps,
            sleepDuration: sleep,
            restingHeartRate: rhr
        )
    }

    // MARK: - Additional Metrics

    /// Fetches resting heart rate for a specific time period
    private func fetchRestingHeartRate(from startDate: Date, to endDate: Date) async throws -> Double? {
        guard let restingHRType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw HealthKitError.invalidData
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: restingHRType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(underlying: error))
                    return
                }

                let averageQuantity = statistics?.averageQuantity()
                let value = averageQuantity?.doubleValue(for: HKUnit(from: "count/min"))
                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Anchor Query for Incremental Updates

    /// Fetches new samples since a specific anchor
    /// - Parameters:
    ///   - metricType: The type of metric to fetch
    ///   - anchor: Previous query anchor (nil for first query)
    ///   - limit: Maximum number of samples to return
    /// - Returns: Tuple containing new samples and updated anchor
    func fetchNewSamples(
        for metricType: HealthMetricType,
        since anchor: HKQueryAnchor?,
        limit: Int = HKObjectQueryNoLimit
    ) async throws -> (samples: [HKSample], newAnchor: HKQueryAnchor?) {
        guard let sampleType = metricType.healthKitIdentifier as? HKSampleType else {
            throw HealthKitError.invalidData
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: nil,
                anchor: anchor,
                limit: limit
            ) { _, samplesOrNil, deletedObjectsOrNil, newAnchor, errorOrNil in
                if let error = errorOrNil {
                    continuation.resume(throwing: HealthKitError.queryFailed(underlying: error))
                    return
                }

                let samples = samplesOrNil ?? []
                continuation.resume(returning: (samples: samples, newAnchor: newAnchor))
            }

            healthStore.execute(query)
        }
    }
}
