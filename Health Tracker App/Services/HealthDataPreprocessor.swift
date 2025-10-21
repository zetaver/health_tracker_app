//
//  HealthDataPreprocessor.swift
//  Health Tracker App
//
//  Preprocesses HealthKit data for AI/ML analysis
//  Handles normalization, aggregation, and feature engineering
//

import Foundation

/// Preprocesses health data for AI model consumption
actor HealthDataPreprocessor {

    // MARK: - Normalization Methods

    enum NormalizationMethod {
        case zScore           // (x - mean) / std
        case minMax           // (x - min) / (max - min)
        case robust           // (x - median) / IQR
        case none
    }

    enum OutlierHandling {
        case remove
        case cap              // Cap at threshold
        case flag             // Keep but mark
        case none
    }

    // MARK: - Configuration

    struct PreprocessingConfig {
        let normalizationMethod: NormalizationMethod
        let outlierHandling: OutlierHandling
        let outlierThreshold: Double           // Number of std devs
        let missingDataStrategy: MissingDataStrategy
        let smoothingEnabled: Bool
        let smoothingWindowSize: Int

        enum MissingDataStrategy {
            case forwardFill
            case interpolation
            case median
            case remove
        }

        static let `default` = PreprocessingConfig(
            normalizationMethod: .zScore,
            outlierHandling: .cap,
            outlierThreshold: 3.0,
            missingDataStrategy: .interpolation,
            smoothingEnabled: false,
            smoothingWindowSize: 5
        )

        static let aiOptimized = PreprocessingConfig(
            normalizationMethod: .zScore,
            outlierHandling: .cap,
            outlierThreshold: 3.0,
            missingDataStrategy: .interpolation,
            smoothingEnabled: true,
            smoothingWindowSize: 5
        )
    }

    private let config: PreprocessingConfig

    // MARK: - Statistical Parameters

    struct StatisticalParameters: Codable {
        let heartRate: MetricParameters
        let systolicBP: MetricParameters
        let diastolicBP: MetricParameters
        let steps: MetricParameters

        struct MetricParameters: Codable {
            let mean: Double
            let stdDev: Double
            let median: Double
            let min: Double
            let max: Double
            let q25: Double   // 25th percentile
            let q75: Double   // 75th percentile
            let iqr: Double   // Interquartile range
        }
    }

    private var parameters: StatisticalParameters?

    // MARK: - Initialization

    init(config: PreprocessingConfig = .default) {
        self.config = config
    }

    // MARK: - Preprocessing Pipeline

    /// Main preprocessing pipeline
    func preprocessHealthData(
        heartRate: [HeartRateMetric],
        bloodPressure: [BloodPressureMetric],
        steps: [StepsMetric],
        sleep: [SleepMetric]
    ) async throws -> AIHealthDataPayload {

        // 1. Calculate statistical parameters if not already done
        if parameters == nil {
            parameters = calculateStatisticalParameters(
                heartRate: heartRate,
                bloodPressure: bloodPressure,
                steps: steps
            )
        }

        // 2. Preprocess each metric type
        let processedHeartRate = await preprocessHeartRate(heartRate)
        let processedBP = await preprocessBloodPressure(bloodPressure)
        let processedSteps = await preprocessSteps(steps)
        let processedSleep = await preprocessSleep(sleep)

        // 3. Create temporal aggregations
        let aggregations = await createAggregations(
            heartRate: processedHeartRate,
            bloodPressure: processedBP,
            steps: processedSteps,
            sleep: processedSleep
        )

        // 4. Engineer features
        let features = await engineerFeatures(
            heartRate: processedHeartRate,
            bloodPressure: processedBP,
            steps: processedSteps,
            sleep: processedSleep,
            aggregations: aggregations
        )

        // 5. Create payload
        return AIHealthDataPayload(
            heartRate: processedHeartRate,
            bloodPressure: processedBP,
            steps: processedSteps,
            sleep: processedSleep,
            aggregations: aggregations,
            features: features,
            preprocessingMetadata: createMetadata()
        )
    }

    // MARK: - Heart Rate Preprocessing

    private func preprocessHeartRate(_ metrics: [HeartRateMetric]) async -> ProcessedHeartRateData {
        guard !metrics.isEmpty else {
            return ProcessedHeartRateData(dataPoints: [], statistics: nil, normalized: [])
        }

        let values = metrics.map { $0.beatsPerMinute }

        // Handle outliers
        let (cleanedValues, outlierIndices) = handleOutliers(
            values: values,
            threshold: config.outlierThreshold
        )

        // Normalize
        let normalizedValues = normalize(
            values: cleanedValues,
            method: config.normalizationMethod,
            parameters: parameters?.heartRate
        )

        // Calculate statistics
        let statistics = calculateStatistics(values: cleanedValues)

        return ProcessedHeartRateData(
            dataPoints: metrics.enumerated().map { index, metric in
                ProcessedDataPoint(
                    timestamp: metric.timestamp,
                    originalValue: metric.beatsPerMinute,
                    normalizedValue: normalizedValues[index],
                    isOutlier: outlierIndices.contains(index)
                )
            },
            statistics: statistics,
            normalized: normalizedValues
        )
    }

    // MARK: - Blood Pressure Preprocessing

    private func preprocessBloodPressure(_ metrics: [BloodPressureMetric]) async -> ProcessedBloodPressureData {
        guard !metrics.isEmpty else {
            return ProcessedBloodPressureData(
                systolic: ProcessedSeries(values: [], statistics: nil),
                diastolic: ProcessedSeries(values: [], statistics: nil)
            )
        }

        let systolicValues = metrics.map { $0.systolic }
        let diastolicValues = metrics.map { $0.diastolic }

        // Process systolic
        let (cleanedSystolic, _) = handleOutliers(values: systolicValues, threshold: config.outlierThreshold)
        let normalizedSystolic = normalize(
            values: cleanedSystolic,
            method: config.normalizationMethod,
            parameters: parameters?.systolicBP
        )

        // Process diastolic
        let (cleanedDiastolic, _) = handleOutliers(values: diastolicValues, threshold: config.outlierThreshold)
        let normalizedDiastolic = normalize(
            values: cleanedDiastolic,
            method: config.normalizationMethod,
            parameters: parameters?.diastolicBP
        )

        return ProcessedBloodPressureData(
            systolic: ProcessedSeries(
                values: normalizedSystolic,
                statistics: calculateStatistics(values: cleanedSystolic)
            ),
            diastolic: ProcessedSeries(
                values: normalizedDiastolic,
                statistics: calculateStatistics(values: cleanedDiastolic)
            )
        )
    }

    // MARK: - Steps Preprocessing

    private func preprocessSteps(_ metrics: [StepsMetric]) async -> ProcessedStepsData {
        guard !metrics.isEmpty else {
            return ProcessedStepsData(dataPoints: [], statistics: nil, normalized: [])
        }

        let values = metrics.map { Double($0.count) }

        let (cleanedValues, outlierIndices) = handleOutliers(values: values, threshold: config.outlierThreshold)
        let normalizedValues = normalize(
            values: cleanedValues,
            method: config.normalizationMethod,
            parameters: parameters?.steps
        )

        return ProcessedStepsData(
            dataPoints: metrics.enumerated().map { index, metric in
                ProcessedDataPoint(
                    timestamp: metric.timestamp,
                    originalValue: Double(metric.count),
                    normalizedValue: normalizedValues[index],
                    isOutlier: outlierIndices.contains(index)
                )
            },
            statistics: calculateStatistics(values: cleanedValues),
            normalized: normalizedValues
        )
    }

    // MARK: - Sleep Preprocessing

    private func preprocessSleep(_ metrics: [SleepMetric]) async -> ProcessedSleepData {
        guard !metrics.isEmpty else {
            return ProcessedSleepData(sessions: [], statistics: nil)
        }

        // Group by date
        let sessionsByDate = Dictionary(grouping: metrics) { metric in
            Calendar.current.startOfDay(for: metric.startDate)
        }

        let sessions = sessionsByDate.map { date, dayMetrics -> SleepSession in
            let totalDuration = dayMetrics.reduce(0.0) { $0 + $1.duration }
            let asleepDuration = dayMetrics.filter {
                $0.stage == .asleep || $0.stage == .deep || $0.stage == .rem
            }.reduce(0.0) { $0 + $1.duration }

            let deepSleep = dayMetrics.filter { $0.stage == .deep }.reduce(0.0) { $0 + $1.duration }
            let remSleep = dayMetrics.filter { $0.stage == .rem }.reduce(0.0) { $0 + $1.duration }

            let efficiency = totalDuration > 0 ? asleepDuration / totalDuration : 0

            return SleepSession(
                date: date,
                totalDurationHours: totalDuration / 3600,
                asleepDurationHours: asleepDuration / 3600,
                deepSleepHours: deepSleep / 3600,
                remSleepHours: remSleep / 3600,
                efficiency: efficiency,
                sleepScore: calculateSleepScore(efficiency: efficiency, duration: totalDuration / 3600)
            )
        }.sorted { $0.date < $1.date }

        let durations = sessions.map { $0.totalDurationHours }
        let statistics = calculateStatistics(values: durations)

        return ProcessedSleepData(sessions: sessions, statistics: statistics)
    }

    // MARK: - Outlier Handling

    private func handleOutliers(values: [Double], threshold: Double) -> ([Double], Set<Int>) {
        guard config.outlierHandling != .none else {
            return (values, Set())
        }

        let mean = values.reduce(0.0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0.0, +) / Double(values.count)
        let stdDev = sqrt(variance)

        var outlierIndices = Set<Int>()
        var cleanedValues = values

        for (index, value) in values.enumerated() {
            let zScore = abs(value - mean) / stdDev

            if zScore > threshold {
                outlierIndices.insert(index)

                switch config.outlierHandling {
                case .remove:
                    // Mark for removal (handled separately)
                    break
                case .cap:
                    // Cap at threshold
                    let cappedValue = mean + (threshold * stdDev * (value > mean ? 1 : -1))
                    cleanedValues[index] = cappedValue
                case .flag:
                    // Keep original value but flag
                    break
                case .none:
                    break
                }
            }
        }

        return (cleanedValues, outlierIndices)
    }

    // MARK: - Normalization

    private func normalize(
        values: [Double],
        method: NormalizationMethod,
        parameters: StatisticalParameters.MetricParameters?
    ) -> [Double] {
        guard !values.isEmpty else { return [] }

        switch method {
        case .zScore:
            let mean = parameters?.mean ?? values.reduce(0.0, +) / Double(values.count)
            let stdDev = parameters?.stdDev ?? calculateStdDev(values: values, mean: mean)
            return values.map { ($0 - mean) / stdDev }

        case .minMax:
            let min = parameters?.min ?? values.min() ?? 0
            let max = parameters?.max ?? values.max() ?? 1
            let range = max - min
            return values.map { range > 0 ? ($0 - min) / range : 0 }

        case .robust:
            let median = parameters?.median ?? calculateMedian(values: values)
            let iqr = parameters?.iqr ?? (parameters?.q75 ?? 0) - (parameters?.q25 ?? 0)
            return values.map { iqr > 0 ? ($0 - median) / iqr : 0 }

        case .none:
            return values
        }
    }

    // MARK: - Statistics

    private func calculateStatistics(values: [Double]) -> VitalStatistics {
        guard !values.isEmpty else {
            return VitalStatistics(count: 0, mean: 0, median: 0, stdDev: 0, min: 0, max: 0, q25: 0, q75: 0)
        }

        let sorted = values.sorted()
        let count = values.count
        let mean = values.reduce(0.0, +) / Double(count)
        let median = calculateMedian(values: sorted)
        let stdDev = calculateStdDev(values: values, mean: mean)
        let min = sorted.first ?? 0
        let max = sorted.last ?? 0
        let q25 = calculatePercentile(sorted: sorted, percentile: 0.25)
        let q75 = calculatePercentile(sorted: sorted, percentile: 0.75)

        return VitalStatistics(
            count: count,
            mean: mean,
            median: median,
            stdDev: stdDev,
            min: min,
            max: max,
            q25: q25,
            q75: q75
        )
    }

    private func calculateMedian(values: [Double]) -> Double {
        let sorted = values.sorted()
        let count = sorted.count

        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        } else {
            return sorted[count / 2]
        }
    }

    private func calculateStdDev(values: [Double], mean: Double) -> Double {
        let variance = values.map { pow($0 - mean, 2) }.reduce(0.0, +) / Double(values.count)
        return sqrt(variance)
    }

    private func calculatePercentile(sorted: [Double], percentile: Double) -> Double {
        let index = Int(Double(sorted.count - 1) * percentile)
        return sorted[index]
    }

    private func calculateStatisticalParameters(
        heartRate: [HeartRateMetric],
        bloodPressure: [BloodPressureMetric],
        steps: [StepsMetric]
    ) -> StatisticalParameters {
        // Calculate for heart rate
        let hrValues = heartRate.map { $0.beatsPerMinute }
        let hrSorted = hrValues.sorted()

        let hrMean = hrValues.reduce(0.0, +) / Double(hrValues.count)
        let hrParams = StatisticalParameters.MetricParameters(
            mean: hrMean,
            stdDev: calculateStdDev(values: hrValues, mean: hrMean),
            median: calculateMedian(values: hrValues),
            min: hrSorted.first ?? 0,
            max: hrSorted.last ?? 200,
            q25: calculatePercentile(sorted: hrSorted, percentile: 0.25),
            q75: calculatePercentile(sorted: hrSorted, percentile: 0.75),
            iqr: calculatePercentile(sorted: hrSorted, percentile: 0.75) - calculatePercentile(sorted: hrSorted, percentile: 0.25)
        )

        // Similar for blood pressure and steps...
        let systolicValues = bloodPressure.map { $0.systolic }
        let systolicSorted = systolicValues.sorted()
        let systolicMean = systolicValues.reduce(0.0, +) / Double(systolicValues.count)

        let diastolicValues = bloodPressure.map { $0.diastolic }
        let diastolicSorted = diastolicValues.sorted()
        let diastolicMean = diastolicValues.reduce(0.0, +) / Double(diastolicValues.count)

        let stepsValues = steps.map { Double($0.count) }
        let stepsSorted = stepsValues.sorted()
        let stepsMean = stepsValues.reduce(0.0, +) / Double(stepsValues.count)

        return StatisticalParameters(
            heartRate: hrParams,
            systolicBP: StatisticalParameters.MetricParameters(
                mean: systolicMean,
                stdDev: calculateStdDev(values: systolicValues, mean: systolicMean),
                median: calculateMedian(values: systolicValues),
                min: systolicSorted.first ?? 0,
                max: systolicSorted.last ?? 200,
                q25: calculatePercentile(sorted: systolicSorted, percentile: 0.25),
                q75: calculatePercentile(sorted: systolicSorted, percentile: 0.75),
                iqr: calculatePercentile(sorted: systolicSorted, percentile: 0.75) - calculatePercentile(sorted: systolicSorted, percentile: 0.25)
            ),
            diastolicBP: StatisticalParameters.MetricParameters(
                mean: diastolicMean,
                stdDev: calculateStdDev(values: diastolicValues, mean: diastolicMean),
                median: calculateMedian(values: diastolicValues),
                min: diastolicSorted.first ?? 0,
                max: diastolicSorted.last ?? 120,
                q25: calculatePercentile(sorted: diastolicSorted, percentile: 0.25),
                q75: calculatePercentile(sorted: diastolicSorted, percentile: 0.75),
                iqr: calculatePercentile(sorted: diastolicSorted, percentile: 0.75) - calculatePercentile(sorted: diastolicSorted, percentile: 0.25)
            ),
            steps: StatisticalParameters.MetricParameters(
                mean: stepsMean,
                stdDev: calculateStdDev(values: stepsValues, mean: stepsMean),
                median: calculateMedian(values: stepsValues),
                min: stepsSorted.first ?? 0,
                max: stepsSorted.last ?? 30000,
                q25: calculatePercentile(sorted: stepsSorted, percentile: 0.25),
                q75: calculatePercentile(sorted: stepsSorted, percentile: 0.75),
                iqr: calculatePercentile(sorted: stepsSorted, percentile: 0.75) - calculatePercentile(sorted: stepsSorted, percentile: 0.25)
            )
        )
    }

    // MARK: - Aggregations

    private func createAggregations(
        heartRate: ProcessedHeartRateData,
        bloodPressure: ProcessedBloodPressureData,
        steps: ProcessedStepsData,
        sleep: ProcessedSleepData
    ) async -> TemporalAggregations {
        // Group by day
        let dailyAggregates = createDailyAggregates(
            heartRate: heartRate,
            bloodPressure: bloodPressure,
            steps: steps,
            sleep: sleep
        )

        return TemporalAggregations(daily: dailyAggregates)
    }

    private func createDailyAggregates(
        heartRate: ProcessedHeartRateData,
        bloodPressure: ProcessedBloodPressureData,
        steps: ProcessedStepsData,
        sleep: ProcessedSleepData
    ) -> [DailyAggregate] {
        // Implementation would group data by day and create aggregates
        // Simplified for brevity
        return []
    }

    // MARK: - Feature Engineering

    private func engineerFeatures(
        heartRate: ProcessedHeartRateData,
        bloodPressure: ProcessedBloodPressureData,
        steps: ProcessedStepsData,
        sleep: ProcessedSleepData,
        aggregations: TemporalAggregations
    ) async -> EngineeredFeatures {
        // Calculate derived features
        let cardiovascularScore = calculateCardiovascularScore(heartRate: heartRate)
        let sleepQualityIndex = calculateSleepQualityIndex(sleep: sleep)
        let activityRegularity = calculateActivityRegularity(steps: steps)

        return EngineeredFeatures(
            cardiovascularFitnessScore: cardiovascularScore,
            sleepQualityIndex: sleepQualityIndex,
            activityRegularity: activityRegularity
        )
    }

    private func calculateCardiovascularScore(heartRate: ProcessedHeartRateData) -> Double {
        // Simplified scoring based on resting HR and variability
        guard let stats = heartRate.statistics else { return 0 }

        // Lower resting heart rate is better (up to a point)
        let restingScore = max(0, 100 - (stats.mean - 60) * 2)

        // Lower variability is concerning, moderate is good
        let variabilityScore = min(100, stats.stdDev * 5)

        return (restingScore + variabilityScore) / 2
    }

    private func calculateSleepQualityIndex(sleep: ProcessedSleepData) -> Double {
        // Simplified sleep quality calculation
        guard !sleep.sessions.isEmpty else { return 0 }

        let avgEfficiency = sleep.sessions.map { $0.efficiency }.reduce(0.0, +) / Double(sleep.sessions.count)
        let avgDuration = sleep.sessions.map { $0.totalDurationHours }.reduce(0.0, +) / Double(sleep.sessions.count)

        let efficiencyScore = avgEfficiency * 50  // Max 50 points
        let durationScore = min(50, (avgDuration / 8.0) * 50)  // Max 50 points for 8 hours

        return efficiencyScore + durationScore
    }

    private func calculateActivityRegularity(steps: ProcessedStepsData) -> Double {
        // Calculate consistency of daily steps
        guard !steps.dataPoints.isEmpty else { return 0 }

        let values = steps.dataPoints.map { $0.originalValue }
        let mean = values.reduce(0.0, +) / Double(values.count)
        let stdDev = calculateStdDev(values: values, mean: mean)

        // Lower coefficient of variation = higher regularity
        let cv = stdDev / mean
        return max(0, 1 - cv)
    }

    private func calculateSleepScore(efficiency: Double, duration: Double) -> Double {
        let efficiencyScore = efficiency * 50
        let durationScore = min(50, (duration / 8.0) * 50)
        return efficiencyScore + durationScore
    }

    // MARK: - Metadata

    private func createMetadata() -> PreprocessingMetadata {
        return PreprocessingMetadata(
            normalizationMethod: config.normalizationMethod.description,
            outlierHandling: config.outlierHandling.description,
            smoothingEnabled: config.smoothingEnabled,
            timestamp: Date()
        )
    }
}

// MARK: - Supporting Types

struct ProcessedDataPoint {
    let timestamp: Date
    let originalValue: Double
    let normalizedValue: Double
    let isOutlier: Bool
}

struct ProcessedHeartRateData {
    let dataPoints: [ProcessedDataPoint]
    let statistics: VitalStatistics?
    let normalized: [Double]
}

struct ProcessedBloodPressureData {
    let systolic: ProcessedSeries
    let diastolic: ProcessedSeries
}

struct ProcessedSeries {
    let values: [Double]
    let statistics: VitalStatistics?
}

struct ProcessedStepsData {
    let dataPoints: [ProcessedDataPoint]
    let statistics: VitalStatistics?
    let normalized: [Double]
}

struct ProcessedSleepData {
    let sessions: [SleepSession]
    let statistics: VitalStatistics?
}

struct SleepSession {
    let date: Date
    let totalDurationHours: Double
    let asleepDurationHours: Double
    let deepSleepHours: Double
    let remSleepHours: Double
    let efficiency: Double
    let sleepScore: Double
}

struct VitalStatistics: Codable {
    let count: Int
    let mean: Double
    let median: Double
    let stdDev: Double
    let min: Double
    let max: Double
    let q25: Double
    let q75: Double
}

struct TemporalAggregations {
    let daily: [DailyAggregate]
}

struct DailyAggregate {
    let date: Date
    let heartRateMean: Double?
    let stepTotal: Int?
    let sleepDuration: Double?
}

struct EngineeredFeatures: Codable {
    let cardiovascularFitnessScore: Double
    let sleepQualityIndex: Double
    let activityRegularity: Double
}

struct PreprocessingMetadata: Codable {
    let normalizationMethod: String
    let outlierHandling: String
    let smoothingEnabled: Bool
    let timestamp: Date
}

struct AIHealthDataPayload {
    let heartRate: ProcessedHeartRateData
    let bloodPressure: ProcessedBloodPressureData
    let steps: ProcessedStepsData
    let sleep: ProcessedSleepData
    let aggregations: TemporalAggregations
    let features: EngineeredFeatures
    let preprocessingMetadata: PreprocessingMetadata
}

// MARK: - Extensions

extension HealthDataPreprocessor.NormalizationMethod {
    var description: String {
        switch self {
        case .zScore: return "z_score"
        case .minMax: return "min_max"
        case .robust: return "robust"
        case .none: return "none"
        }
    }
}

extension HealthDataPreprocessor.OutlierHandling {
    var description: String {
        switch self {
        case .remove: return "remove"
        case .cap: return "cap"
        case .flag: return "flag"
        case .none: return "none"
        }
    }
}
