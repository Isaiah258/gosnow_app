//
//  DailySnowView.swift
//  GoSnow
//
//  Created by federico Liu on 2024/6/18.
//
import SwiftUI

struct DailySnowView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        // 雪圈

                        // 雪场（与雪圈同级）
                        CardLink(
                            title: "雪场",
                            subtitle: "搜索雪场、看数据与图表",
                            icon: "map.fill",
                            tint: .green
                        ) {
                            ResortsView()
                        }

                        // 失物招领
                        CardLink(
                            title: "失物招领",
                            subtitle: "丢失？捡到？这里快速对接",
                            icon: "magnifyingglass",
                            tint: .purple
                        ) {
                            LostAndFoundView()
                        }

                        // 顺风车
                        CardLink(
                            title: "顺风车",
                            subtitle: "按雪场/日期找同行",
                            icon: "car.fill",      // 如想更像拼车可试 "car.2.fill"（iOS 16+）
                            tint: .orange
                        ) {
                            CarpoolView()
                        }

                        CardLink(
                            title: "合租拼房",
                            subtitle: "寻找合租雪友",
                            icon: "house.fill",
                            tint: .indigo
                        ) {
                            RoommateView()
                        }

                        // ✅ 点击后直接弹 PopupView（不导航）
                        ActionCardLink(
                            title: "更新弹窗预览",
                            subtitle: "UpdateNoticeCard",
                            icon: "sparkles",
                            tint: .pink
                        ) {
                            NotificationCenter.default.post(name: .debugShowUpdatePopup, object: nil)
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("发现")
        }
    }
}

#Preview {
    DailySnowView()
}

// MARK: - 统一风格卡片链接（复用你项目里的 RoundedContainer / IconBadge）
private struct CardLink<Destination: View>: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let tint: Color
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination().navigationBarTitleDisplayMode(.inline)) {
            RoundedContainer {
                HStack(spacing: 14) {
                    IconBadge(system: icon, tint: tint)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 72)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ✅ 不导航：点击直接执行 action（用于弹 Popup）
private struct ActionCardLink: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedContainer {
                HStack(spacing: 14) {
                    IconBadge(system: icon, tint: tint)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 72)
            }
        }
        .buttonStyle(.plain)
    }
}
