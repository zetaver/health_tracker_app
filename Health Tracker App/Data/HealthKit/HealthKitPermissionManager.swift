//
//  HealthKitPermissionManager.swift
//  Health Tracker App
//
//  Handles HealthKit authorization and permission management
//

import Foundation
import HealthKit

/// Manages HealthKit permissions and authorization status
@MainActor
class HealthKitPermissionManager {

    // MARK: - Properties

    private let healthStore: HKHealthStore

    /// Indicates if HealthKit is available on this device
    static var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Initialization

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    // MARK: - Permission Configuration

    /// Defines all health data types we want to read
    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()

        // Quantity types
        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .stepCount,
            .activeEnergyBurned,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .oxygenSaturation,
            .bodyTemperature,
            .respiratoryRate,
            .bloodPressureSystolic,
            .bloodPressureDiastolic
        ]

        for identifier in quantityTypes {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        // Category types
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        // Correlation types
        if let bloodPressureType = HKCorrelationType.correlationType(forIdentifier: .bloodPressure) {
            types.insert(bloodPressureType)
        }

        return types
    }

    /// Defines all health data types we want to write (optional)
    private var writeTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()

        // Add write permissions if needed (e.g., for manual data entry)
        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .bloodPressureSystolic,
            .bloodPressureDiastolic
        ]

        for identifier in quantityTypes {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        return types
    }

    // MARK: - Authorization

    /// Requests authorization for all required health data types
    /// - Returns: Boolean indicating if authorization was successful
    func requestAuthorization() async throws -> Bool {
        guard Self.isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            return true
        } catch {
            throw HealthKitError.authorizationFailed(underlying: error)
        }
    }

    /// Requests authorization for specific metric types
    /// - Parameter metricTypes: Array of metric types to request authorization for
    /// - Returns: Boolean indicating if authorization was successful
    func requestAuthorization(for metricTypes: [HealthMetricType]) async throws -> Bool {
        guard Self.isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        var readTypesToRequest = Set<HKObjectType>()
        var writeTypesToRequest = Set<HKSampleType>()

        for metricType in metricTypes {
            if metricType == .bloodPressure {
                // Blood pressure requires correlation type
                if let type = HKCorrelationType.correlationType(forIdentifier: .bloodPressure) {
                    readTypesToRequest.insert(type)
                }
                if let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic) {
                    readTypesToRequest.insert(systolicType)
                }
                if let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) {
                    readTypesToRequest.insert(diastolicType)
                }
            } else if let type = metricType.healthKitIdentifier {
                readTypesToRequest.insert(type)
            }
        }

        do {
            try await healthStore.requestAuthorization(toShare: writeTypesToRequest, read: readTypesToRequest)
            return true
        } catch {
            throw HealthKitError.authorizationFailed(underlying: error)
        }
    }

    // MARK: - Authorization Status

    /// Checks authorization status for a specific metric type
    /// - Parameter metricType: The metric type to check
    /// - Returns: Authorization status
    func authorizationStatus(for metricType: HealthMetricType) -> HKAuthorizationStatus {
        guard let objectType = metricType.healthKitIdentifier else {
            return .notDetermined
        }

        return healthStore.authorizationStatus(for: objectType)
    }

    /// Checks if authorization has been granted for all required types
    /// - Returns: Boolean indicating if all permissions are granted
    func hasAllPermissions() -> Bool {
        for type in readTypes {
            let status = healthStore.authorizationStatus(for: type)
            if status != .sharingAuthorized {
                return false
            }
        }
        return true
    }

    /// Returns a list of metric types that need authorization
    /// - Returns: Array of metric types requiring authorization
    func unauthorizedMetricTypes() -> [HealthMetricType] {
        var unauthorized: [HealthMetricType] = []

        for metricType in HealthMetricType.allCases {
            let status = authorizationStatus(for: metricType)
            if status != .sharingAuthorized {
                unauthorized.append(metricType)
            }
        }

        return unauthorized
    }

    // MARK: - Permission Helpers

    /// Determines if we can read a specific metric type
    /// - Parameter metricType: The metric type to check
    /// - Returns: Boolean indicating if reading is allowed
    func canRead(_ metricType: HealthMetricType) -> Bool {
        let status = authorizationStatus(for: metricType)
        return status == .sharingAuthorized
    }

    /// Gets a user-friendly description of the authorization status
    /// - Parameter metricType: The metric type to describe
    /// - Returns: Human-readable status description
    func statusDescription(for metricType: HealthMetricType) -> String {
        let status = authorizationStatus(for: metricType)
        switch status {
        case .notDetermined:
            return "Permission not requested"
        case .sharingDenied:
            return "Permission denied"
        case .sharingAuthorized:
            return "Permission granted"
        @unknown default:
            return "Unknown status"
        }
    }
}

// MARK: - Permission Models

/// Represents the overall permission state
struct HealthKitPermissionState {
    let isAvailable: Bool
    let hasAllPermissions: Bool
    let unauthorizedTypes: [HealthMetricType]
    let lastChecked: Date

    var needsAuthorization: Bool {
        isAvailable && !hasAllPermissions
    }

    init(isAvailable: Bool,
         hasAllPermissions: Bool,
         unauthorizedTypes: [HealthMetricType],
         lastChecked: Date = Date()) {
        self.isAvailable = isAvailable
        self.hasAllPermissions = hasAllPermissions
        self.unauthorizedTypes = unauthorizedTypes
        self.lastChecked = lastChecked
    }
}

// MARK: - Error Handling

enum HealthKitError: LocalizedError {
    case notAvailable
    case authorizationFailed(underlying: Error)
    case queryFailed(underlying: Error)
    case invalidData
    case noData
    case permissionDenied(metricType: HealthMetricType)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .authorizationFailed(let error):
            return "Failed to authorize HealthKit access: \(error.localizedDescription)"
        case .queryFailed(let error):
            return "Failed to query HealthKit data: \(error.localizedDescription)"
        case .invalidData:
            return "Received invalid data from HealthKit"
        case .noData:
            return "No data available for the requested period"
        case .permissionDenied(let metricType):
            return "Permission denied for \(metricType.displayName)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is only available on iPhone and Apple Watch"
        case .authorizationFailed:
            return "Please grant permission in Settings > Privacy > Health"
        case .queryFailed:
            return "Please try again later"
        case .invalidData:
            return "The health data format is not supported"
        case .noData:
            return "Try selecting a different date range"
        case .permissionDenied:
            return "Please grant permission in Settings > Privacy > Health"
        }
    }
}
