//
//  HealthKitManager.swift
//  雪兔滑行
//
//  Created by ChatGPT on 2025/8/10.
//

import Foundation
import HealthKit

struct HealthMetrics {
    let avgHeartRateBpm: Double?
    let activeEnergyKcal: Double?
}

/// Read-only HealthKit wrapper dedicated to session summaries.
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private var authorizationCached: Bool?

    private init() {}

    func requestAuthorizationIfNeeded() async -> Bool {
        if let authorizationCached { return authorizationCached }
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationCached = false
            return false
        }

        guard
            let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
            let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            authorizationCached = false
            return false
        }

        let readTypes: Set<HKObjectType> = [heartRateType, activeEnergyType]

        do {
            let success = try await requestAuthorization(readTypes: readTypes)
            authorizationCached = success
            return success
        } catch {
            authorizationCached = false
            return false
        }
    }

    func fetchMetrics(start: Date, end: Date) async -> HealthMetrics {
        guard HKHealthStore.isHealthDataAvailable() else {
            return HealthMetrics(avgHeartRateBpm: nil, activeEnergyKcal: nil)
        }

        guard
            let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
            let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            return HealthMetrics(avgHeartRateBpm: nil, activeEnergyKcal: nil)
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        async let heartRate = statisticsAverage(for: heartRateType, unit: HKUnit.count().unitDivided(by: HKUnit.minute()), predicate: predicate)
        async let activeEnergy = statisticsSum(for: activeEnergyType, unit: .kilocalorie(), predicate: predicate)

        let heartRateValue = await heartRate
        let energyValue = await activeEnergy

        return HealthMetrics(avgHeartRateBpm: heartRateValue, activeEnergyKcal: energyValue)
    }

    // MARK: - Private helpers

    private func requestAuthorization(readTypes: Set<HKObjectType>) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    private func statisticsAverage(for type: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
                let value = stats?.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func statisticsSum(for type: HKQuantityType, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let value = stats?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
}

