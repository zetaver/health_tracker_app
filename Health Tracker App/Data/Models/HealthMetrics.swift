//
//  HealthMetrics.swift
//  Health Tracker App
//
//  Created by HealthKit Integration Pipeline
//

import Foundation
import HealthKit

// MARK: - Health Metric Types

/// Enumeration of all supported health metrics
enum HealthMetricType: String, CaseIterable {
    case heartRate
    case steps
    case bloodPressure
    case sleep
    case activeEnergy
    case restingHeartRate
    case heartRateVariability
    case oxygenSaturation
    case bodyTemperature
    case respiratoryRate

    /// Maps to corresponding HKQuantityTypeIdentifier or HKCategoryTypeIdentifier
    var healthKitIdentifier: HKObjectType? {
        switch self {
        case .heartRate:
            return HKQuantityType.quantityType(forIdentifier: .heartRate)
        case .steps:
            return HKQuantityType.quantityType(forIdentifier: .stepCount)
        case .bloodPressure:
            return nil // Blood pressure requires correlation type
        case .sleep:
            return HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
        case .activeEnergy:
            return HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        case .restingHeartRate:
            return HKQuantityType.quantityType(forIdentifier: .restingHeartRate)
        case .heartRateVariability:
            return HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .oxygenSaturation:
            return HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)
        case .bodyTemperature:
            return HKQuantityType.quantityType(forIdentifier: .bodyTemperature)
        case .respiratoryRate:
            return HKQuantityType.quantityType(forIdentifier: .respiratoryRate)
        }
    }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .heartRate: return "Heart Rate"
        case .steps: return "Steps"
        case .bloodPressure: return "Blood Pressure"
        case .sleep: return "Sleep"
        case .activeEnergy: return "Active Energy"
        case .restingHeartRate: return "Resting Heart Rate"
        case .heartRateVariability: return "Heart Rate Variability"
        case .oxygenSaturation: return "Oxygen Saturation"
        case .bodyTemperature: return "Body Temperature"
        case .respiratoryRate: return "Respiratory Rate"
        }
    }
}

// MARK: - Base Health Metric Protocol

protocol HealthMetric: Codable {
    var id: UUID { get }
    var timestamp: Date { get }
    var sourceDevice: String? { get }
    var metricType: HealthMetricType { get }
}

// MARK: - Heart Rate Metric

struct HeartRateMetric: HealthMetric {
    let id: UUID
    let timestamp: Date
    let beatsPerMinute: Double
    let sourceDevice: String?
    let metricType: HealthMetricType = .heartRate
    let context: HeartRateContext?

    enum HeartRateContext: String, Codable {
        case rest
        case active
        case recovery
        case unknown
    }

    init(id: UUID = UUID(),
         timestamp: Date,
         beatsPerMinute: Double,
         sourceDevice: String? = nil,
         context: HeartRateContext? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.beatsPerMinute = beatsPerMinute
        self.sourceDevice = sourceDevice
        self.context = context
    }
}

// MARK: - Steps Metric

struct StepsMetric: HealthMetric {
    let id: UUID
    let timestamp: Date
    let count: Int
    let sourceDevice: String?
    let metricType: HealthMetricType = .steps
    let duration: TimeInterval? // Duration over which steps were counted

    init(id: UUID = UUID(),
         timestamp: Date,
         count: Int,
         sourceDevice: String? = nil,
         duration: TimeInterval? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.count = count
        self.sourceDevice = sourceDevice
        self.duration = duration
    }
}

// MARK: - Blood Pressure Metric

struct BloodPressureMetric: HealthMetric {
    let id: UUID
    let timestamp: Date
    let systolic: Double // mmHg
    let diastolic: Double // mmHg
    let sourceDevice: String?
    let metricType: HealthMetricType = .bloodPressure

    var classification: BloodPressureClassification {
        if systolic < 120 && diastolic < 80 {
            return .normal
        } else if systolic < 130 && diastolic < 80 {
            return .elevated
        } else if systolic < 140 || diastolic < 90 {
            return .hypertensionStage1
        } else if systolic < 180 || diastolic < 120 {
            return .hypertensionStage2
        } else {
            return .hypertensiveCrisis
        }
    }

    enum BloodPressureClassification: String, Codable {
        case normal
        case elevated
        case hypertensionStage1
        case hypertensionStage2
        case hypertensiveCrisis
    }

    init(id: UUID = UUID(),
         timestamp: Date,
         systolic: Double,
         diastolic: Double,
         sourceDevice: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.systolic = systolic
        self.diastolic = diastolic
        self.sourceDevice = sourceDevice
    }
}

// MARK: - Sleep Metric

struct SleepMetric: HealthMetric {
    let id: UUID
    let timestamp: Date
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let stage: SleepStage
    let sourceDevice: String?
    let metricType: HealthMetricType = .sleep

    enum SleepStage: String, Codable {
        case inBed
        case asleep
        case awake
        case core
        case deep
        case rem
        case unknown

        init(from hkValue: HKCategoryValueSleepAnalysis) {
            switch hkValue {
            case .inBed:
                self = .inBed
            case .asleepUnspecified:
                self = .asleep
            case .awake:
                self = .awake
            case .asleepCore:
                self = .core
            case .asleepDeep:
                self = .deep
            case .asleepREM:
                self = .rem
            @unknown default:
                self = .unknown
            }
        }
    }

    init(id: UUID = UUID(),
         timestamp: Date,
         startDate: Date,
         endDate: Date,
         stage: SleepStage,
         sourceDevice: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.startDate = startDate
        self.endDate = endDate
        self.duration = endDate.timeIntervalSince(startDate)
        self.stage = stage
        self.sourceDevice = sourceDevice
    }
}

// MARK: - Aggregated Health Data

/// Aggregated health metrics for a specific time period
struct AggregatedHealthData: Codable {
    let startDate: Date
    let endDate: Date
    let heartRateAverage: Double?
    let heartRateMin: Double?
    let heartRateMax: Double?
    let totalSteps: Int?
    let sleepDuration: TimeInterval?
    let deepSleepDuration: TimeInterval?
    let remSleepDuration: TimeInterval?
    let activeEnergyBurned: Double?
    let restingHeartRate: Double?

    init(startDate: Date,
         endDate: Date,
         heartRateAverage: Double? = nil,
         heartRateMin: Double? = nil,
         heartRateMax: Double? = nil,
         totalSteps: Int? = nil,
         sleepDuration: TimeInterval? = nil,
         deepSleepDuration: TimeInterval? = nil,
         remSleepDuration: TimeInterval? = nil,
         activeEnergyBurned: Double? = nil,
         restingHeartRate: Double? = nil) {
        self.startDate = startDate
        self.endDate = endDate
        self.heartRateAverage = heartRateAverage
        self.heartRateMin = heartRateMin
        self.heartRateMax = heartRateMax
        self.totalSteps = totalSteps
        self.sleepDuration = sleepDuration
        self.deepSleepDuration = deepSleepDuration
        self.remSleepDuration = remSleepDuration
        self.activeEnergyBurned = activeEnergyBurned
        self.restingHeartRate = restingHeartRate
    }
}

// MARK: - Health Data Batch

/// Container for batched health data ready for API upload
struct HealthDataBatch: Codable {
    let batchId: UUID
    let userId: String
    let createdAt: Date
    let dataPoints: [HealthDataPoint]
    let checksum: String // For data integrity verification

    struct HealthDataPoint: Codable {
        let metricType: String
        let timestamp: Date
        let value: String // JSON-encoded metric data
        let deviceInfo: DeviceInfo?
    }

    struct DeviceInfo: Codable {
        let name: String?
        let model: String?
        let manufacturer: String?
    }

    init(userId: String, dataPoints: [HealthDataPoint]) {
        self.batchId = UUID()
        self.userId = userId
        self.createdAt = Date()
        self.dataPoints = dataPoints
        self.checksum = HealthDataBatch.generateChecksum(for: dataPoints)
    }

    private static func generateChecksum(for dataPoints: [HealthDataPoint]) -> String {
        let data = dataPoints.map { "\($0.timestamp.timeIntervalSince1970):\($0.value)" }.joined()
        return String(data.hashValue)
    }
}

// MARK: - Query Configuration

/// Configuration for HealthKit queries
struct HealthQueryConfiguration {
    let metricType: HealthMetricType
    let startDate: Date
    let endDate: Date
    let limit: Int?
    let sortAscending: Bool

    init(metricType: HealthMetricType,
         startDate: Date,
         endDate: Date,
         limit: Int? = nil,
         sortAscending: Bool = false) {
        self.metricType = metricType
        self.startDate = startDate
        self.endDate = endDate
        self.limit = limit
        self.sortAscending = sortAscending
    }

    /// Convenience initializer for last N days
    static func lastDays(_ days: Int, for metricType: HealthMetricType) -> HealthQueryConfiguration {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        return HealthQueryConfiguration(metricType: metricType, startDate: startDate, endDate: endDate)
    }

    /// Convenience initializer for today
    static func today(for metricType: HealthMetricType) -> HealthQueryConfiguration {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        return HealthQueryConfiguration(metricType: metricType, startDate: startDate, endDate: endDate)
    }
}
