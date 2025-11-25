//
//  RoommateView.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/11/30.
//

import SwiftUI
import Supabase

// 列表行只用到部分字段，单独一个轻量 struct
struct RoommateRow: Decodable, Identifiable {
    let id: UUID
    let resort_id: Int
    let content: String
    let is_hidden: Bool
    let canceled_at: Date?
    let created_at: Date
}

struct RoommateView: View {
    @State private var resorts: [Resorts_data] = []
    @State private var selectedResortId: Int? = nil

    @State private var items: [RoommateRow] = []
    @State private var isLoading = false
    @State private var fetchError: Error?
    @State private var page = 0
    private let pageSize = 10
    @State private var hasMore = true

    @State private var showResortPicker = false
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground),
                             Color(.secondarySystemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 10) {
                    // 顶部：雪场筛选
                    HStack(spacing: 10) {
                        Button { openResortPicker() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bed.double.fill")
                                Text(selectedResortName ?? "所有雪场")
                                    .lineLimit(1)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.horizontal)

                    // 列表
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if isLoading && items.isEmpty {
                                VStack {
                                    ProgressView().padding(.vertical, 24)
                                }
                                .frame(maxWidth: .infinity)
                            } else if let err = fetchError, items.isEmpty {
                                Text("加载失败：\(err.localizedDescription)")
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.vertical, 24)
                                    .frame(maxWidth: .infinity)
                            } else if items.isEmpty {
                                Text("暂无拼房信息")
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 24)
                                    .frame(maxWidth: .infinity)
                            } else {
                                ForEach(items) { item in
                                    RoommateCard(
                                        item: item,
                                        resortName: resortName(for: item.resort_id)
                                    )
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                }

                                if hasMore {
                                    HStack { Spacer(); ProgressView(); Spacer() }
                                        .padding(.vertical, 16)
                                        .task { await loadNextPage() }
                                }
                            }

                            Spacer(minLength: 8)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { await resetAndFetch() }
                }
            }
            .navigationTitle("拼房合租")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink { MyRoommateView() } label: {
                        Image(systemName: "note.text")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showResortPicker) {
                ResortPickerSheet(
                    resorts: resorts,
                    selectedResortId: $selectedResortId
                ) {
                    Task { await resetAndFetch() }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddRoommateView(onPublished: {
                    showAddSheet = false
                    Task { await resetAndFetch() }
                })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .task {
                await loadResortsIfNeeded()
                await resetAndFetch()
            }
        }
    }

    // MARK: - Helpers

    private func openResortPicker() {
        Task {
            if resorts.isEmpty {
                do {
                    resorts = try await RoommateAPI.fetchAllResorts()
                } catch {
                    fetchError = error
                    return
                }
            }
            showResortPicker = true
        }
    }

    private var selectedResortName: String? {
        guard let id = selectedResortId else { return nil }
        return resorts.first(where: { $0.id == id })?.name_resort
    }

    private func resortName(for id: Int) -> String? {
        resorts.first(where: { $0.id == id })?.name_resort
    }

    private func loadResortsIfNeeded() async {
        guard resorts.isEmpty else { return }
        do {
            resorts = try await RoommateAPI.fetchAllResorts()
        } catch {
            print("❌ 获取雪场失败：\(error)")
        }
    }

    private func resetAndFetch() async {
        page = 0
        hasMore = true
        items.removeAll()
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var q = DatabaseManager.shared.client
                .from("roommate_posts")
                .select("id,resort_id,content,is_hidden,canceled_at,created_at")

            // 只看未隐藏未取消
            q = q.eq("is_hidden", value: false)
                 .is("canceled_at", value: nil)

            // 按雪场筛选
            if let rid = selectedResortId {
                q = q.eq("resort_id", value: rid)
            }

            let from = page * pageSize
            let to = from + pageSize - 1

            let pageItems: [RoommateRow] = try await q
                .order("created_at", ascending: false)
                .range(from: from, to: to)
                .execute()
                .value

            items.append(contentsOf: pageItems)
            hasMore = pageItems.count == pageSize
            if hasMore { page += 1 }
        } catch {
            fetchError = error
            hasMore = false
        }
    }
}

// 卡片：只重点展示正文，其他信息尽量淡化
private struct RoommateCard: View {
    let item: RoommateRow
    let resortName: String?

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部：雪场 + 时间
            HStack(spacing: 8) {
                if let name = resortName {
                    Text(name)
                        .font(.headline)
                }
                Spacer()
                Text(dateText(item.created_at))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 正文（自由描述）
            Text(item.content)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            

            Divider().padding(.top, 10)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: d)
    }
}
