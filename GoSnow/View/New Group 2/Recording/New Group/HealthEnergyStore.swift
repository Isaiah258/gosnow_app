//
//  HealthEnergyStore.swift
//  雪兔滑行
// nbvcx
//  Created by federico Liu on 2025/12/20.
//

import Foundation
import HealthKit

/// 只读：按时间段读取「活动能量(kcal)」
/// - 不会主动弹授权（你说要在设置页处理）
/// - StatsView / Summary 都可复用
@MainActor
final class HealthEnergyStore: ObservableObject {

    static let shared = HealthEnergyStore()

    private let healthStore = HKHealthStore()
    private var inFlight: Set<String> = []

    /// cacheKey -> kcal（nil 表示「已查询但无数据/失败」）
    @Published private(set) var cache: [String: Double?] = [:]

    private init() {}

    // MARK: - Authorization (read-only)

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var isEnergyAuthorized: Bool {
        guard isHealthDataAvailable,
              let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        else { return false }

        return healthStore.authorizationStatus(for: energyType) == .sharingAuthorized
    }

    // MARK: - Public

    /// 用于历史卡片：按 sessionId + 时间段缓存
    func prefetchEnergyIfPossible(sessionId: String, start: Date, end: Date) async {
        guard isEnergyAuthorized else { return }
        guard cache.keys.contains(sessionId) == false else { return }
        guard inFlight.contains(sessionId) == false else { return }

        inFlight.insert(sessionId)
        defer { inFlight.remove(sessionId) }

        do {
            let kcal = try await fetchActiveEnergyKcal(start: start, end: end)
            cache[sessionId] = kcal
        } catch {
            // 安静失败：不打扰用户
            cache[sessionId] = nil
        }
    }

    /// 直接查一次（不缓存也可用）
    func fetchActiveEnergyKcalIfAuthorized(start: Date, end: Date) async -> Double? {
        guard isEnergyAuthorized else { return nil }
        return try? await fetchActiveEnergyKcal(start: start, end: end)
    }

    // MARK: - Private

    private func fetchActiveEnergyKcal(start: Date, end: Date) async throws -> Double? {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let kcal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie())
                continuation.resume(returning: kcal)
            }

            self.healthStore.execute(query)
        }
    }
}
