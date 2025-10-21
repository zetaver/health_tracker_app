# AI Integration Guide

Complete guide for integrating HealthKit data with Azure OpenAI and Google Vertex AI for health insights and predictions.

## Table of Contents

1. [Overview](#overview)
2. [Data Preparation Pipeline](#data-preparation-pipeline)
3. [Azure OpenAI Integration](#azure-openai-integration)
4. [Google Vertex AI Integration](#google-vertex-ai-integration)
5. [Example JSON Payloads](#example-json-payloads)
6. [HIPAA Compliance](#hipaa-compliance)
7. [Best Practices](#best-practices)

---

## Overview

### AI Analysis Workflow

```
┌─────────────────────────────────────────────────────────┐
│ 1. Fetch Health Data from HealthKit                    │
│    - Heart rate, steps, blood pressure, sleep          │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│ 2. Preprocess Data                                      │
│    - Normalize (z-score, min-max)                      │
│    - Handle outliers (cap, remove, flag)               │
│    - Fill missing data (interpolation)                 │
│    - Smooth (moving average)                           │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│ 3. Engineer Features                                    │
│    - Cardiovascular fitness score                      │
│    - Sleep quality index                               │
│    - Activity regularity                               │
│    - HRV metrics                                       │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│ 4. Create AI Payload                                    │
│    - Serialize to JSON                                  │
│    - Add metadata (audit, encryption)                  │
│    - De-identify user data                             │
└────────────────────────┬────────────────────────────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
┌────────▼────────┐           ┌──────────▼──────────┐
│ Azure OpenAI    │           │  Google Vertex AI   │
│ GPT-4           │           │  Custom Models      │
│ Health Insights │           │  Predictions        │
└─────────────────┘           └─────────────────────┘
```

---

## Data Preparation Pipeline

### Step 1: Fetch HealthKit Data

```swift
import Foundation

class AIHealthDataService {
    private let healthManager: HealthKitManager
    private let preprocessor: HealthDataPreprocessor
    private let authManager: AuthenticationManager

    init(healthManager: HealthKitManager, authManager: AuthenticationManager) {
        self.healthManager = healthManager
        self.authManager = authManager
        self.preprocessor = HealthDataPreprocessor(
            config: .aiOptimized  // Optimized for AI
        )
    }

    /// Prepares health data for AI analysis
    func prepareDataForAI(days: Int = 7) async throws -> AIAnalysisRequest {
        // 1. Define time window
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!

        // 2. Fetch raw health data
        async let heartRate = healthManager.fetchHeartRate(from: startDate, to: endDate)
        async let bloodPressure = healthManager.fetchBloodPressure(from: startDate, to: endDate)
        async let steps = healthManager.fetchSteps(from: startDate, to: endDate)
        async let sleep = healthManager.fetchSleep(from: startDate, to: endDate)

        let (hr, bp, st, sl) = try await (heartRate, bloodPressure, steps, sleep)

        // 3. Preprocess data
        let preprocessed = try await preprocessor.preprocessHealthData(
            heartRate: hr,
            bloodPressure: bp,
            steps: st,
            sleep: sl
        )

        // 4. Build AI payload
        let payload = buildAIPayload(
            preprocessed: preprocessed,
            timeWindow: TimeWindow(startDate: startDate, endDate: endDate)
        )

        return payload
    }

    private func buildAIPayload(
        preprocessed: AIHealthDataPayload,
        timeWindow: TimeWindow
    ) -> AIAnalysisRequest {
        // Create de-identified user
        let user = DeidentifiedUser(
            userId: hashUserId(authManager.currentUser?.id ?? ""),
            demographics: createDemographics(),
            healthProfile: createHealthProfile(),
            metadata: createUserMetadata()
        )

        // Build vitals data
        let vitals = buildVitalsData(preprocessed: preprocessed)

        // Build aggregations
        let aggregations = buildAggregations(preprocessed: preprocessed)

        // Build features
        let features = buildFeatures(preprocessed: preprocessed)

        // Build context
        let context = buildContext()

        return AIAnalysisRequest(
            user: user,
            timeWindow: timeWindow,
            vitals: vitals,
            aggregations: aggregations,
            features: features,
            context: context
        )
    }

    // Helper methods to build each section
    private func buildVitalsData(preprocessed: AIHealthDataPayload) -> VitalsData {
        // Convert preprocessed data to AI format
        let heartRateData = HeartRateData(
            unit: "bpm",
            dataPoints: preprocessed.heartRate.dataPoints.map { point in
                HeartRateData.HeartRateDataPoint(
                    timestamp: point.timestamp,
                    value: point.originalValue,
                    context: "unknown",
                    quality: point.isOutlier ? "low" : "high"
                )
            },
            statistics: convertStatistics(preprocessed.heartRate.statistics),
            derivedMetrics: HeartRateData.HeartRateDerivedMetrics(
                restingHeartRate: calculateRestingHR(preprocessed.heartRate),
                maxHeartRateObserved: preprocessed.heartRate.statistics?.max ?? 0,
                heartRateVariabilitySDNN: calculateHRV(preprocessed.heartRate),
                heartRateReserve: 220 - 35  // Simplified
            ),
            anomalies: nil
        )

        return VitalsData(
            heartRate: heartRateData,
            bloodPressure: nil,  // Similar conversion
            steps: nil,
            sleep: nil
        )
    }

    private func convertStatistics(_ stats: VitalStatistics?) -> VitalStatisticsData {
        guard let stats = stats else {
            return VitalStatisticsData(count: 0, mean: 0, median: 0, stdDev: 0, min: 0, max: 0, percentile25: 0, percentile75: 0)
        }

        return VitalStatisticsData(
            count: stats.count,
            mean: stats.mean,
            median: stats.median,
            stdDev: stats.stdDev,
            min: stats.min,
            max: stats.max,
            percentile25: stats.q25,
            percentile75: stats.q75
        )
    }

    // De-identification
    private func hashUserId(_ userId: String) -> String {
        // Use SHA-256 to hash the user ID
        return "usr_" + userId.sha256Hash.prefix(16)
    }

    private func createDemographics() -> DeidentifiedUser.Demographics {
        return DeidentifiedUser.Demographics(
            ageRange: "30-40",  // Range instead of exact age
            gender: "M",
            heightCm: 175.0,
            weightKg: 70.0,
            bmi: 22.9
        )
    }

    private func createHealthProfile() -> DeidentifiedUser.HealthProfile {
        return DeidentifiedUser.HealthProfile(
            conditions: nil,
            medications: nil,
            activityLevel: "moderate"
        )
    }

    private func createUserMetadata() -> DeidentifiedUser.UserMetadata {
        return DeidentifiedUser.UserMetadata(
            dataCollectionStart: Date().addingTimeInterval(-90 * 24 * 3600),
            totalDaysActive: 90,
            consentVersion: "2.0",
            privacyLevel: "standard"
        )
    }

    // Additional helper methods...
    private func buildAggregations(preprocessed: AIHealthDataPayload) -> AggregatedData {
        // Implementation
        return AggregatedData(daily: [], weekly: nil)
    }

    private func buildFeatures(preprocessed: AIHealthDataPayload) -> FeatureSet {
        return FeatureSet(
            derived: FeatureSet.DerivedFeatures(
                cardiovascularFitnessScore: preprocessed.features.cardiovascularFitnessScore,
                heartRateRecoveryScore: 75.0,
                sleepQualityIndex: preprocessed.features.sleepQualityIndex,
                activityRegularity: preprocessed.features.activityRegularity,
                vitalityScore: 75.0,
                stressScore: 30.0
            ),
            statistical: FeatureSet.StatisticalFeatures(
                heartRateVariability: FeatureSet.StatisticalFeatures.HRVFeatures(
                    sdnn: 45.0,
                    rmssd: 38.0,
                    pnn50: 12.0
                ),
                bloodPressureVariability: FeatureSet.StatisticalFeatures.BPVariability(
                    coefficientOfVariation: 0.08
                )
            ),
            temporal: FeatureSet.TemporalFeatures(
                dayOfWeekEncoded: [0, 1, 0, 0, 0, 0, 0],
                hourOfDaySin: 0.5,
                hourOfDayCos: 0.866,
                isWeekend: false,
                isWorkHours: true,
                season: "winter"
            )
        )
    }

    private func buildContext() -> DataContext {
        return DataContext(
            dataQuality: DataContext.DataQuality(
                completeness: 0.95,
                accuracyScore: 0.92,
                consistencyScore: 0.88,
                reliability: "high"
            ),
            deviceInfo: DataContext.DeviceInfo(
                primaryDevice: "Apple Watch Series 9",
                iosVersion: "17.5",
                healthkitVersion: "17.0"
            ),
            preprocessing: DataContext.PreprocessingInfo(
                normalizationMethod: "z_score",
                outlierHandling: "cap",
                missingDataStrategy: "interpolation"
            )
        )
    }

    private func calculateRestingHR(_ hr: ProcessedHeartRateData) -> Double {
        let sortedValues = hr.dataPoints.map { $0.originalValue }.sorted()
        let bottomQuartile = sortedValues.prefix(sortedValues.count / 4)
        return bottomQuartile.reduce(0.0, +) / Double(bottomQuartile.count)
    }

    private func calculateHRV(_ hr: ProcessedHeartRateData) -> Double {
        // Simplified HRV calculation
        return hr.statistics?.stdDev ?? 0
    }
}

// String extension for SHA-256
extension String {
    var sha256Hash: String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
```

---

## Azure OpenAI Integration

### Step 1: Create OpenAI-Specific Request

```swift
extension AIHealthDataService {
    /// Creates a request optimized for Azure OpenAI GPT models
    func createOpenAIRequest(aiPayload: AIAnalysisRequest) -> AzureOpenAIRequest {
        // Extract key metrics for summary
        let heartRateStats = aiPayload.vitals.heartRate?.statistics
        let stepsStats = aiPayload.vitals.steps?.statistics
        let sleepStats = aiPayload.vitals.sleep?.statistics

        let keyMetrics = AzureOpenAIRequest.DataSummary.KeyMetrics(
            avgHeartRate: heartRateStats?.mean ?? 0,
            avgRestingHR: aiPayload.vitals.heartRate?.derivedMetrics.restingHeartRate ?? 0,
            avgSteps: stepsStats?.mean ?? 0,
            avgSleepHours: sleepStats?.mean ?? 0,
            sleepEfficiency: aiPayload.vitals.sleep?.statistics.avgEfficiency ?? 0
        )

        let dataSummary = AzureOpenAIRequest.DataSummary(
            period: "7_days",
            keyMetrics: keyMetrics,
            notablePatterns: extractPatterns(aiPayload),
            anomalies: extractAnomalies(aiPayload)
        )

        return AzureOpenAIRequest(
            model: "gpt-4",
            task: "health_insights",
            context: AzureOpenAIRequest.OpenAIContext(
                userProfile: AzureOpenAIRequest.OpenAIContext.UserProfile(
                    ageRange: aiPayload.user.demographics.ageRange,
                    activityLevel: aiPayload.user.healthProfile?.activityLevel ?? "moderate",
                    healthGoals: ["improve_sleep", "increase_activity"]
                )
            ),
            dataSummary: dataSummary,
            requestedInsights: [
                "overall_health_assessment",
                "personalized_recommendations",
                "risk_factors",
                "trend_analysis"
            ]
        )
    }

    private func extractPatterns(_ payload: AIAnalysisRequest) -> [String] {
        var patterns: [String] = []

        // Analyze daily aggregates for patterns
        if let daily = payload.aggregations.daily.first {
            if let hr = daily.heartRate?.mean {
                if hr > 80 {
                    patterns.append("Elevated average heart rate (\(Int(hr)) bpm)")
                }
            }
        }

        return patterns
    }

    private func extractAnomalies(_ payload: AIAnalysisRequest) -> [String] {
        var anomalies: [String] = []

        // Check for anomalies
        if let hrAnomalies = payload.vitals.heartRate?.anomalies {
            for anomaly in hrAnomalies {
                anomalies.append("Heart rate spike: \(Int(anomaly.value)) bpm at \(formatTime(anomaly.timestamp))")
            }
        }

        return anomalies
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
```

### Step 2: Send to Azure OpenAI

```swift
extension AIHealthDataService {
    /// Sends request to Azure OpenAI for analysis
    func getAIInsights() async throws -> String {
        // 1. Prepare data
        let aiPayload = try await prepareDataForAI(days: 7)

        // 2. Create OpenAI request
        let openAIRequest = createOpenAIRequest(aiPayload: aiPayload)

        // 3. Build prompt
        let prompt = buildOpenAIPrompt(request: openAIRequest)

        // 4. Send to Azure OpenAI
        let insights = try await sendToAzureOpenAI(prompt: prompt)

        return insights
    }

    private func buildOpenAIPrompt(request: AzureOpenAIRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try! encoder.encode(request)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        return """
        You are a health analysis AI. Analyze the following health data and provide insights:

        \(jsonString)

        Please provide:
        1. Overall health assessment
        2. Personalized recommendations
        3. Potential risk factors
        4. Trend analysis

        Format your response as structured JSON.
        """
    }

    private func sendToAzureOpenAI(prompt: String) async throws -> String {
        // Azure OpenAI API endpoint
        let endpoint = "https://your-resource.openai.azure.com/openai/deployments/gpt-4/chat/completions?api-version=2024-02-15-preview"

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SecureConfigurationManager.shared.getSecureValue(key: "AZURE_OPENAI_API_KEY"), forHTTPHeaderField: "api-key")

        let requestBody: [String: Any] = [
            "messages": [
                ["role": "system", "content": "You are a health analysis AI."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 2000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: nil)
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let choices = json["choices"] as! [[String: Any]]
        let message = choices[0]["message"] as! [String: Any]
        let content = message["content"] as! String

        return content
    }
}
```

---

## Google Vertex AI Integration

### Step 1: Create Vertex AI Request

```swift
extension AIHealthDataService {
    /// Creates a request for Google Vertex AI prediction
    func createVertexAIRequest(aiPayload: AIAnalysisRequest) -> VertexAIPredictionRequest {
        // Extract features for prediction
        let userFeatures = VertexAIPredictionRequest.PredictionInstance.UserFeatures(
            ageRangeEncoded: encodeAgeRange(aiPayload.user.demographics.ageRange),
            genderEncoded: encodeGender(aiPayload.user.demographics.gender),
            bmi: aiPayload.user.demographics.bmi ?? 0,
            activityLevelEncoded: encodeActivityLevel(aiPayload.user.healthProfile?.activityLevel ?? "moderate")
        )

        let vitalFeatures = VertexAIPredictionRequest.PredictionInstance.VitalFeatures(
            heartRateMean: aiPayload.vitals.heartRate?.statistics.mean ?? 0,
            heartRateStd: aiPayload.vitals.heartRate?.statistics.stdDev ?? 0,
            heartRateMin: aiPayload.vitals.heartRate?.statistics.min ?? 0,
            heartRateMax: aiPayload.vitals.heartRate?.statistics.max ?? 0,
            restingHeartRate: aiPayload.vitals.heartRate?.derivedMetrics.restingHeartRate ?? 0,
            systolicMean: aiPayload.vitals.bloodPressure?.statistics.systolic.mean ?? 0,
            diastolicMean: aiPayload.vitals.bloodPressure?.statistics.diastolic.mean ?? 0,
            stepsDailyAvg: aiPayload.vitals.steps?.statistics.mean ?? 0,
            sleepDurationAvg: aiPayload.vitals.sleep?.statistics.avgDurationHours ?? 0,
            sleepEfficiencyAvg: aiPayload.vitals.sleep?.statistics.avgEfficiency ?? 0
        )

        let temporalFeatures = VertexAIPredictionRequest.PredictionInstance.TemporalFeatures(
            dayOfWeekSin: aiPayload.features.temporal.hourOfDaySin,
            dayOfWeekCos: aiPayload.features.temporal.hourOfDayCos,
            hourOfDaySin: 0.0,
            hourOfDayCos: 1.0,
            isWeekend: aiPayload.features.temporal.isWeekend ? 1 : 0
        )

        let derivedFeatures = VertexAIPredictionRequest.PredictionInstance.DerivedFeatures(
            cardiovascularFitnessScore: aiPayload.features.derived.cardiovascularFitnessScore,
            sleepQualityIndex: aiPayload.features.derived.sleepQualityIndex,
            activityRegularity: aiPayload.features.derived.activityRegularity,
            stressScore: aiPayload.features.derived.stressScore
        )

        let instance = VertexAIPredictionRequest.PredictionInstance(
            userFeatures: userFeatures,
            vitalFeatures: vitalFeatures,
            temporalFeatures: temporalFeatures,
            derivedFeatures: derivedFeatures,
            timeSeries: nil  // Optional
        )

        return VertexAIPredictionRequest(
            instances: [instance],
            parameters: VertexAIPredictionRequest.PredictionParameters(
                predictionHorizon: "7_days",
                confidenceThreshold: 0.8
            )
        )
    }

    private func encodeAgeRange(_ range: String) -> Int {
        switch range {
        case "18-25": return 0
        case "26-35": return 1
        case "36-45": return 2
        case "46-55": return 3
        case "56-65": return 4
        default: return 5
        }
    }

    private func encodeGender(_ gender: String?) -> Int {
        switch gender {
        case "M": return 0
        case "F": return 1
        default: return 2
        }
    }

    private func encodeActivityLevel(_ level: String) -> Int {
        switch level {
        case "low": return 0
        case "moderate": return 1
        case "high": return 2
        case "very_high": return 3
        default: return 1
        }
    }
}
```

### Step 2: Send to Vertex AI

```swift
extension AIHealthDataService {
    /// Sends prediction request to Google Vertex AI
    func getPredictions() async throws -> [String: Any] {
        // 1. Prepare data
        let aiPayload = try await prepareDataForAI(days: 7)

        // 2. Create Vertex AI request
        let vertexRequest = createVertexAIRequest(aiPayload: aiPayload)

        // 3. Send to Vertex AI
        let predictions = try await sendToVertexAI(request: vertexRequest)

        return predictions
    }

    private func sendToVertexAI(request: VertexAIPredictionRequest) async throws -> [String: Any] {
        // Vertex AI endpoint
        let projectId = "your-project-id"
        let region = "us-central1"
        let endpointId = "your-endpoint-id"
        let endpoint = "https://\(region)-aiplatform.googleapis.com/v1/projects/\(projectId)/locations/\(region)/endpoints/\(endpointId):predict"

        var urlRequest = URLRequest(url: URL(string: endpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Get access token from Google Auth
        let accessToken = try await getGoogleAccessToken()
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "VertexAI", code: -1, userInfo: nil)
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json
    }

    private func getGoogleAccessToken() async throws -> String {
        // Implementation for Google OAuth token
        // In production, use Google Sign-In SDK or service account
        return "your-access-token"
    }
}
```

---

## Example JSON Payloads

### Complete AI Analysis Request

```json
{
  "schema_version": "1.0",
  "request_id": "req_abc123def456",
  "timestamp": "2024-01-08T12:00:00Z",

  "encryption": {
    "algorithm": "AES-256-GCM",
    "key_id": "key_v1_prod",
    "iv": "base64_encoded_iv",
    "encrypted": true
  },

  "integrity": {
    "checksum": "sha256_hash_of_payload",
    "signature": "hmac_sha256_signature"
  },

  "audit": {
    "data_collection_start": "2024-01-01T00:00:00Z",
    "data_collection_end": "2024-01-07T23:59:59Z",
    "processing_timestamp": "2024-01-08T11:59:30Z",
    "purpose": "health_analysis",
    "consent_id": "consent_v2_user123",
    "retention_days": 90
  },

  "user": {
    "user_id": "usr_hashed_abc123",
    "demographics": {
      "age_range": "30-40",
      "gender": "M",
      "height_cm": 175.0,
      "weight_kg": 70.0,
      "bmi": 22.9
    },
    "health_profile": {
      "activity_level": "moderate"
    },
    "metadata": {
      "data_collection_start": "2024-01-01T00:00:00Z",
      "total_days_active": 90,
      "consent_version": "2.0",
      "privacy_level": "standard"
    }
  },

  "time_window": {
    "start_date": "2024-01-01T00:00:00Z",
    "end_date": "2024-01-07T23:59:59Z",
    "duration_seconds": 604800,
    "timezone": "UTC",
    "granularity": "daily"
  },

  "vitals": {
    "heart_rate": {
      "unit": "bpm",
      "data_points": [
        {
          "timestamp": "2024-01-01T08:30:00Z",
          "value": 72.0,
          "context": "resting",
          "quality": "high"
        }
      ],
      "statistics": {
        "count": 1440,
        "mean": 75.2,
        "median": 74.0,
        "std_dev": 12.5,
        "min": 52.0,
        "max": 158.0,
        "percentile_25": 68.0,
        "percentile_75": 82.0
      },
      "derived_metrics": {
        "resting_heart_rate": 58.0,
        "max_heart_rate_observed": 158.0,
        "heart_rate_variability_sdnn": 45.2,
        "heart_rate_reserve": 100.0
      },
      "anomalies": []
    }
  },

  "aggregations": {
    "daily": [
      {
        "date": "2024-01-01",
        "day_of_week": "monday",
        "is_weekend": false,
        "heart_rate": {
          "mean": 75.2,
          "min": 52.0,
          "max": 158.0,
          "count": 1440
        },
        "steps": {
          "mean": 8542,
          "min": 0,
          "max": 8542,
          "count": 1
        },
        "overall_health_score": 78.5
      }
    ]
  },

  "features": {
    "derived": {
      "cardiovascular_fitness_score": 78.5,
      "heart_rate_recovery_score": 82.0,
      "sleep_quality_index": 0.85,
      "activity_regularity": 0.75,
      "vitality_score": 75.5,
      "stress_score": 32.0
    },
    "statistical": {
      "heart_rate_variability": {
        "sdnn": 45.2,
        "rmssd": 38.5,
        "pnn50": 12.3
      },
      "blood_pressure_variability": {
        "coefficient_of_variation": 0.08
      }
    },
    "temporal": {
      "day_of_week_encoded": [0, 1, 0, 0, 0, 0, 0],
      "hour_of_day_sin": 0.5,
      "hour_of_day_cos": 0.866,
      "is_weekend": false,
      "is_work_hours": true,
      "season": "winter"
    }
  },

  "context": {
    "data_quality": {
      "completeness": 0.95,
      "accuracy_score": 0.92,
      "consistency_score": 0.88,
      "reliability": "high"
    },
    "device_info": {
      "primary_device": "Apple Watch Series 9",
      "ios_version": "17.5",
      "healthkit_version": "17.0"
    },
    "preprocessing": {
      "normalization_method": "z_score",
      "outlier_handling": "cap",
      "missing_data_strategy": "interpolation"
    }
  }
}
```

---

## HIPAA Compliance

### Data De-identification Checklist

✅ **User ID**: Hashed, not real ID
✅ **Age**: Range (30-40), not exact
✅ **Location**: Not included
✅ **Dates**: Relative, not absolute when possible
✅ **Device IDs**: Generic model names only

### Encryption Requirements

All payloads must be encrypted before transmission:

```swift
// Encrypt payload before sending
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
let jsonData = try encoder.encode(aiPayload)

let encryptedData = try encryptPayload(jsonData)

// Send encrypted data
let response = try await apiClient.post(
    endpoint: "/api/v1/ai/analyze",
    body: encryptedData
)
```

---

## Best Practices

### 1. Data Quality

- ✅ Ensure >90% completeness
- ✅ Remove obvious outliers
- ✅ Fill missing data appropriately
- ✅ Validate ranges

### 2. Privacy

- ✅ Always hash user IDs
- ✅ Use age ranges, not exact ages
- ✅ Minimize PII in payloads
- ✅ Encrypt all transmissions

### 3. Performance

- ✅ Batch requests when possible
- ✅ Cache AI responses
- ✅ Use async/await for concurrent operations
- ✅ Compress large payloads

### 4. Error Handling

```swift
do {
    let insights = try await getAIInsights()
    // Process insights
} catch AIError.insufficientData {
    // Not enough data for analysis
} catch AIError.modelUnavailable {
    // AI service down, use fallback
} catch {
    // Generic error
}
```

### 5. Monitoring

- Log all AI requests
- Track response times
- Monitor prediction accuracy
- Alert on anomalies

---

## Next Steps

1. ✅ Review AI_DATA_SCHEMA.md for complete schema
2. ✅ Implement HealthDataPreprocessor for normalization
3. ✅ Test with sample data
4. ✅ Set up Azure OpenAI or Vertex AI endpoints
5. ✅ Validate HIPAA compliance
6. ✅ Deploy to production

For detailed schema documentation, see [AI_DATA_SCHEMA.md](AI_DATA_SCHEMA.md).
