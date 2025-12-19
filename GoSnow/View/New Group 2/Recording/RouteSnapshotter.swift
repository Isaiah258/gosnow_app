//
//  RouteSnapshotter.swift
//  雪兔滑行
//
//  Created by federico Liu on 2026/1/2.
//

import UIKit
import CoreLocation
import MapboxMaps

enum RouteSnapshotter {

    struct Segment {
        let coords: [CLLocationCoordinate2D]
        let bucket: Int // 0=green, 1=orange
    }

    static func makeSnapshot(
        styleURI: StyleURI,
        size: CGSize,
        segments: [Segment],
        padding: CGFloat = 70
    ) async throws -> UIImage {

        let allCoords = segments.flatMap { $0.coords }
        let camera = cameraOptionsToFit(coords: allCoords, size: size, padding: padding)

        // ✅ Swift 6：UIScreen 只能在 MainActor 读取
        let pixelRatio = await MainActor.run { UIScreen.main.scale }

        // ✅ 你当前版本：options 只有 size/pixelRatio
        let options = MapSnapshotOptions(size: size, pixelRatio: pixelRatio)

        // ✅ 你当前版本：Snapshotter 只有这个 init
        let snapshotter = Snapshotter(options: options)

        // ✅ 你当前版本：用属性 + 方法配置 style / camera
        snapshotter.styleURI = styleURI
        snapshotter.setCamera(to: camera)

        return try await withCheckedThrowingContinuation { cont in
            snapshotter.start(
                overlayHandler: { overlay in
                    drawRoute(on: overlay, segments: segments)
                },
                completion: { result in
                    switch result {
                    case .success(let image):
                        cont.resume(returning: image)
                    case .failure(let error):
                        cont.resume(throwing: error)
                    }
                }
            )
        }
    }

    // MARK: - Draw

    private static func drawRoute(on overlay: SnapshotOverlay, segments: [Segment]) {
        guard !segments.isEmpty else { return }

        let ctx = overlay.context
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)

        // 描边（黑色粗线）
        for seg in segments {
            stroke(ctx: ctx, overlay: overlay, coords: seg.coords,
                   color: UIColor.black.withAlphaComponent(0.55), width: 6.0)
        }

        // 主线（绿/橙）
        for seg in segments {
            let color: UIColor = (seg.bucket == 1) ? .systemOrange : .systemGreen
            stroke(ctx: ctx, overlay: overlay, coords: seg.coords,
                   color: color.withAlphaComponent(0.95), width: 3.5)
        }
    }

    private static func stroke(
        ctx: CGContext,
        overlay: SnapshotOverlay,
        coords: [CLLocationCoordinate2D],
        color: UIColor,
        width: CGFloat
    ) {
        guard coords.count >= 2 else { return }

        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)

        var didMove = false
        for c in coords {
            let p = overlay.pointForCoordinate(c)
            if !didMove {
                ctx.beginPath()
                ctx.move(to: p)
                didMove = true
            } else {
                ctx.addLine(to: p)
            }
        }
        ctx.strokePath()
    }

    // MARK: - Camera fit (WebMercator)

    private static func cameraOptionsToFit(
        coords: [CLLocationCoordinate2D],
        size: CGSize,
        padding: CGFloat
    ) -> CameraOptions {

        guard coords.count >= 2 else {
            return CameraOptions(center: coords.first, zoom: 15, bearing: 0, pitch: 0)
        }

        var minLat =  90.0, maxLat = -90.0
        var minLon =  180.0, maxLon = -180.0

        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )

        func xNorm(_ lon: Double) -> Double { (lon + 180.0) / 360.0 }
        func yNorm(_ lat: Double) -> Double {
            let rad = lat * .pi / 180.0
            let sinv = sin(rad)
            let y = 0.5 - log((1 + sinv) / (1 - sinv)) / (4 * .pi)
            return min(max(y, 0), 1)
        }

        let x1 = xNorm(minLon), x2 = xNorm(maxLon)
        let y1 = yNorm(minLat), y2 = yNorm(maxLat)

        let dx = abs(x2 - x1)
        let dy = abs(y2 - y1)

        let usableW = max(1, Double(size.width - padding * 2))
        let usableH = max(1, Double(size.height - padding * 2))

        let tileSize = 512.0

        let zoom: Double = {
            if dx < 1e-9 && dy < 1e-9 { return 16.0 }
            let scaleX = usableW / max(dx, 1e-9)
            let scaleY = usableH / max(dy, 1e-9)
            let scale = min(scaleX, scaleY)
            let z = log2(scale / tileSize)
            return min(max(z, 0), 22)
        }()

        return CameraOptions(center: center, zoom: zoom, bearing: 0, pitch: 0)
    }
}

