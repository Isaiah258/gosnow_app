import Foundation
import CoreLocation
import MapboxMaps
import MapboxCommon
import Turf

@MainActor
final class LiveTrackController: ObservableObject {

    private weak var mapView: MapView?

    // ✅ 两个 source：green / orange
    private let greenSourceId  = "live-track-green-source"
    private let orangeSourceId = "live-track-orange-source"

    // ✅ 两套 layer：各自 casing + main
    private let greenCasingLayerId  = "live-track-green-casing"
    private let greenLineLayerId    = "live-track-green-line"
    private let orangeCasingLayerId = "live-track-orange-casing"
    private let orangeLineLayerId   = "live-track-orange-line"

    private var didInstall = false

    private struct Segment {
        var coords: [CLLocationCoordinate2D]
        var bucket: Int   // 0=green, 1=orange
    }
    private var segments: [Segment] = []

    private var lastAcceptedLoc: CLLocation?
    private var lastAcceptedCoord: CLLocationCoordinate2D?

    private let minDistanceM: CLLocationDistance = 3

    // ✅ 你的需求：快段阈值
    private let orangeOnThresholdKmh: Double = 50
    private let orangeOffThresholdKmh: Double = 48

    private let enterOrangeDwellSec: TimeInterval = 2.0
    private let exitOrangeDwellSec: TimeInterval  = 1.0

    // ✅ 状态机
    private var currentBucket: Int = 0
    private var pendingOrangeSince: Date?
    private var pendingGreenSince: Date?

    private var renderTask: Task<Void, Never>?
    private var styleLoadedCancellable: Cancelable?

    var isEnabled: Bool = true {
        didSet { scheduleRender() }
    }

    func attach(to mapView: MapView) {
        self.mapView = mapView
        installWhenStyleReady()
    }

    func reset() {
        segments.removeAll()
        lastAcceptedLoc = nil
        lastAcceptedCoord = nil

        currentBucket = 0
        pendingOrangeSince = nil
        pendingGreenSince = nil

        scheduleRender()
    }

    func append(_ coord: CLLocationCoordinate2D, speedKmh: Double) {
        guard isEnabled else { return }

        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

        if let last = lastAcceptedLoc, loc.distance(from: last) < minDistanceM {
            return
        }

        let now = Date()
        updateBucket(now: now, speedKmh: speedKmh)
        let bucket = currentBucket

        // 首点只缓存
        guard let prev = lastAcceptedCoord else {
            lastAcceptedLoc = loc
            lastAcceptedCoord = coord
            return
        }

        lastAcceptedLoc = loc
        lastAcceptedCoord = coord

        // 同色段合并
        if var lastSeg = segments.last, lastSeg.bucket == bucket {
            lastSeg.coords.append(coord)
            segments[segments.count - 1] = lastSeg
        } else {
            segments.append(Segment(coords: [prev, coord], bucket: bucket))
        }

        scheduleRender()
    }

    private func updateBucket(now: Date, speedKmh: Double) {
        if currentBucket == 0 {
            if speedKmh >= orangeOnThresholdKmh {
                if pendingOrangeSince == nil { pendingOrangeSince = now }
                if let t0 = pendingOrangeSince, now.timeIntervalSince(t0) >= enterOrangeDwellSec {
                    currentBucket = 1
                    pendingOrangeSince = nil
                    pendingGreenSince = nil
                }
            } else {
                pendingOrangeSince = nil
            }
        } else {
            if speedKmh <= orangeOffThresholdKmh {
                if pendingGreenSince == nil { pendingGreenSince = now }
                if let t0 = pendingGreenSince, now.timeIntervalSince(t0) >= exitOrangeDwellSec {
                    currentBucket = 0
                    pendingGreenSince = nil
                    pendingOrangeSince = nil
                }
            } else {
                pendingGreenSince = nil
            }
        }
    }

    // MARK: - Install

    private func installWhenStyleReady() {
        guard let mapView else { return }

        if mapView.mapboxMap.isStyleLoaded {
            install()
        } else {
            styleLoadedCancellable?.cancel()
            styleLoadedCancellable = mapView.mapboxMap.onStyleLoaded.observeNext { [weak self] _ in
                Task { @MainActor in self?.install() }
            }
        }
    }

    private func install() {
        guard let mapView else { return }
        guard mapView.mapboxMap.isStyleLoaded else { return }
        guard !didInstall else { return }

        didInstall = true

        // 清理旧的（防止重复叠加）
        try? mapView.mapboxMap.removeLayer(withId: greenLineLayerId)
        try? mapView.mapboxMap.removeLayer(withId: greenCasingLayerId)
        try? mapView.mapboxMap.removeLayer(withId: orangeLineLayerId)
        try? mapView.mapboxMap.removeLayer(withId: orangeCasingLayerId)

        try? mapView.mapboxMap.removeSource(withId: greenSourceId)
        try? mapView.mapboxMap.removeSource(withId: orangeSourceId)

        // ✅ 两个 source
        var greenSource = GeoJSONSource(id: greenSourceId)
        greenSource.data = .featureCollection(Turf.FeatureCollection(features: []))
        try? mapView.mapboxMap.addSource(greenSource)

        var orangeSource = GeoJSONSource(id: orangeSourceId)
        orangeSource.data = .featureCollection(Turf.FeatureCollection(features: []))
        try? mapView.mapboxMap.addSource(orangeSource)

        // ✅ green casing
        var gCasing = LineLayer(id: greenCasingLayerId, source: greenSourceId)
        gCasing.lineColor = .constant(StyleColor(.black))
        gCasing.lineOpacity = .constant(0.55)
        gCasing.lineWidth = .constant(6.0)
        gCasing.lineJoin = .constant(.round)
        gCasing.lineCap = .constant(.round)
        try? mapView.mapboxMap.addLayer(gCasing)

        // ✅ green main
        var gLine = LineLayer(id: greenLineLayerId, source: greenSourceId)
        gLine.lineColor = .constant(StyleColor(.systemGreen))
        gLine.lineOpacity = .constant(0.95)
        gLine.lineWidth = .constant(3.5)
        gLine.lineJoin = .constant(.round)
        gLine.lineCap = .constant(.round)
        try? mapView.mapboxMap.addLayer(gLine)

        // ✅ orange casing
        var oCasing = LineLayer(id: orangeCasingLayerId, source: orangeSourceId)
        oCasing.lineColor = .constant(StyleColor(.black))
        oCasing.lineOpacity = .constant(0.55)
        oCasing.lineWidth = .constant(6.0)
        oCasing.lineJoin = .constant(.round)
        oCasing.lineCap = .constant(.round)
        try? mapView.mapboxMap.addLayer(oCasing)

        // ✅ orange main
        var oLine = LineLayer(id: orangeLineLayerId, source: orangeSourceId)
        oLine.lineColor = .constant(StyleColor(.systemOrange))
        oLine.lineOpacity = .constant(0.95)
        oLine.lineWidth = .constant(3.5)
        oLine.lineJoin = .constant(.round)
        oLine.lineCap = .constant(.round)
        try? mapView.mapboxMap.addLayer(oLine)

        scheduleRender()
    }

    // MARK: - Render

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.renderNow()
        }
    }

    private func renderNow() async {
        guard let mapView else { return }
        guard mapView.mapboxMap.isStyleLoaded else { return }
        if !didInstall { install(); return }

        // 关闭或没有数据 → 清空两条 source
        guard isEnabled, !segments.isEmpty else {
            let empty = Turf.FeatureCollection(features: [])
            mapView.mapboxMap.updateGeoJSONSource(withId: greenSourceId,  geoJSON: .featureCollection(empty))
            mapView.mapboxMap.updateGeoJSONSource(withId: orangeSourceId, geoJSON: .featureCollection(empty))
            return
        }

        var greenFeatures: [Turf.Feature] = []
        var orangeFeatures: [Turf.Feature] = []

        for seg in segments {
            guard seg.coords.count >= 2 else { continue }
            let ls = Turf.LineString(seg.coords)
            let f = Turf.Feature(geometry: .lineString(ls))
            if seg.bucket == 1 {
                orangeFeatures.append(f)
            } else {
                greenFeatures.append(f)
            }
        }

        let greenFC  = Turf.FeatureCollection(features: greenFeatures)
        let orangeFC = Turf.FeatureCollection(features: orangeFeatures)

        mapView.mapboxMap.updateGeoJSONSource(withId: greenSourceId,  geoJSON: .featureCollection(greenFC))
        mapView.mapboxMap.updateGeoJSONSource(withId: orangeSourceId, geoJSON: .featureCollection(orangeFC))
    }
}


extension LiveTrackController {

    struct SnapshotSegment {
        let coords: [CLLocationCoordinate2D]
        let bucket: Int // 0=green, 1=orange
    }

    func snapshotSegments() -> [SnapshotSegment] {
        segments.map { SnapshotSegment(coords: $0.coords, bucket: $0.bucket) }
    }

    func snapshotAllCoords() -> [CLLocationCoordinate2D] {
        segments.flatMap(\.coords)
    }
}

