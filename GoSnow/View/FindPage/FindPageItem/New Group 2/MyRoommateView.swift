//
//  MyRoommateView.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/11/30.
//

import SwiftUI
import Supabase

struct MyRoommateView: View {
    @State private var items: [RoommatePost] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                if isLoading && items.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let e = error {
                    Text("加载失败：\(e)").foregroundStyle(.red)
                } else if items.isEmpty {
                    Text("你还没有发布拼房信息").foregroundStyle(.secondary)
                } else {
                    ForEach(items) { p in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(dateText(p.created_at))
                                    .font(.headline)
                                Spacer()
                                if p.is_hidden {
                                    Text("已取消")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text("雪场ID：\(p.resort_id)")
                                .foregroundStyle(.secondary)

                            Text(p.content)
                                .lineLimit(3)
                        }
                        .swipeActions(edge: .trailing) {
                            if p.is_hidden {
                                Button {
                                    Task {
                                        try? await RoommateAPI.restorePost(id: p.id)
                                        await reload()
                                    }
                                } label: {
                                    Label("恢复", systemImage: "arrow.uturn.backward.circle")
                                }
                            } else {
                                Button(role: .destructive) {
                                    Task {
                                        try? await RoommateAPI.cancelPost(id: p.id)
                                        await reload()
                                    }
                                } label: {
                                    Label("取消", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("左滑可\(Text("取消 / 恢复").bold())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("我的拼房")
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await RoommateAPI.fetchMyPosts()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: d)
    }
}
