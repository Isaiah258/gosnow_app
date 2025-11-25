//
//  UpdateMockOverlay.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/12/17.
//

import SwiftUI

/// ✅ 真机调试用：模拟“更新公告弹窗”
/// - DEBUG 下可用；上线前你把触发条件换成后端即可
struct UpdateMockOverlay: View {
    @Binding var isPresented: Bool

    /// 你可以在这里随时改文案/图/链接
    private let bannerURL = "https://picsum.photos/900/320" // 先用占位图，你后面换成自己的横幅
    private let appStoreURL = URL(string: "https://apps.apple.com/app/id1234567890")! // TODO: 换成你的 App ID

    var body: some View {
        ZStack {
            // 背景遮罩（点一下也能关闭，符合多数 App 习惯）
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    // 如果你不想点外面关闭，把这段删掉即可
                    isPresented = false
                }

            // 卡片
            UpdateBannerCard(
                bannerImageURL: bannerURL,
                title: "新版本已上线",
                message: "本次更新优化了记录稳定性，并提升地图与雪道展示的流畅度。",
                appStoreURL: appStoreURL,
                onDismiss: { isPresented = false }   // “稍后更新”
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .animation(.easeOut(duration: 0.22), value: isPresented)
    }
}
