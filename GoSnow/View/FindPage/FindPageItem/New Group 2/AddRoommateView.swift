//
//  AddRoommateView.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/11/30.
//

import SwiftUI
import Supabase

struct AddRoommateView: View {
    var onPublished: (() -> Void)? = nil

    @State private var selectedResort: ResortRef? = nil
    @State private var content: String = ""

    @State private var resorts: [ResortRef] = []
    @State private var searchText: String = ""
    @State private var isPublishing = false
    @State private var uploadMessage: String = ""
    @State private var showUploadAlert = false

    private var isPublishButtonEnabled: Bool {
        selectedResort != nil &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                // MARK: - 雪场选择
                Section(header: Text("雪场")) {

                    TextField("搜索雪场", text: $searchText)
                        .textInputAutocapitalization(.none)
                        .disableAutocorrection(true)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 8)
                        .onChange(of: searchText) { _, key in
                            Task { await searchResorts(key) }
                        }

                    if !searchText.isEmpty {
                        List(filteredResorts, id: \.id) { r in
                            Button {
                                selectedResort = r
                                searchText = ""
                            } label: {
                                HStack {
                                    Text(r.name)
                                    if selectedResort?.id == r.id {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    } else if let r = selectedResort {
                        Text("已选择雪场：\(r.name)")
                            .font(.headline)
                            .padding(.vertical, 4)
                    }
                }

                // MARK: - 正文（去掉边框）
                Section(header: Text("正文描述（请简短有效附带联系方式）")) {
                    ZStack(alignment: .topLeading) {
                        // 简单占位提示（content 为空时显示）
                        
                        TextEditor(text: $content)
                            .frame(minHeight: 160)
                            .padding(.leading, -4) // 稍微对齐系统内边距
                    }
                }

                // MARK: - 免责声明 + 发布按钮
                Section(
                    footer:
                        Text("本功能仅提供信息发布与对接，平台不参与任何交易，也不承担担保或赔付责任。请自行核验对方身份、房源与合同。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                ) {
                    if isPublishing {
                        ProgressView("发布中…")
                    } else {
                        Button("发布", action: publish)
                            .disabled(!isPublishButtonEnabled)
                    }
                }
            }
            .navigationBarTitle("发布拼房合租", displayMode: .inline)
            .onAppear {
                Task { await searchResorts("") }   // 默认加载一些雪场
            }
            .alert(isPresented: $showUploadAlert) {
                Alert(
                    title: Text("状态"),
                    message: Text(uploadMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: - 雪场搜索

    private var filteredResorts: [ResortRef] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return resorts }
        return resorts.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private func searchResorts(_ key: String) async {
        do {
            struct Row: Decodable { let id: Int; let name_resort: String }
            let rows: [Row] = try await DatabaseManager.shared.client
                .from("Resorts_data")
                .select("id,name_resort")
                .ilike("name_resort", pattern: key.isEmpty ? "%" : "%\(key)%")
                .limit(30)
                .execute()
                .value

            let mapped = rows.map { ResortRef(id: $0.id, name: $0.name_resort) }
            await MainActor.run { self.resorts = mapped }
        } catch {
            await MainActor.run { self.resorts = [] }
        }
    }

    // MARK: - 发布

    private func publish() {
        guard isPublishButtonEnabled, let r = selectedResort else { return }
        isPublishing = true

        Task {
            defer {
                isPublishing = false
                showUploadAlert = true
            }
            do {
                guard let user = DatabaseManager.shared.getCurrentUser() else {
                    throw NSError(
                        domain: "auth",
                        code: 401,
                        userInfo: [NSLocalizedDescriptionKey: "未登录"]
                    )
                }

                struct Payload: Encodable {
                    let user_id: UUID
                    let resort_id: Int
                    let content: String
                    let is_hidden: Bool = false
                }

                let body = content.trimmingCharacters(in: .whitespacesAndNewlines)

                let payload = Payload(
                    user_id: user.id,
                    resort_id: Int(r.id),
                    content: body
                )

                try await DatabaseManager.shared.client
                    .from("roommate_posts")
                    .insert(payload)
                    .execute()

                uploadMessage = "发布成功"
                onPublished?()
            } catch {
                uploadMessage = "发布失败：\(error.localizedDescription)"
            }
        }
    }
}
