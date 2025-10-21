//
//  AIHealthDataModels.swift
//  Health Tracker App
//
//  Data models optimized for AI/ML analysis (Azure OpenAI, Vertex AI)
//  HIPAA-compliant with de-identification and encryption support
//

import Foundation

// MARK: - Main AI Payload

/// Complete health data payload ready for AI analysis
struct AIAnalysisRequest: Codable {
    let schemaVersion: String
    let requestId: String
    let timestamp: Date
    let encryption: EncryptionMetadata?
    let integrity: IntegrityMetadata
    let audit: AuditMetadata
    let user: DeidentifiedUser
    let timeWindow: TimeWindow
    let vitals: VitalsData
    let aggregations: AggregatedData
    let features: FeatureSet
    let context: DataContext

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestId = "request_id"
        case timestamp, encryption, integrity, audit, user
        case timeWindow = "time_window"
        case vitals, aggregations, features, context
    }

    init(
        requestId: String = UUID().uuidString,
        user: DeidentifiedUser,
        timeWindow: TimeWindow,
        vitals: VitalsData,
        aggregations: AggregatedData,
        features: FeatureSet,
        context: DataContext,
        encryption: EncryptionMetadata? = nil
    ) {
        self.schemaVersion = "1.0"
        self.requestId = requestId
        self.timestamp = Date()
        self.encryption = encryption
        self.integrity = IntegrityMetadata(checksum: "", signature: "")
        self.audit = AuditMetadata(
            dataCollectionStart: timeWindow.startDate,
            dataCollectionEnd: timeWindow.endDate,
            processingTimestamp: Date(),
            purpose: "health_analysis",
            consentId: "consent_v2",
            retentionDays: 90
        )
        self.user = user
        self.timeWindow = timeWindow
        self.vitals = vitals
        self.aggregations = aggregations
        self.features = features
        self.context = context
    }
}

// MARK: - Metadata

struct EncryptionMetadata: Codable {
    let algorithm: String
    let keyId: String
    let iv: String
    let encrypted: Bool

    enum CodingKeys: String, CodingKey {
        case algorithm
        case keyId = "key_id"
        case iv, encrypted
    }
}

struct IntegrityMetadata: Codable {
    let checksum: String
    let signature: String
}

struct AuditMetadata: Codable {
    let dataCollectionStart: Date
    let dataCollectionEnd: Date
    let processingTimestamp: Date
    let purpose: String
    let consentId: String
    let retentionDays: Int

    enum CodingKeys: String, CodingKey {
        case dataCollectionStart = "data_collection_start"
        case dataCollectionEnd = "data_collection_end"
        case processingTimestamp = "processing_timestamp"
        case purpose
        case consentId = "consent_id"
        case retentionDays = "retention_days"
    }
}

// MARK: - De-identified User

struct DeidentifiedUser: Codable {
    let userId: String  // Hashed
    let demographics: Demographics
    let healthProfile: HealthProfile?
    let metadata: UserMetadata

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case demographics
        case healthProfile = "health_profile"
        case metadata
    }

    struct Demographics: Codable {
        let ageRange: String    // "30-40", not exact age
        let gender: String?     // Optional
        let heightCm: Double?
        let weightKg: Double?
        let bmi: Double?

        enum CodingKeys: String, CodingKey {
            case ageRange = "age_range"
            case gender
            case heightCm = "height_cm"
            case weightKg = "weight_kg"
            case bmi
        }
    }

    struct HealthProfile: Codable {
        let conditions: [String]?
        let medications: [String]?
        let activityLevel: String  // low, moderate, high, very_high

        enum CodingKeys: String, CodingKey {
            case conditions, medications
            case activityLevel = "activity_level"
        }
    }

    struct UserMetadata: Codable {
        let dataCollectionStart: Date
        let totalDaysActive: Int
        let consentVersion: String
        let privacyLevel: String

        enum CodingKeys: String, CodingKey {
            case dataCollectionStart = "data_collection_start"
            case totalDaysActive = "total_days_active"
            case consentVersion = "consent_version"
            case privacyLevel = "privacy_level"
        }
    }
}

// MARK: - Time Window

struct TimeWindow: Codable {
    let startDate: Date
    let endDate: Date
    let durationSeconds: TimeInterval
    let timezone: String
    let granularity: String  // raw, hourly, daily, weekly

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case durationSeconds = "duration_seconds"
        case timezone, granularity
    }

    init(startDate: Date, endDate: Date, timezone: String = "UTC", granularity: String = "daily") {
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = endDate.timeIntervalSince(startDate)
        self.timezone = timezone
        self.granularity = granularity
    }
}

// MARK: - Vitals Data

struct VitalsData: Codable {
    let heartRate: HeartRateData?
    let bloodPressure: BloodPressureData?
    let steps: StepsData?
    let sleep: SleepData?

    enum CodingKeys: String, CodingKey {
        case heartRate = "heart_rate"
        case bloodPressure = "blood_pressure"
        case steps, sleep
    }
}

struct HeartRateData: Codable {
    let unit: String
    let dataPoints: [HeartRateDataPoint]
    let statistics: VitalStatisticsData
    let derivedMetrics: HeartRateDerivedMetrics
    let anomalies: [AnomalyData]?

    enum CodingKeys: String, CodingKey {
        case unit
        case dataPoints = "data_points"
        case statistics
        case derivedMetrics = "derived_metrics"
        case anomalies
    }

    struct HeartRateDataPoint: Codable {
        let timestamp: Date
        let value: Double
        let context: String?  // resting, active, recovery
        let quality: String   // high, medium, low

        enum CodingKeys: String, CodingKey {
            case timestamp, value, context, quality
        }
    }

    struct HeartRateDerivedMetrics: Codable {
        let restingHeartRate: Double
        let maxHeartRateObserved: Double
        let heartRateVariabilitySDNN: Double
        let heartRateReserve: Double

        enum CodingKeys: String, CodingKey {
            case restingHeartRate = "resting_heart_rate"
            case maxHeartRateObserved = "max_heart_rate_observed"
            case heartRateVariabilitySDNN = "heart_rate_variability_sdnn"
            case heartRateReserve = "heart_rate_reserve"
        }
    }
}

struct BloodPressureData: Codable {
    let unit: String
    let dataPoints: [BloodPressureDataPoint]
    let statistics: BloodPressureStatistics
    let trends: TrendData

    enum CodingKeys: String, CodingKey {
        case unit
        case dataPoints = "data_points"
        case statistics, trends
    }

    struct BloodPressureDataPoint: Codable {
        let timestamp: Date
        let systolic: Double
        let diastolic: Double
        let meanArterialPressure: Double
        let pulsePressure: Double
        let classification: String

        enum CodingKeys: String, CodingKey {
            case timestamp, systolic, diastolic
            case meanArterialPressure = "mean_arterial_pressure"
            case pulsePressure = "pulse_pressure"
            case classification
        }
    }

    struct BloodPressureStatistics: Codable {
        let systolic: VitalStatisticsData
        let diastolic: VitalStatisticsData
    }
}

struct StepsData: Codable {
    let unit: String
    let dataPoints: [StepsDataPoint]
    let statistics: VitalStatisticsData
    let activityPatterns: ActivityPatterns

    enum CodingKeys: String, CodingKey {
        case unit
        case dataPoints = "data_points"
        case statistics
        case activityPatterns = "activity_patterns"
    }

    struct StepsDataPoint: Codable {
        let timestamp: Date
        let value: Int
        let durationSeconds: TimeInterval
        let activeMinutes: Int?
        let distanceMeters: Double?

        enum CodingKeys: String, CodingKey {
            case timestamp, value
            case durationSeconds = "duration_seconds"
            case activeMinutes = "active_minutes"
            case distanceMeters = "distance_meters"
        }
    }

    struct ActivityPatterns: Codable {
        let peakHours: [Int]
        let sedentaryHours: [Int]
        let mostActiveDay: String
        let weekendVsWeekdayRatio: Double

        enum CodingKeys: String, CodingKey {
            case peakHours = "peak_hours"
            case sedentaryHours = "sedentary_hours"
            case mostActiveDay = "most_active_day"
            case weekendVsWeekdayRatio = "weekend_vs_weekday_ratio"
        }
    }
}

struct SleepData: Codable {
    let dataPoints: [SleepDataPoint]
    let statistics: SleepStatistics
    let patterns: SleepPatterns

    enum CodingKeys: String, CodingKey {
        case dataPoints = "data_points"
        case statistics, patterns
    }

    struct SleepDataPoint: Codable {
        let date: String  // YYYY-MM-DD
        let startTime: Date
        let endTime: Date
        let totalDurationHours: Double
        let stages: SleepStages
        let qualityMetrics: SleepQualityMetrics

        enum CodingKeys: String, CodingKey {
            case date
            case startTime = "start_time"
            case endTime = "end_time"
            case totalDurationHours = "total_duration_hours"
            case stages
            case qualityMetrics = "quality_metrics"
        }
    }

    struct SleepStages: Codable {
        let awake: StageData
        let light: StageData
        let deep: StageData
        let rem: StageData

        struct StageData: Codable {
            let durationSeconds: TimeInterval
            let percentage: Double

            enum CodingKeys: String, CodingKey {
                case durationSeconds = "duration_seconds"
                case percentage
            }
        }
    }

    struct SleepQualityMetrics: Codable {
        let sleepEfficiency: Double
        let sleepLatencyMinutes: Int
        let wakeCount: Int
        let sleepScore: Int

        enum CodingKeys: String, CodingKey {
            case sleepEfficiency = "sleep_efficiency"
            case sleepLatencyMinutes = "sleep_latency_minutes"
            case wakeCount = "wake_count"
            case sleepScore = "sleep_score"
        }
    }

    struct SleepStatistics: Codable {
        let avgDurationHours: Double
        let avgEfficiency: Double
        let avgDeepSleepHours: Double
        let avgRemSleepHours: Double
        let consistencyScore: Double

        enum CodingKeys: String, CodingKey {
            case avgDurationHours = "avg_duration_hours"
            case avgEfficiency = "avg_efficiency"
            case avgDeepSleepHours = "avg_deep_sleep_hours"
            case avgRemSleepHours = "avg_rem_sleep_hours"
            case consistencyScore = "consistency_score"
        }
    }

    struct SleepPatterns: Codable {
        let avgBedtime: String
        let avgWakeTime: String
        let bedtimeRegularity: Double
        let weekendShiftHours: Double

        enum CodingKeys: String, CodingKey {
            case avgBedtime = "avg_bedtime"
            case avgWakeTime = "avg_wake_time"
            case bedtimeRegularity = "bedtime_regularity"
            case weekendShiftHours = "weekend_shift_hours"
        }
    }
}

// MARK: - Aggregated Data

struct AggregatedData: Codable {
    let daily: [DailyAggregateData]
    let weekly: [WeeklyAggregateData]?

    struct DailyAggregateData: Codable {
        let date: String
        let dayOfWeek: String
        let isWeekend: Bool
        let heartRate: AggregateMetrics?
        let steps: AggregateMetrics?
        let sleep: SleepAggregate?
        let overallHealthScore: Double?

        enum CodingKeys: String, CodingKey {
            case date
            case dayOfWeek = "day_of_week"
            case isWeekend = "is_weekend"
            case heartRate = "heart_rate"
            case steps, sleep
            case overallHealthScore = "overall_health_score"
        }
    }

    struct WeeklyAggregateData: Codable {
        let weekStart: String
        let weekNumber: Int
        let averages: WeeklyAverages
        let trends: WeeklyTrends

        enum CodingKeys: String, CodingKey {
            case weekStart = "week_start"
            case weekNumber = "week_number"
            case averages, trends
        }

        struct WeeklyAverages: Codable {
            let heartRate: Double
            let steps: Double
            let sleepHours: Double

            enum CodingKeys: String, CodingKey {
                case heartRate = "heart_rate"
                case steps
                case sleepHours = "sleep_hours"
            }
        }

        struct WeeklyTrends: Codable {
            let heartRateChange: Double
            let stepsChange: Double
            let sleepChange: Double

            enum CodingKeys: String, CodingKey {
                case heartRateChange = "heart_rate_change"
                case stepsChange = "steps_change"
                case sleepChange = "sleep_change"
            }
        }
    }

    struct AggregateMetrics: Codable {
        let mean: Double
        let min: Double
        let max: Double
        let count: Int
    }

    struct SleepAggregate: Codable {
        let durationHours: Double
        let efficiency: Double
        let score: Int

        enum CodingKeys: String, CodingKey {
            case durationHours = "duration_hours"
            case efficiency, score
        }
    }
}

// MARK: - Feature Set

struct FeatureSet: Codable {
    let derived: DerivedFeatures
    let statistical: StatisticalFeatures
    let temporal: TemporalFeatures

    struct DerivedFeatures: Codable {
        let cardiovascularFitnessScore: Double
        let heartRateRecoveryScore: Double
        let sleepQualityIndex: Double
        let activityRegularity: Double
        let vitalityScore: Double
        let stressScore: Double

        enum CodingKeys: String, CodingKey {
            case cardiovascularFitnessScore = "cardiovascular_fitness_score"
            case heartRateRecoveryScore = "heart_rate_recovery_score"
            case sleepQualityIndex = "sleep_quality_index"
            case activityRegularity = "activity_regularity"
            case vitalityScore = "vitality_score"
            case stressScore = "stress_score"
        }
    }

    struct StatisticalFeatures: Codable {
        let heartRateVariability: HRVFeatures
        let bloodPressureVariability: BPVariability

        enum CodingKeys: String, CodingKey {
            case heartRateVariability = "heart_rate_variability"
            case bloodPressureVariability = "blood_pressure_variability"
        }

        struct HRVFeatures: Codable {
            let sdnn: Double
            let rmssd: Double
            let pnn50: Double

            enum CodingKeys: String, CodingKey {
                case sdnn, rmssd, pnn50
            }
        }

        struct BPVariability: Codable {
            let coefficientOfVariation: Double

            enum CodingKeys: String, CodingKey {
                case coefficientOfVariation = "coefficient_of_variation"
            }
        }
    }

    struct TemporalFeatures: Codable {
        let dayOfWeekEncoded: [Int]
        let hourOfDaySin: Double
        let hourOfDayCos: Double
        let isWeekend: Bool
        let isWorkHours: Bool
        let season: String

        enum CodingKeys: String, CodingKey {
            case dayOfWeekEncoded = "day_of_week_encoded"
            case hourOfDaySin = "hour_of_day_sin"
            case hourOfDayCos = "hour_of_day_cos"
            case isWeekend = "is_weekend"
            case isWorkHours = "is_work_hours"
            case season
        }
    }
}

// MARK: - Supporting Types

struct VitalStatisticsData: Codable {
    let count: Int
    let mean: Double
    let median: Double
    let stdDev: Double
    let min: Double
    let max: Double
    let percentile25: Double
    let percentile75: Double

    enum CodingKeys: String, CodingKey {
        case count, mean, median
        case stdDev = "std_dev"
        case min, max
        case percentile25 = "percentile_25"
        case percentile75 = "percentile_75"
    }
}

struct TrendData: Codable {
    let systolicTrend: String
    let diastolicTrend: String
    let trendConfidence: Double
    let slopePerDay: Double

    enum CodingKeys: String, CodingKey {
        case systolicTrend = "systolic_trend"
        case diastolicTrend = "diastolic_trend"
        case trendConfidence = "trend_confidence"
        case slopePerDay = "slope_per_day"
    }
}

struct AnomalyData: Codable {
    let timestamp: Date
    let value: Double
    let type: String
    let confidence: Double
    let context: String?
}

struct DataContext: Codable {
    let dataQuality: DataQuality
    let deviceInfo: DeviceInfo
    let preprocessing: PreprocessingInfo

    enum CodingKeys: String, CodingKey {
        case dataQuality = "data_quality"
        case deviceInfo = "device_info"
        case preprocessing
    }

    struct DataQuality: Codable {
        let completeness: Double
        let accuracyScore: Double
        let consistencyScore: Double
        let reliability: String

        enum CodingKeys: String, CodingKey {
            case completeness
            case accuracyScore = "accuracy_score"
            case consistencyScore = "consistency_score"
            case reliability
        }
    }

    struct DeviceInfo: Codable {
        let primaryDevice: String
        let iosVersion: String
        let healthkitVersion: String

        enum CodingKeys: String, CodingKey {
            case primaryDevice = "primary_device"
            case iosVersion = "ios_version"
            case healthkitVersion = "healthkit_version"
        }
    }

    struct PreprocessingInfo: Codable {
        let normalizationMethod: String
        let outlierHandling: String
        let missingDataStrategy: String

        enum CodingKeys: String, CodingKey {
            case normalizationMethod = "normalization_method"
            case outlierHandling = "outlier_handling"
            case missingDataStrategy = "missing_data_strategy"
        }
    }
}

// MARK: - Azure OpenAI Specific

struct AzureOpenAIRequest: Codable {
    let model: String
    let task: String
    let context: OpenAIContext
    let dataSummary: DataSummary
    let requestedInsights: [String]

    enum CodingKeys: String, CodingKey {
        case model, task, context
        case dataSummary = "data_summary"
        case requestedInsights = "requested_insights"
    }

    struct OpenAIContext: Codable {
        let userProfile: UserProfile

        enum CodingKeys: String, CodingKey {
            case userProfile = "user_profile"
        }

        struct UserProfile: Codable {
            let ageRange: String
            let activityLevel: String
            let healthGoals: [String]

            enum CodingKeys: String, CodingKey {
                case ageRange = "age_range"
                case activityLevel = "activity_level"
                case healthGoals = "health_goals"
            }
        }
    }

    struct DataSummary: Codable {
        let period: String
        let keyMetrics: KeyMetrics
        let notablePatterns: [String]
        let anomalies: [String]

        enum CodingKeys: String, CodingKey {
            case period
            case keyMetrics = "key_metrics"
            case notablePatterns = "notable_patterns"
            case anomalies
        }

        struct KeyMetrics: Codable {
            let avgHeartRate: Double
            let avgRestingHR: Double
            let avgSteps: Double
            let avgSleepHours: Double
            let sleepEfficiency: Double

            enum CodingKeys: String, CodingKey {
                case avgHeartRate = "avg_heart_rate"
                case avgRestingHR = "avg_resting_hr"
                case avgSteps = "avg_steps"
                case avgSleepHours = "avg_sleep_hours"
                case sleepEfficiency = "sleep_efficiency"
            }
        }
    }
}

// MARK: - Vertex AI Specific

struct VertexAIPredictionRequest: Codable {
    let instances: [PredictionInstance]
    let parameters: PredictionParameters?

    struct PredictionInstance: Codable {
        let userFeatures: UserFeatures
        let vitalFeatures: VitalFeatures
        let temporalFeatures: TemporalFeatures
        let derivedFeatures: DerivedFeatures
        let timeSeries: TimeSeriesFeatures?

        enum CodingKeys: String, CodingKey {
            case userFeatures = "user_features"
            case vitalFeatures = "vital_features"
            case temporalFeatures = "temporal_features"
            case derivedFeatures = "derived_features"
            case timeSeries = "time_series"
        }

        struct UserFeatures: Codable {
            let ageRangeEncoded: Int
            let genderEncoded: Int
            let bmi: Double
            let activityLevelEncoded: Int

            enum CodingKeys: String, CodingKey {
                case ageRangeEncoded = "age_range_encoded"
                case genderEncoded = "gender_encoded"
                case bmi
                case activityLevelEncoded = "activity_level_encoded"
            }
        }

        struct VitalFeatures: Codable {
            let heartRateMean: Double
            let heartRateStd: Double
            let heartRateMin: Double
            let heartRateMax: Double
            let restingHeartRate: Double
            let systolicMean: Double
            let diastolicMean: Double
            let stepsDailyAvg: Double
            let sleepDurationAvg: Double
            let sleepEfficiencyAvg: Double

            enum CodingKeys: String, CodingKey {
                case heartRateMean = "heart_rate_mean"
                case heartRateStd = "heart_rate_std"
                case heartRateMin = "heart_rate_min"
                case heartRateMax = "heart_rate_max"
                case restingHeartRate = "resting_heart_rate"
                case systolicMean = "systolic_mean"
                case diastolicMean = "diastolic_mean"
                case stepsDailyAvg = "steps_daily_avg"
                case sleepDurationAvg = "sleep_duration_avg"
                case sleepEfficiencyAvg = "sleep_efficiency_avg"
            }
        }

        struct TemporalFeatures: Codable {
            let dayOfWeekSin: Double
            let dayOfWeekCos: Double
            let hourOfDaySin: Double
            let hourOfDayCos: Double
            let isWeekend: Int

            enum CodingKeys: String, CodingKey {
                case dayOfWeekSin = "day_of_week_sin"
                case dayOfWeekCos = "day_of_week_cos"
                case hourOfDaySin = "hour_of_day_sin"
                case hourOfDayCos = "hour_of_day_cos"
                case isWeekend = "is_weekend"
            }
        }

        struct DerivedFeatures: Codable {
            let cardiovascularFitnessScore: Double
            let sleepQualityIndex: Double
            let activityRegularity: Double
            let stressScore: Double

            enum CodingKeys: String, CodingKey {
                case cardiovascularFitnessScore = "cardiovascular_fitness_score"
                case sleepQualityIndex = "sleep_quality_index"
                case activityRegularity = "activity_regularity"
                case stressScore = "stress_score"
            }
        }

        struct TimeSeriesFeatures: Codable {
            let heartRateSequence: [Double]
            let stepsSequence: [Double]
            let sleepHoursSequence: [Double]

            enum CodingKeys: String, CodingKey {
                case heartRateSequence = "heart_rate_sequence"
                case stepsSequence = "steps_sequence"
                case sleepHoursSequence = "sleep_hours_sequence"
            }
        }
    }

    struct PredictionParameters: Codable {
        let predictionHorizon: String
        let confidenceThreshold: Double

        enum CodingKeys: String, CodingKey {
            case predictionHorizon = "prediction_horizon"
            case confidenceThreshold = "confidence_threshold"
        }
    }
}
