//
//  MapViewRepresentable.swift
//  GoSnow
//
//  Created by federico Liu on 2024/8/21.
//
import SwiftUI
import MapboxMaps
import CoreLocation





import MapboxMaps

enum RecordingMapStyle: CaseIterable, Identifiable {
    case contour   // 你的自定义滑雪/等高线样式

    var id: Self { self }

    var title: String { "地形图" }

    var styleURI: StyleURI {
        StyleURI(rawValue: "mapbox://styles/gosnow/cmikjh06p00ys01s68fmy9nor")
        ?? .outdoors
    }
}







struct MapViewRepresentable: UIViewRepresentable {
    let style: RecordingMapStyle
    let onMapViewCreated: (MapView) -> Void

    func makeUIView(context: Context) -> MapView {
        // 用默认的 MapInitOptions 即可
        let initOptions = MapInitOptions()
        let mapView = MapView(frame: .zero, mapInitOptions: initOptions)

        // ✅ 开启用户位置蓝点（puck）
        var locationOptions = LocationOptions()
        locationOptions.puckType = .puck2D()          // 2D 蓝点样式
        locationOptions.puckBearingEnabled = true     // 允许根据方向旋转
        mapView.location.options = locationOptions

        // 一些简单的 UI 配置
        mapView.ornaments.options.scaleBar.visibility = .visible
        mapView.ornaments.options.compass.visibility = .adaptive
        // mapView.ornaments.options.attributionButton.visibility = .visible  // 这个之前会报 @_spi，先别用

        // ✅ 初次加载样式
        mapView.mapboxMap.loadStyle(style.styleURI) { _ in
            // 这里暂时不做别的，纯粹换 style
        }

        onMapViewCreated(mapView)
        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        // ✅ 每次 style 变化都重新 load 一次
        uiView.mapboxMap.loadStyle(style.styleURI) { _ in
            // 如果后面要加中文本地化 / 自定义图层，可以写在这里
        }
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
