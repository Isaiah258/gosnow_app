//
//  SessionSummarySheet.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/8/10.
//

// Recording/UI/SessionSummarySheet.swift
import SwiftUI
import UIKit


// MARK: - Main Sheet

struct SessionSummarySheet: View {
    let summary: SessionSummary
    let routeImage: UIImage?

    @State private var energyKcal: Double? = nil
    @State private var hasTriedFetchEnergy: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {

                routePreview

                header

                LazyVGrid(columns: columns, spacing: 14) {

                    // ✅ 距离 -> 里程；图标改成 road.lanes
                    MetricCard(
                        title: "里程",
                        value: String(format: "%.1f", summary.distanceKm),
                        unit: "km",
                        icon: "flag.pattern.checkered",
                        iconTint: .green
                    )

                    MetricCard(
                        title: "用时",
                        value: summary.durationText,
                        unit: nil,
                        icon: "timer",
                        iconTint: .cyan
                    )

                    MetricCard(
                        title: "最高速度",
                        value: String(format: "%.1f", summary.topSpeedKmh),
                        unit: "km/h",
                        icon: "speedometer",
                        iconTint: .orange
                    )

                    MetricCard(
                        title: "能量",
                        value: energyText,
                        unit: energyKcal == nil ? nil : "kcal",
                        icon: "flame.fill",
                        iconTint: .red
                    )
                }

                if let drop = summary.elevationDropM {
                    WideMetricCard(
                        title: "落差",
                        value: "\(drop)",
                        unit: "m",
                        icon: "mountain.2.fill",
                        iconTint: .mint
                    )
                }

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .background(Color.black.ignoresSafeArea())
        .presentationDetents([.fraction(0.60), .medium])
        .presentationDragIndicator(.visible)
        .modifier(PresentationCornerRadiusIfAvailable(28))
        .presentationBackground(.black)
        .task { await loadEnergySilentlyIfPossible() }
    }

    // MARK: - Route Preview

    private var routePreview: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        return ZStack(alignment: .bottomLeading) {

            Group {
                if let img = routeImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 10) {
                        ProgressView().tint(.white.opacity(0.90))
                        Text("正在生成路线图")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                        Text("不会影响总结展示")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Text("路线预览")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.35))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .clipShape(Capsule())
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(shape.fill(Color.white.opacity(0.06)))
        .clipShape(shape)
        .overlay(glassStroke(corner: 24))
        .shadow(color: Color.black.opacity(0.70), radius: 22, y: 14)
        .shadow(color: Color.white.opacity(0.05), radius: 1, y: -1)
        .padding(.top, 6)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("本次滑行总结")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text(timeRangeText(start: summary.startAt, end: summary.endAt))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    // MARK: - Energy

    private var energyText: String {
        if let kcal = energyKcal { return String(format: "%.0f", kcal) }
        return "–"
    }

    private func loadEnergySilentlyIfPossible() async {
        guard hasTriedFetchEnergy == false else { return }
        hasTriedFetchEnergy = true
        energyKcal = await HealthEnergyStore.shared.fetchActiveEnergyKcalIfAuthorized(
            start: summary.startAt,
            end: summary.endAt
        )
    }

    private func timeRangeText(start: Date, end: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        return "\(f.string(from: start)) - \(f.string(from: end))"
    }

    // MARK: - Glass Stroke Helper

    private func glassStroke(corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.10),
                        Color.black.opacity(0.45)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

// MARK: - Metric Cards (Icon tinted only, circle NOT tinted)

private struct MetricCard: View {
    let title: String
    let value: String
    let unit: String?
    let icon: String
    let iconTint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 10) {
                ZStack {
                    // ✅ 圆圈不带颜色：统一灰玻璃
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .frame(width: 30, height: 30)

                    // ✅ 只有图标带颜色
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconTint)
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                if let unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.60))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0.08),
                                    Color.black.opacity(0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.62), radius: 18, y: 12)
        .shadow(color: Color.white.opacity(0.05), radius: 1, y: -1)
    }
}

private struct WideMetricCard: View {
    let title: String
    let value: String
    let unit: String?
    let icon: String
    let iconTint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                // ✅ 圆圈不带颜色：统一灰玻璃
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .frame(width: 30, height: 30)

                // ✅ 只有图标带颜色
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint)
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                if let unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.60))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0.08),
                                    Color.black.opacity(0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.62), radius: 18, y: 12)
        .shadow(color: Color.white.opacity(0.05), radius: 1, y: -1)
    }
}

// MARK: - iOS 17 corner radius helper

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
