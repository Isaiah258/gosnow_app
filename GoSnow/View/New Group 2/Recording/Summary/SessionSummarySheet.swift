//
//  SessionSummarySheet.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/8/10.
//

// Recording/UI/SessionSummarySheet.swift
import SwiftUI
import UIKit

struct SessionSummarySheet: View {
    let summary: SessionSummary
    @State private var healthMetrics: HealthMetrics? = nil
    @State private var isLoadingHealth = false
    @State private var isHealthAuthorized = false
    @State private var hasCheckedAuthorization = false

    var body: some View {
        VStack(spacing: 24) {
            Text("本次滑行总结").font(.title3).bold()

            HStack(spacing: 28) {
                metricBlock(title: "距离 (km)", value: String(format: "%.1f", summary.distanceKm))
                metricBlock(title: "平均速度 (km/h)", value: String(format: "%.1f", summary.avgSpeedKmh))
            }
            HStack(spacing: 28) {
                metricBlock(title: "最高速度 (km/h)", value: String(format: "%.1f", summary.topSpeedKmh))
                metricBlock(title: "用时", value: summary.durationText)
            }
            if let drop = summary.elevationDropM {
                metricBlock(title: "落差 (m)", value: "\(drop)")
                    .frame(maxWidth: .infinity)
            }

            healthSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .presentationDetents([.fraction(0.42), .medium])
        .presentationDragIndicator(.visible)
        .modifier(PresentationCornerRadiusIfAvailable(24))
        .presentationBackground(.regularMaterial)
        .task { await loadHealthData() }
    }

    private func metricBlock(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 42, weight: .semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("健康数据")
                    .font(.headline)
                if isLoadingHealth {
                    Spacer()
                    ProgressView()
                }
            }

            Group {
                if isLoadingHealth {
                    Text("正在从 Apple 健康加载...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if hasCheckedAuthorization && !isHealthAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("未授权读取健康数据")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("连接 Apple 健康") {
                            Task { await loadHealthData() }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if let metrics = healthMetrics, (metrics.avgHeartRateBpm != nil || metrics.activeEnergyKcal != nil) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let hr = metrics.avgHeartRateBpm {
                            healthMetricRow(title: "平均心率", value: String(format: "%.0f bpm", hr))
                        }
                        if let energy = metrics.activeEnergyKcal {
                            healthMetricRow(title: "活跃能量", value: String(format: "%.0f kcal", energy))
                        }
                    }
                } else {
                    Text("暂无可用的健康数据")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func healthMetricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private func loadHealthData() async {
        await MainActor.run {
            isLoadingHealth = true
        }

        let authorized = await HealthKitManager.shared.requestAuthorizationIfNeeded()
        await MainActor.run {
            self.isHealthAuthorized = authorized
            self.hasCheckedAuthorization = true
        }

        guard authorized else {
            await MainActor.run {
                self.healthMetrics = nil
                self.isLoadingHealth = false
            }
            return
        }

        let metrics = await HealthKitManager.shared.fetchMetrics(start: summary.startAt, end: summary.endAt)
        await MainActor.run {
            self.healthMetrics = metrics
            self.isLoadingHealth = false
        }
    }
}

private struct PresentationCornerRadiusIfAvailable: ViewModifier {
    let radius: CGFloat
    init(_ radius: CGFloat) { self.radius = radius }
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.presentationCornerRadius(radius)
        } else { content }
    }
}

/*

 import SwiftUI
 import UIKit



 // MARK: - 供分享的“图片卡片”视图（只用于渲染，不直接展示）
 struct SummaryShareCard: View {
     let summary: SessionSummary
     let date: Date

     var body: some View {
         VStack(spacing: 20) {
             // 头部
             HStack {
                 VStack(alignment: .leading, spacing: 6) {
                     Text("Snowbunny 滑行总结")
                         .font(.system(size: 32, weight: .semibold))
                     Text(dateFormatted(date))
                         .font(.subheadline)
                         .foregroundStyle(.secondary)
                 }
                 Spacer()
                 // 右侧角标（可换成你的 App 图标）
                 Image(systemName: "snowflake")
                     .font(.system(size: 28, weight: .bold))
             }

             // 指标网格
             Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                 GridRow {
                     metricTile(title: "距离 (km)", value: String(format: "%.1f", summary.distanceKm))
                     metricTile(title: "平均速度 (km/h)", value: String(format: "%.1f", summary.avgSpeedKmh))
                 }
                 GridRow {
                     metricTile(title: "最高速度 (km/h)", value: String(format: "%.1f", summary.topSpeedKmh))
                     metricTile(title: "用时", value: summary.durationText)
                 }
                 if let drop = summary.elevationDropM {
                     GridRow {
                         metricTile(title: "落差 (m)", value: "\(drop)")
                         Color.clear.frame(height: 0) // 占位补齐
                     }
                 }
             }

             Divider().padding(.top, 4)

             // 结尾品牌条
             HStack {
                 Text("来自 Snowbunny")
                     .font(.footnote)
                     .foregroundStyle(.secondary)
                 Spacer()
                 Text("#Snowbunny")
                     .font(.footnote)
                     .foregroundStyle(.secondary)
             }
         }
         .padding(28)
         .background(.white)          // 纯白底，便于社媒展示
         .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
         .shadow(radius: 8, y: 4)
     }

     private func metricTile(title: String, value: String) -> some View {
         VStack(alignment: .leading, spacing: 6) {
             Text(value)
                 .font(.system(size: 44, weight: .semibold))
                 .minimumScaleFactor(0.7)
                 .lineLimit(1)
             Text(title)
                 .font(.subheadline)
                 .foregroundStyle(.secondary)
         }
         .frame(maxWidth: .infinity, alignment: .leading)
         .padding(16)
         .background(Color(.systemGray6))
         .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
     }

     private func dateFormatted(_ date: Date) -> String {
         let f = DateFormatter()
         f.dateFormat = "yyyy-MM-dd HH:mm"
         return f.string(from: date)
     }
 }

 // MARK: - 主体：总结 Sheet
 import SwiftUI

 struct SessionSummarySheet: View {
     let summary: SessionSummary

     var body: some View {
         VStack(spacing: 24) {
             Text("本次滑行总结")
                 .font(.title3).bold()

             HStack(spacing: 28) {
                 metricBlock(title: "距离 (km)",
                             value: String(format: "%.1f", summary.distanceKm))
                 metricBlock(title: "平均速度 (km/h)",
                             value: String(format: "%.1f", summary.avgSpeedKmh))
             }

             HStack(spacing: 28) {
                 metricBlock(title: "最高速度 (km/h)",
                             value: String(format: "%.1f", summary.topSpeedKmh))
                 metricBlock(title: "用时",
                             value: summary.durationText)
             }

             if let drop = summary.elevationDropM {
                 metricBlock(title: "落差 (m)", value: "\(drop)")
                     .frame(maxWidth: .infinity)
             }
         }
         .padding(.horizontal, 20)
         .padding(.top, 12)
         .presentationDetents([.fraction(0.42), .medium])
         .presentationDragIndicator(.visible)
         .modifier(PresentationCornerRadiusIfAvailable(24))
         .presentationBackground(.regularMaterial)



         .buttonStyle(.borderedProminent)
         .controlSize(.large)
         .padding(.top, 8)

     }




     private func metricBlock(title: String, value: String) -> some View {
         VStack(spacing: 6) {
             Text(value)
                 .font(.system(size: 42, weight: .semibold))
                 .minimumScaleFactor(0.7)
                 .lineLimit(1)
                 .monospacedDigit()
             Text(title)
                 .font(.caption)
                 .foregroundColor(.gray)
         }
         .frame(maxWidth: .infinity)
     }
 }

 // 兼容性处理：iOS 17 才有 presentationCornerRadius
 private struct PresentationCornerRadiusIfAvailable: ViewModifier {
     let radius: CGFloat
     init(_ radius: CGFloat) { self.radius = radius }
     func body(content: Content) -> some View {
         if #available(iOS 17.0, *) {
             content.presentationCornerRadius(radius)
         } else {
             content
         }
     }
 }

*/
