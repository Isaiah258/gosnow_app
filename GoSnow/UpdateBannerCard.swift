//
//  UpdateBannerCard.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/12/17.
//

import SwiftUI
import Kingfisher

struct UpdateBannerCard: View {
    // 内容
    let bannerImageURL: String?        // 横幅图（可为空）
    let title: String                  // 可选标题（你也可以传空）
    let message: String                // 说明文字

    // 行为
    let appStoreURL: URL               // 去更新跳 AppStore
    var onDismiss: () -> Void          // 稍后更新 -> 关闭

    // ✅ 关键：外层水平边距（toast 需要 0；floater 可用 20）
    var horizontalInset: CGFloat = 0

    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme

    // 你可以按喜好调这些参数
    private let cardCorner: CGFloat = 22
    private let bannerHeight: CGFloat = 110

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Banner
            if let urlStr = bannerImageURL, let url = URL(string: urlStr) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(height: bannerHeight)
                    .clipped()
                    .clipShape(RoundedCorners(radius: cardCorner, corners: [.topLeft, .topRight]))
            } else {
                // 无图占位（你后面有图了就不会看到）
                ZStack {
                    LinearGradient(
                        colors: [Color(.tertiarySystemFill), Color(.secondarySystemBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.55))
                }
                .frame(height: bannerHeight)
                .clipShape(RoundedCorners(radius: cardCorner, corners: [.topLeft, .topRight]))
            }

            // MARK: - Content
            VStack(alignment: .leading, spacing: 10) {
                if !title.isEmpty {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.top, 2)
                }

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // 主按钮：去更新
                Button {
                    openURL(appStoreURL)
                } label: {
                    Text("去更新")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.92))
                        )
                        .foregroundStyle(Color(UIColor.systemBackground))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                // 灰字：稍后更新
                Button {
                    onDismiss()
                } label: {
                    Text("稍后更新")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedCorners(radius: cardCorner, corners: [.bottomLeft, .bottomRight]))
        }
        .background(
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(
            color: scheme == .dark ? .clear : .black.opacity(0.12),
            radius: 18, x: 0, y: 10
        )
        // ✅ 关键：原来这里是固定 .padding(.horizontal, 20)
        .padding(.horizontal, horizontalInset)
    }
}

// MARK: - 指定圆角的 Shape（只圆顶部或底部）
struct RoundedCorners: Shape {
    var radius: CGFloat = 16
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let p = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(p.cgPath)
    }
}
