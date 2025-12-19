//
//  RecordingViewModel.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/8/10.
//

import Foundation
import UIKit
import CoreLocation

@MainActor
final class RecordingViewModel: ObservableObject {

    @Published var speedKmh: Double = 0
    @Published var distanceKm: Double = 0
    @Published var durationSec: Int = 0
    @Published var state: RecordingState = .idle

    /// 提供给地图跟随
    @Published var currentCoordinate: CLLocationCoordinate2D?

    private let recorder: SessionRecorder
    private let store: LocalStore

    /// UI 轮询任务（定时从 recorder 拉最新数据）
    private var pollingTask: Task<Void, Never>?

    init(recorder: SessionRecorder, store: LocalStore) {
        self.recorder = recorder
        self.store = store

        // UI 轮询
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.syncFromRecorder()
                // 录制/暂停更快，idle 更慢
                let ms: UInt64 = (self.state == .recording || self.state == .paused) ? 500 : 2000
                try? await Task.sleep(nanoseconds: ms * 1_000_000)
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.syncFromRecorder() }
        }
    }

    deinit {
        pollingTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 控制

    func start(resortId: Int?) async {
        await recorder.start(resortId: resortId)
        await syncFromRecorder()
    }

    func pause() {
        recorder.pause()
        Task { await syncFromRecorder() }
    }

    func resume() {
        recorder.resume()
        Task { await syncFromRecorder() }
    }

    @MainActor
    func stopSaveAndSummarize() async -> (SessionSummary, SkiSession)? {
        let session = await recorder.stop()
        await syncFromRecorder()

        let summary = SessionSummary(
            id: session.id,
            startAt: session.startAt,
            endAt: session.endAt,
            distanceKm: session.distanceKm,
            avgSpeedKmh: session.avgSpeedKmh,
            topSpeedKmh: session.topSpeedKmh,
            elevationDropM: nil,
            durationSec: session.durationSec
        )

        let storeCopy = self.store
        Task.detached(priority: .utility) {
            do {
                if let json = storeCopy as? JSONLocalStore {
                    try await json.saveSessionAsync(session)
                    await json.pruneToLimitAsync(MAX_SESSIONS)
                } else {
                    try storeCopy.saveSession(session)
                }
            } catch {
                print("❌ async save session failed:", error)
            }
        }

        return (summary, session)
    }

    // MARK: - 从 recorder 同步 UI（关键逻辑）

    private func syncFromRecorder() async {
        let recState = recorder.state
        state = recState

        // ✅ 只要处于 idle，就强制把 UI 清零，不管底层有什么噪音
        guard recState == .recording || recState == .paused else {
            speedKmh = 0
            distanceKm = 0
            durationSec = 0
            currentCoordinate = nil
            return
        }

        // 只有在录制 / 暂停中才把真实数据灌给 UI
        speedKmh    = recorder.currentSpeedKmh
        distanceKm  = recorder.distanceKm
        durationSec = recorder.durationSec
        currentCoordinate = recorder.lastCoordinate

        if let r = recorder as? SessionRecorderCoordinates {
            self.currentCoordinate = r.lastCoordinate
        }
    }
}







