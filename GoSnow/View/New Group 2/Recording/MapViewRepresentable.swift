//
//  MapViewRepresentable.swift
//  GoSnow
//
//  Created by federico Liu on 2024/8/21.
//
import SwiftUI
import MapboxMaps

enum RecordingMapStyle: CaseIterable, Identifiable {
    case contour

    var id: Self { self }
    var title: String { "地形图" }

    var styleURI: StyleURI {
        StyleURI(rawValue: "mapbox://styles/gosnow/cmikjh06p00ys01s68fmy9nor") ?? .outdoors
    }
}

struct MapViewRepresentable: UIViewRepresentable {
    let style: RecordingMapStyle
    let onMapViewCreated: (MapView) -> Void

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero, mapInitOptions: MapInitOptions())

        // ✅ 允许用户 3D 倾斜 / 旋转（默认一般是开，但你显式开更稳）
        mapView.gestures.options.pitchEnabled = true
        mapView.gestures.options.rotateEnabled = true

        var locationOptions = LocationOptions()
        locationOptions.puckType = .puck2D()
        locationOptions.puckBearingEnabled = true
        mapView.location.options = locationOptions

        mapView.ornaments.options.scaleBar.visibility = .visible
        mapView.ornaments.options.compass.visibility = .adaptive

        mapView.mapboxMap.loadStyle(style.styleURI)

        onMapViewCreated(mapView)
        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        // ✅ 不要在这里反复 loadStyle
    }
}












/*
 import SwiftUI
 import MapKit
 import CoreLocation

 struct MapViewRepresentable: UIViewRepresentable {
     @Binding var userLocation: CLLocationCoordinate2D?
     let onMapViewCreated: (MKMapView) -> Void

     func makeUIView(context: Context) -> MKMapView {
         let mapView = MKMapView()
         mapView.delegate = context.coordinator

         // 交互&显示选项
         mapView.isRotateEnabled = true
         mapView.isPitchEnabled = true
         mapView.isZoomEnabled = true
         mapView.isScrollEnabled = true

         mapView.showsUserLocation = true
         mapView.userTrackingMode = .follow
         mapView.mapType = .standard

         // 初始相机范围
         mapView.setCameraZoomRange(
             MKMapView.CameraZoomRange(minCenterCoordinateDistance: 150,
                                       maxCenterCoordinateDistance: 50_000),
             animated: false
         )

         onMapViewCreated(mapView)
         return mapView
     }

     func updateUIView(_ uiView: MKMapView, context: Context) {
         // 刻意留空：避免与外层抢相机控制
     }

     func makeCoordinator() -> MapCoordinator {
         MapCoordinator(self)
     }

     final class MapCoordinator: NSObject, MKMapViewDelegate {
         let parent: MapViewRepresentable
         init(_ parent: MapViewRepresentable) { self.parent = parent }

         // ✅ 把蓝点的坐标回传给上层（这是你现在缺的环节）
         func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
             if let coord = userLocation.location?.coordinate {
                 parent.userLocation = coord
             }
         }
     }
 }


*/
