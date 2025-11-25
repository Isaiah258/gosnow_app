//
//  ResortsCommunityView.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/10/7.
//

import SwiftUI
import Kingfisher
import Supabase
import SKPhotoBrowser

// MARK: - Page

struct ResortsCommunityView: View {
    @StateObject private var notiVM = NotificationsVM()
    @State private var showNotifications = false

    @StateObject private var vm = FeedVM()
    @State private var query: String = ""
    @State private var path: NavigationPath = NavigationPath()
    
    @State private var showImageViewer = false
    @State private var viewerIndex = 0
    @State private var viewerURLs: [URL] = []
    
    @State private var showMyPosts = false

    // 雪场匹配
    @State private var resortMatches: [ResortRef] = []
    @State private var resortSearching = false
    @State private var resortSearchTask: Task<Void, Never>? = nil

    // 选中的雪场（顶部横卡展示）
    @State private var selectedResort: ResortRef? = nil

    @State private var showingComposer = false
    @State private var showErrorAlert = false

    @FocusState private var searchFocused: Bool

    // 关键词过滤
    private var filteredByQuery: [ResortPost] {
        let src = vm.items
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return src }
        return src.filter {
            ($0.title?.localizedCaseInsensitiveContains(q) ?? false) ||
            ($0.text?.localizedCaseInsensitiveContains(q) ?? false) ||
            $0.author.name.localizedCaseInsensitiveContains(q) ||
            $0.resort.name.localizedCaseInsensitiveContains(q)
        }
    }

    // MARK: - 对外 body：只返回 mainView，减轻类型推断压力
    var body: some View {
        mainView
    }

    // MARK: - mainView：挂各种 sheet / alert / task / onChange
    private var mainView: some View {
        navigationStack
            // 发帖
            .sheet(isPresented: $showingComposer) {
                composeSheet
            }

            // 通知中心
            .sheet(isPresented: $showNotifications) {
                notificationsSheet      // ⬅️ 用一个单独的 computed view
            }

            // 我的帖子
            .sheet(
                isPresented: $showMyPosts,
                onDismiss: {
                    Task { await vm.refresh() }     // 关闭后刷新主列表
                }
            ) {
                myPostsSheet             // ⬅️ 同样拆出去
            }

            // 错误弹窗
            .alert(
                "出错了",
                isPresented: $showErrorAlert,
                presenting: vm.lastErrorMessage
            ) { _ in
                Button("好的", role: .cancel) { vm.lastErrorMessage = nil }
            } message: { msg in
                Text(msg)
            }

            // 键盘处理
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    searchFocused = false
                }
            )

            // 按类型导航
            .navigationDestination(for: Int.self) { id in
                ChartsOfSnowView(resortId: id)
            }
            .navigationDestination(for: ResortPost.self) { post in
                ResortsPostDetailView(
                    post: post,
                    onToggleLike: { post, toLiked in
                        Task { await toggleLike(for: post, to: toLiked) }
                    },
                    onAddComment: { post, text in
                        Task { await addComment(for: post, body: text) }
                    }
                )
            }

            // 图片查看器挂在最外层背景
            .background(
                SKPhotoBrowserPresenter(
                    isPresented: $showImageViewer,
                    urls: viewerURLs,
                    startIndex: viewerIndex
                )
            )

            // 首次加载
            .task {
                await vm.loadInitialIfNeeded()
                await notiVM.load()
            }

            // 错误状态联动 alert 显隐
            .onChange(of: vm.lastErrorMessage) { _, new in
                showErrorAlert = (new != nil)
            }

            // 搜索关键字防抖
            .onChange(of: query) { _, newValue in
                handleQueryChange(newValue)
            }
    }


    // MARK: - NavigationStack：只负责导航和顶部 toolbar
    private var navigationStack: some View {
        NavigationStack(path: $path) {
            scrollContent
        }
        .background(Color(.systemBackground))
        .navigationTitle("雪圈")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 左上角：通知铃铛
            ToolbarItem(placement: .topBarLeading) {
                NotificationsBellButton(vm: notiVM) {
                    showNotifications = true
                }
            }

            // 右上角：我的帖子 + 发帖
            ToolbarItemGroup(placement: .topBarTrailing) {
                // 我的帖子管理
                Button {
                    showMyPosts = true
                } label: {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("我的帖子")

                // 发帖
                Button {
                    showingComposer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                }
                .accessibilityLabel("发布")
            }
        }
        // 按类型导航
        .navigationDestination(for: Int.self) { id in
            ChartsOfSnowView(resortId: id)
        }
        .navigationDestination(for: ResortPost.self) { post in
            ResortsPostDetailView(
                post: post,
                onToggleLike: { post, toLiked in
                    Task { await toggleLike(for: post, to: toLiked) }
                },
                onAddComment: { post, text in
                    Task { await addComment(for: post, body: text) }
                }
            )
        }
    }

    // MARK: - ScrollView 内容
    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {

                // 标题 + 搜索
                header

                // 搜索时：展示匹配雪场 chips（未选中时显示）
                if selectedResort == nil,
                   !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resortMatchesBlock
                }

                // 已选中：顶部横向小卡片
                if let r = selectedResort {
                    ResortHeaderCard(
                        ref: r,
                        onClear: {
                            selectedResort = nil
                            Task { await vm.setResortFilter(nil) }
                        },
                        onOpenDetail: { path.append(r.id) } // 直接压入 Int
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }

                // 帖子列表
                contentList
            }
            .background(Color(.systemBackground))
            .contentShape(Rectangle())
            .onTapGesture { searchFocused = false } // 点击空白收起键盘
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("雪圈")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)

            // 搜索
            SearchField(
                text: $query,
                placeholder: "搜索雪场或帖子",
                isFocused: $searchFocused
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - 雪场匹配 & 选择

    private var resortMatchesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("匹配雪场").font(.headline)
                if resortSearching { ProgressView().scaleEffect(0.8) }
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(resortMatches, id: \.id) { r in
                        Button {
                            // 选中雪场 → 顶部横卡 + 刷新筛选
                            selectedResort = r
                            query = ""
                            Task { await vm.setResortFilter(r.id) }

                            // 立刻导航到详情（传 Int id）
                            searchFocused = false
                            path.append(r.id)
                        } label: {
                            HStack(spacing: 8) {
                                Text(r.name)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.systemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(.black.opacity(0.06), lineWidth: 1 / UIScreen.main.scale)
                            )
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - 帖子列表

    @ViewBuilder
    private var contentList: some View {
        if vm.isLoadingInitial {
            VStack(spacing: 16) {
                ForEach(0..<5, id: \.self) { _ in RowSkeleton().padding(.horizontal, 20) }
            }
            .padding(.top, 12)
        } else if let err = vm.initialError {
            VStack(spacing: 10) {
                Text("加载失败").font(.headline)
                Text(err)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await vm.refresh() }
                } label: {
                    Text("重试")
                        .bold()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 20)
        } else if filteredByQuery.isEmpty {
            VStack(spacing: 6) {
                Text("暂无帖子").font(.headline)
                Text(selectedResort == nil ? "可先搜索并选择一个雪场" : "这个雪场还没有帖子，去发布一条吧！")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(filteredByQuery) { (p: ResortPost) in
                    PostRow(
                        post: p,
                        onAppearAtEnd: {
                            if p.id == filteredByQuery.last?.id {
                                Task { await vm.loadMoreIfNeeded() }
                            }
                        },
                        onDelete: p.canDelete ? { Task { await vm.delete(p) } } : nil,
                        onReport: { Task { await vm.report(p) } },
                        onOpenDetail: { path.append(p) },
                        onTapImageAt: { tapped in
                            viewerURLs = p.mediaURLs
                            viewerIndex = tapped
                            showImageViewer = true
                        },
                        onToggleLike: { post, toLiked in
                            Task { await toggleLike(for: post, to: toLiked) }
                        },
                        onAddComment: { post, body in
                            Task { await addComment(for: post, body: body) }
                        }
                    )
                    .padding(.bottom, 8)

                    Divider()
                        .padding(.leading, 20)
                        .padding(.vertical, 8)
                }

                if vm.isPaginating {
                    HStack {
                        Spacer()
                        ProgressView().padding(.vertical, 16)
                        Spacer()
                    }
                } else if vm.reachedEnd && !vm.items.isEmpty {
                    Text("没有更多了")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - 发帖 sheet 内容

    @ViewBuilder
    private var composeSheet: some View {
        ResortsPostComposerView { didPost in
            if didPost { Task { await vm.refresh() } }
        }
    }
    // MARK: - 通知中心 sheet 内容

    @ViewBuilder
    private var notificationsSheet: some View {
        NavigationStack {
            NotificationsCenterView(
                vm: notiVM,
                onTapPost: { postId in
                    showNotifications = false
                    if let p = vm.items.first(where: { $0.id == postId }) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            path.append(p)
                        }
                    }
                }
            )
        }
    }

    // MARK: - 我的帖子 sheet 内容

    @ViewBuilder
    private var myPostsSheet: some View {
        NavigationStack {
            MyResortPostsView { post in
                // 关闭「我的帖子」后，再跳转到详情
                showMyPosts = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    path.append(post)
                }
            }
        }
    }


    // MARK: - 搜索雪场（防抖）

    private func handleQueryChange(_ newValue: String) {
        resortSearchTask?.cancel()
        let text = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            resortMatches = []
            resortSearching = false
            return
        }
        guard selectedResort == nil else { return }

        resortSearching = true
        resortSearchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            await searchResorts(keyword: text)
        }
    }

    private func searchResorts(keyword: String) async {
        do {
            struct Row: Decodable { let id: Int; let name_resort: String }
            let rows: [Row] = try await DatabaseManager.shared.client
                .from("Resorts_data")
                .select("id,name_resort")
                .ilike("name_resort", pattern: "%\(keyword)%")
                .limit(10)
                .execute()
                .value
            resortMatches = rows.map { .init(id: $0.id, name: $0.name_resort) }
        } catch {
            resortMatches = []
        }
        resortSearching = false
    }

    // MARK: - 数据操作（点赞 / 评论 / 通知）

    private func toggleLike(for post: ResortPost, to liked: Bool) async {
        let c = DatabaseManager.shared.client
        do {
            guard let u = try? await c.auth.user() else {
                vm.lastErrorMessage = "请先登录"
                return
            }
            if liked {
                struct InsertLike: Encodable { let post_id: UUID; let author_id: UUID }
                _ = try await c
                    .from("resorts_post_likes")
                    .insert(InsertLike(post_id: post.id, author_id: u.id))
                    .execute()

                if let recipient = post.authorId, recipient != u.id {
                    struct InsertNotif: Encodable {
                        let recipient_user_id: UUID
                        let actor_user_id: UUID
                        let type: String
                        let post_id: UUID
                    }
                    _ = try? await c
                        .from("resorts_notifications")
                        .insert(InsertNotif(
                            recipient_user_id: recipient,
                            actor_user_id: u.id,
                            type: "like_post",
                            post_id: post.id
                        ))
                        .execute()
                }
            } else {
                _ = try await c
                    .from("resorts_post_likes")
                    .delete()
                    .eq("post_id", value: post.id)
                    .eq("author_id", value: u.id)
                    .execute()
            }

        } catch {
            vm.lastErrorMessage = (error as NSError).localizedDescription
        }
    }

    private func addComment(for post: ResortPost, body: String) async {
        let c = DatabaseManager.shared.client
        do {
            guard let u = try? await c.auth.user() else {
                vm.lastErrorMessage = "请先登录"
                return
            }
            struct InsertComment: Encodable { let post_id: UUID; let user_id: UUID; let body: String }
            _ = try await c
                .from("resorts_post_comments")
                .insert(InsertComment(post_id: post.id, user_id: u.id, body: body))
                .execute()

            if let recipient = post.authorId, recipient != u.id {
                struct InsertNotif: Encodable {
                    let recipient_user_id: UUID
                    let actor_user_id: UUID
                    let type: String
                    let post_id: UUID
                }
                _ = try? await c
                    .from("resorts_notifications")
                    .insert(InsertNotif(
                        recipient_user_id: recipient,
                        actor_user_id: u.id,
                        type: "comment_post",
                        post_id: post.id
                    ))
                    .execute()
            }

        } catch {
            vm.lastErrorMessage = (error as NSError).localizedDescription
        }
    }
}



// MARK: - 顶部小雪场卡片（横向）

private struct ResortHeaderCard: View {
    let ref: ResortRef
    var onClear: () -> Void
    var onOpenDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Button(action: onOpenDetail) {
                    HStack(spacing: 4) {
                        Text("查看雪场详情")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.black.opacity(0.06), lineWidth: 1 / UIScreen.main.scale)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
    }
}

// MARK: - 适配原图比例的远程图（列表用）

// MARK: - 首页列表图片（按比例分档渲染）
private struct FeedImage: View {
    let url: URL
    private let corner: CGFloat = 12
    private let containerW: CGFloat = UIScreen.main.bounds.width - 40 // 列表里左右各20的内边距
    private let placeholderH: CGFloat = 240
    private let normalMaxH: CGFloat = 420
    private let tallMaxH: CGFloat = 480

    @State private var aspect: CGFloat? = nil // 宽/高

    // 计算展示高度与模式
    private func layout(for a: CGFloat?) -> (height: CGFloat, fill: Bool) {
        guard let a, a > 0 else {
            return (placeholderH, true) // 未知先给稳定占位，fill 让占位更好看
        }
        if a < 0.8 {
            return (min(containerW / 0.8, tallMaxH), true)   // 超窄竖
        } else if a > 1.9 {
            return (220, true)                               // 超宽横
        } else {
            return (min(containerW / a, normalMaxH), false)  // 常规
        }
    }

    var body: some View {
        let (h, useFill) = layout(for: aspect)

        KFImage(url)
            .onSuccess { r in
                let sz = r.image.size
                if sz.width > 0, sz.height > 0 {
                    aspect = sz.width / sz.height
                }
            }
            .placeholder {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                    )
                    .frame(width: containerW, height: h)
                    .frame(height: h)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            }
            .resizable()
            .modifier(AspectModeModifier(useFill: useFill, aspect: aspect))
            .frame(width: containerW, height: h)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .contentShape(Rectangle())
    }
}

// 小工具：根据 useFill 选择 Fill/Fit
private struct AspectModeModifier: ViewModifier {
    let useFill: Bool
    let aspect: CGFloat?

    func body(content: Content) -> some View {
        if let a = aspect, a > 0, !useFill {
            content.aspectRatio(a, contentMode: .fit)
        } else {
            content.scaledToFill()
        }
    }
}

// MARK: - 帖子行（仿推特底部操作栏 + 内联评论）

private struct PostRow: View {
    let post: ResortPost
    var onAppearAtEnd: () -> Void
    var onDelete: (() -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var onOpenDetail: (() -> Void)? = nil
    var onTapImageAt: ((Int) -> Void)? = nil
    var onToggleLike: ((ResortPost, Bool) -> Void)? = nil
    var onAddComment: ((ResortPost, String) -> Void)? = nil

    @State private var page = 0
    @State private var showDeleteConfirm = false

    // UI 状态（乐观更新）
    @State private var likedByMe: Bool
    @State private var likeCount: Int
    @State private var commentCount: Int
    @State private var showComposer = false
    @State private var commentText = ""
    @State private var sending = false
    @State private var likePop = false   // 新增：点赞弹跳

    init(
        post: ResortPost,
        onAppearAtEnd: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onReport: (() -> Void)? = nil,
        onOpenDetail: (() -> Void)? = nil,
        onTapImageAt: ((Int) -> Void)? = nil,
        onToggleLike: ((ResortPost, Bool) -> Void)? = nil,
        onAddComment: ((ResortPost, String) -> Void)? = nil
    ) {
        self.post = post
        self.onAppearAtEnd = onAppearAtEnd
        self.onDelete = onDelete
        self.onReport = onReport
        self.onOpenDetail = onOpenDetail
        self.onTapImageAt = onTapImageAt
        self.onToggleLike = onToggleLike
        self.onAddComment = onAddComment
        _likedByMe = State(initialValue: post.likedByMe)
        _likeCount = State(initialValue: post.likeCount)
        _commentCount = State(initialValue: post.commentCount)
    }

    // 文本显示约束
    private let maxLines = 8
    private let maxChars = 2000

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // 顶部：作者 + 时间 + 菜单
            HStack(spacing: 12) {
                KFImage(post.author.avatarURL)
                    .placeholder { Circle().fill(Color(.tertiarySystemFill)) }
                    .setProcessor(DownsamplingImageProcessor(size: .init(width: 40, height: 40)))
                    .cacheOriginalImage()
                    .resizable().scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author.name).font(.subheadline.weight(.semibold))
                    Text(post.timeText).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    if let onReport { Button("举报") { onReport() } }
                    if onDelete != nil {
                        Button("删除", role: .destructive) { showDeleteConfirm = true }
                    }

                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .confirmationDialog("确认删除这条帖子？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    if let onDelete { Button("删除", role: .destructive) { onDelete() } }
                    Button("取消", role: .cancel) {}
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 20)

            // 卡片主体可点击
            VStack(alignment: .leading, spacing: 8) {
                if let t = post.title, !t.isEmpty {
                    Text(t)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                if let text = post.text, !text.isEmpty {
                    let limited = String(text.prefix(maxChars))
                    Text(limited)
                        .font(.system(size: 15))        // 稍微小一点、偏 Twitter 的感觉
                        .foregroundStyle(.primary)
                        .lineSpacing(4)                 // 行距拉开一点
                        .padding(.top, 2)               // 和标题之间留一点空气
                        .lineLimit(maxLines)
                        .truncationMode(.tail)
                }

            }
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
            .onTapGesture { onOpenDetail?() }

            if !post.mediaURLs.isEmpty {
                FeedMediaViewKF(urls: post.mediaURLs) { tapped in
                    onTapImageAt?(tapped)
                }
            }

            // 底部一行：左雪场，右评论/点赞
            HStack(spacing: 16) {
                // 左：雪场胶囊（点击也能进详情）
                ResortTagCapsule(name: post.resort.name)
                    .onTapGesture { onOpenDetail?() }

                Spacer()

                // 右：评论按钮
                Button {
                    withAnimation(.spring) { showComposer.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "message")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(commentCount)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                // 右：点赞按钮（带弹跳 + 触感）
                Button {
                    let toLiked = !likedByMe
                    likedByMe = toLiked
                    likeCount += toLiked ? 1 : -1
                    onToggleLike?(post, toLiked)

                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                        likePop.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: likedByMe ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(likedByMe ? .red : .secondary)
                            .scaleEffect(likePop ? 1.18 : 1.0) // 放大一点
                            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: likePop)
                            .symbolEffect(.bounce, value: likedByMe)
                        Text("\(likeCount)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)

            // 内联评论输入
            if showComposer {
                HStack(spacing: 8) {
                    TextField("写评论…", text: $commentText, axis: .vertical)
                        .textInputAutocapitalization(.none)
                        .disableAutocorrection(true)
                        .lineLimit(1...4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    Button {
                        guard !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        let text = commentText
                        commentText = ""
                        sending = true
                        onAddComment?(post, text)
                        commentCount += 1   // 乐观更新
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { sending = false }
                    } label: {
                        if sending { ProgressView().scaleEffect(0.8) }
                        else { Text("发送").bold() }
                    }
                    .disabled(sending)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

        }
        .onAppear(perform: onAppearAtEnd)
        .contentShape(Rectangle())
        .onTapGesture { onOpenDetail?() }

    }
}

private struct ImageViewer: View {
    let urls: [URL]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var bgOpacity: Double = 1.0

    init(urls: [URL], startIndex: Int) {
        self.urls = urls
        self.startIndex = startIndex
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(bgOpacity).ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(urls.indices, id: \.self) { i in
                    ZoomableRemoteImageOne(
                        url: urls[i],
                        onSingleTap: { dismiss() },
                        onDragUpdate: { progress in
                            bgOpacity = max(0.3, 1.0 - progress*0.7)
                        },
                        onDragEnd: { shouldDismiss in
                            if shouldDismiss { dismiss() }
                            else { withAnimation(.spring()) { bgOpacity = 1.0 } }
                        }
                    )
                    .ignoresSafeArea()
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        }
        .statusBarHidden(true)
    }
}

// UIKit 容器：真正的可缩放视图（保留双击缩放）
private struct ZoomableRemoteImageOne: UIViewRepresentable {
    let url: URL
    var onSingleTap: () -> Void = {}
    var onDragUpdate: (CGFloat) -> Void = { _ in }
    var onDragEnd: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = UIScrollView()
        sv.backgroundColor = .clear
        sv.maximumZoomScale = 4.0
        sv.minimumZoomScale = 1.0
        sv.delegate = context.coordinator
        sv.bouncesZoom = true
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.contentInsetAdjustmentBehavior = .never

        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        iv.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTapped(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        iv.addGestureRecognizer(singleTap)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        sv.addGestureRecognizer(pan)

        sv.addSubview(iv)
        context.coordinator.imageView = iv
        context.coordinator.scrollView = sv
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onDragUpdate = onDragUpdate
        context.coordinator.onDragEnd = onDragEnd

        context.coordinator.load(url: url)
        return sv
    }

    func updateUIView(_ sv: UIScrollView, context: Context) {
        context.coordinator.updateMinZoomScaleForSize(sv.bounds.size)
        context.coordinator.centerImage()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        private var imageSize: CGSize = .zero

        var onSingleTap: () -> Void = {}
        var onDragUpdate: (CGFloat) -> Void = { _ in }
        var onDragEnd: (Bool) -> Void = { _ in }

        private var initialCenter: CGPoint = .zero
        private var isDraggingToDismiss = false
        
        // 在 ZoomableRemoteImageOne.Coordinator 里替换 load(url:)
        func load(url: URL) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data, var img = UIImage(data: data) else { return }

                // ✅ 关键：把 EXIF 方向烤掉，得到 .up 的位图
                img = img.normalizedOrientation()

                DispatchQueue.main.async {
                    self.imageSize = img.size
                    self.imageView?.image = img
                    self.imageView?.frame = CGRect(origin: .zero, size: img.size)
                    self.scrollView?.contentSize = img.size
                    if let sv = self.scrollView {
                        self.updateMinZoomScaleForSize(sv.bounds.size)
                        sv.zoomScale = sv.minimumZoomScale
                        self.centerImage()
                    }
                }
            }.resume()
        }


/*
        func load(url: URL) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self.imageSize = img.size
                    self.imageView?.image = img
                    self.imageView?.frame = CGRect(origin: .zero, size: img.size)
                    self.scrollView?.contentSize = img.size
                    if let sv = self.scrollView {
                        self.updateMinZoomScaleForSize(sv.bounds.size)
                        sv.zoomScale = sv.minimumZoomScale
                        self.centerImage()
                    }
                }
            }.resume()
        }
*/
        func updateMinZoomScaleForSize(_ size: CGSize) {
            guard imageSize.width > 0, imageSize.height > 0, let sv = scrollView else { return }
            let widthScale  = size.width  / imageSize.width
            let heightScale = size.height / imageSize.height
            let minScale = min(widthScale, heightScale)
            sv.minimumZoomScale = minScale
            if sv.zoomScale < minScale { sv.zoomScale = minScale }
        }

        func centerImage() {
            guard let sv = scrollView, let iv = imageView else { return }
            let offsetX = max((sv.bounds.size.width  - sv.contentSize.width)  * 0.5, 0)
            let offsetY = max((sv.bounds.size.height - sv.contentSize.height) * 0.5, 0)
            iv.center = CGPoint(x: sv.contentSize.width * 0.5 + offsetX,
                                y: sv.contentSize.height * 0.5 + offsetY)
        }

        @objc func doubleTapped(_ gr: UITapGestureRecognizer) {
            guard let sv = scrollView else { return }
            let pointInView = gr.location(in: imageView)
            let newScale: CGFloat = abs(sv.zoomScale - sv.minimumZoomScale) < 0.01
                ? min(sv.maximumZoomScale, sv.minimumZoomScale * 2.0)
                : sv.minimumZoomScale

            let w = sv.bounds.width / newScale
            let h = sv.bounds.height / newScale
            let x = pointInView.x - (w * 0.5)
            let y = pointInView.y - (h * 0.5)
            let rect = CGRect(x: x, y: y, width: w, height: h)
            sv.zoom(to: rect, animated: true)
        }

        @objc func singleTapped(_ gr: UITapGestureRecognizer) {
            guard let sv = scrollView else { return }
            if abs(sv.zoomScale - sv.minimumZoomScale) < 0.01 {
                onSingleTap()
            }
        }

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard let sv = scrollView, abs(sv.zoomScale - sv.minimumZoomScale) < 0.01,
                  let iv = imageView else { return }

            let translation = gr.translation(in: sv)
            let velocity = gr.velocity(in: sv)

            switch gr.state {
            case .began:
                initialCenter = iv.center
                isDraggingToDismiss = abs(translation.y) > abs(translation.x)
            case .changed:
                guard isDraggingToDismiss else { return }
                let ty = max(translation.y, 0)
                iv.center = CGPoint(x: initialCenter.x, y: initialCenter.y + ty)
                let progress = min(1.0, ty / 300.0)
                onDragUpdate(progress)
            case .ended, .cancelled, .failed:
                guard isDraggingToDismiss else { return }
                let ty = max(translation.y, 0)
                let shouldDismiss = (ty > 140) || (velocity.y > 900)
                if shouldDismiss {
                    onDragEnd(true)
                } else {
                    UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                        iv.center = self.initialCenter
                    }
                    onDragEnd(false)
                }
                isDraggingToDismiss = false
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
        func scrollViewDidLayoutSubviews(_ scrollView: UIScrollView) {
            updateMinZoomScaleForSize(scrollView.bounds.size)
            centerImage()
        }
    }
}

// 胶囊组件

private struct ResortTagCapsule: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                Capsule()
                    .stroke(.black.opacity(0.06), lineWidth: 1 / UIScreen.main.scale)
            )
    }
}

// 骨架行

private struct RowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Circle().fill(Color(.tertiarySystemFill)).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Rectangle().fill(Color(.tertiarySystemFill)).frame(width: 120, height: 12)
                    Rectangle().fill(Color(.tertiarySystemFill)).frame(width: 80, height: 10)
                }
                Spacer()
            }
            Rectangle().fill(Color(.tertiarySystemFill)).frame(height: 12).cornerRadius(3)
            Rectangle().fill(Color(.tertiarySystemFill)).frame(height: 12).cornerRadius(3).opacity(0.9)
            Rectangle().fill(Color(.tertiarySystemFill)).frame(height: 200).cornerRadius(10)
        }
        .padding(.vertical, 12)
        .redacted(reason: .placeholder)
    }
}

// MARK: - Search Field（支持焦点绑定）

private struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "搜索"
    var onSubmit: () -> Void = {}
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.none)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .focused(isFocused)
                .onSubmit { onSubmit() }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.black.opacity(0.06), lineWidth: 1 / UIScreen.main.scale)
        )
    }
}

// MARK: - 简单模型（本文件用到）

struct ResortRef: Hashable, Identifiable {
    var id: Int
    var name: String
}

// === 详情页：可根据需要接入评论流（此处增配了点赞/评论入口） ===
struct ResortsPostDetailView: View {
    let post: ResortPost
    var onToggleLike: ((ResortPost, Bool) -> Void)?
    var onAddComment: ((ResortPost, String) -> Void)?

    // 点赞/计数的本地状态
    @State private var likedByMe: Bool
    @State private var likeCount: Int
    @State private var commentCount: Int

    // 评论列表 VM（用当前 post.id 初始化）
    @StateObject private var commentsVM: CommentsVM

    // 评论输入
    @State private var showComposer = false
    @State private var commentText = ""
    @State private var sending = false

    // 查看全部评论
    @State private var showAllComments = false

    // 图片查看器（沿用你现有的 SKPhotoBrowserPresenter）
    @State private var showDetailViewer = false
    @State private var detailViewerIndex = 0

    init(post: ResortPost,
         onToggleLike: ((ResortPost, Bool) -> Void)? = nil,
         onAddComment: ((ResortPost, String) -> Void)? = nil) {
        self.post = post
        self.onToggleLike = onToggleLike
        self.onAddComment = onAddComment
        _likedByMe = State(initialValue: post.likedByMe)
        _likeCount  = State(initialValue: post.likeCount)
        _commentCount = State(initialValue: post.commentCount)
        _commentsVM = StateObject(wrappedValue: CommentsVM(postId: post.id))
        
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // 顶部：作者 + 时间
                HStack(spacing: 10) {
                    if let url = post.author.avatarURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable()
                            default: Circle().fill(Color(.tertiarySystemFill))
                            }
                        }
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                    } else {
                        Circle().fill(Color(.tertiarySystemFill))
                            .frame(width: 42, height: 42)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.author.name).font(.subheadline.weight(.semibold))
                        Text(post.timeText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // 图片：与列表一致的九宫格
                if !post.mediaURLs.isEmpty {
                    FeedMediaViewKF(urls: post.mediaURLs) { tapped in
                        detailViewerIndex = tapped
                        showDetailViewer = true
                    }
                }

                // 标题/正文（详情展示完整）
                VStack(alignment: .leading, spacing: 10) {
                    if let t = post.title, !t.isEmpty {
                        Text(t)
                            .font(.title3.bold())
                    }
                    if let text = post.text, !text.isEmpty {
                        Text(text)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .lineSpacing(5)          // 详情页再松一点
                    }
                }

                .padding(.horizontal, 20)

                // —— 胶囊 + 点赞/评论 在一行（按钮在右）——
                HStack(spacing: 12) {
                    ResortTagCapsule(name: post.resort.name)

                    Spacer()

                    HStack(spacing: 24) {
                        Button {
                            let toLiked = !likedByMe
                            likedByMe = toLiked
                            likeCount += toLiked ? 1 : -1
                            onToggleLike?(post, toLiked)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: likedByMe ? "heart.fill" : "heart")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(likedByMe ? .red : .secondary)
                                    .symbolEffect(.bounce, value: likedByMe) // iOS 17+
                                Text("\(likeCount)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.spring) { showComposer.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "message")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text("\(commentCount)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Divider().padding(.horizontal, 20)

                // 评论输入
                if showComposer {
                    HStack(spacing: 8) {
                        TextField("写评论…", text: $commentText, axis: .vertical)
                            .textInputAutocapitalization(.none)
                            .disableAutocorrection(true)
                            .lineLimit(1...4)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))

                        Button {
                            let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty, !sending else { return }
                            sending = true
                            commentText = ""
                            // 先乐观 +1
                            commentCount += 1
                            onAddComment?(post, text)
                            Task {
                                // 立即刷新详情内的评论列表
                                await commentsVM.loadInitial()
                                sending = false
                            }
                        } label: {
                            if sending { ProgressView().scaleEffect(0.8) }
                            else { Text("发送").bold() }
                        }
                        .disabled(sending)
                    }
                    .padding(.horizontal, 20)
                }

                // 详情页顶部内容不动……（头像、时间、正文、图片、胶囊、右侧操作栏）

                ThreadedCommentsSection(postId: post.id)


            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAllComments) {
            NavigationStack { CommentsListView(postId: post.id) }
        }
        .background(
            SKPhotoBrowserPresenter(
                isPresented: $showDetailViewer,
                urls: post.mediaURLs,
                startIndex: detailViewerIndex
            )
        )
        .background(Color(.systemBackground))
    }
}





// ======== FeedMediaViewKF（保持你原有版本） ========

struct FeedMediaViewKF: View {
    let urls: [URL]
    var corner: CGFloat = 12
    var gap: CGFloat = 6
    var sidePadding: CGFloat = 20
    var maxRowHeight: CGFloat = 300
    var onTap: (Int) -> Void = { _ in }

    private var containerW: CGFloat { UIScreen.main.bounds.width - sidePadding * 2 }

    var body: some View {
        Group {
            switch urls.count {
            case 1: single(urls[0])
            case 2: two(urls)
            case 3: three(urls)
            default: fourPlus(urls)
            }
        }
        .padding(.horizontal, sidePadding)
    }

    private func single(_ url: URL) -> some View {
        let rowH = min(maxRowHeight, containerW * 0.75)
        return gridCell(url, width: containerW, height: rowH, index: 0)
    }
    private func two(_ urls: [URL]) -> some View {
        let rowH = min(maxRowHeight, containerW * 0.56)
        return HStack(spacing: gap) {
            gridCell(urls[0], width: (containerW - gap)/2, height: rowH, index: 0)
            gridCell(urls[1], width: (containerW - gap)/2, height: rowH, index: 1)
        }
    }
    private func three(_ urls: [URL]) -> some View {
        let rowH = min(maxRowHeight, containerW * 0.56)
        return HStack(spacing: gap) {
            gridCell(urls[0], width: (containerW - gap) * 0.6, height: rowH, index: 0)
            VStack(spacing: gap) {
                gridCell(urls[1], width: (containerW - gap) * 0.4, height: (rowH - gap)/2, index: 1)
                gridCell(urls[2], width: (containerW - gap) * 0.4, height: (rowH - gap)/2, index: 2)
            }
        }
    }
    private func fourPlus(_ urls: [URL]) -> some View {
        let cellW = (containerW - gap)/2
        let cellH = min(maxRowHeight/2, cellW)
        let shown = Array(urls.prefix(4))
        let extra = urls.count - shown.count

        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                gridCell(shown[0], width: cellW, height: cellH, index: 0)
                gridCell(shown[1], width: cellW, height: cellH, index: 1)
            }
            HStack(spacing: gap) {
                gridCell(shown[2], width: cellW, height: cellH, index: 2)
                ZStack {
                    gridCell(shown[3], width: cellW, height: cellH, index: 3)
                    if extra > 0 {
                        Color.black.opacity(0.28)
                            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                        Text("+\(extra)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func gridCell(_ url: URL, width: CGFloat, height: CGFloat, index: Int) -> some View {
        KFImage(url)
            .placeholder {
                Rectangle().fill(Color.black.opacity(0.06))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
            }
            .setProcessor(DownsamplingImageProcessor(size: .init(width: 1000, height: 1000)))
            .cacheOriginalImage()
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { onTap(index) }
    }
}

// ======== SKPhotoBrowser Presenter（保持你原有版本） ========

public struct SKPhotoBrowserPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let urls: [URL]
    let startIndex: Int

    public func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.isOpaque = false
        host.view.backgroundColor = .clear      // ✅ 默认透明
        return host
    }

    public func updateUIViewController(_ host: UIViewController, context: Context) {
        if isPresented, context.coordinator.presented == nil {
            SKPhotoBrowserOptions.displayCounterLabel = false
            SKPhotoBrowserOptions.displayBackAndForwardButton = false
            SKPhotoBrowserOptions.displayAction = false
            SKPhotoBrowserOptions.displayHorizontalScrollIndicator = false
            SKPhotoBrowserOptions.displayVerticalScrollIndicator = false
            SKPhotoBrowserOptions.enableSingleTapDismiss = false
            SKPhotoBrowserOptions.disableVerticalSwipe = false
            SKPhotoBrowserOptions.enableZoomBlackArea = true
            SKPhotoBrowserOptions.backgroundColor = .black

            // ✅ 使用缓存构建 photos
            let photos = makePhotos(from: urls)

            let browser = SKPhotoBrowser(photos: photos)
            browser.initializePageIndex(startIndex)
            browser.view.backgroundColor = .black
            browser.modalPresentationCapturesStatusBarAppearance = true
            browser.modalPresentationStyle = .overFullScreen
            browser.modalTransitionStyle = .crossDissolve

            browser.delegate = context.coordinator

            host.view.backgroundColor = .clear
            host.present(browser, animated: true)
            context.coordinator.presented = browser
        }
        else if !isPresented, let presented = context.coordinator.presented {
            presented.dismiss(animated: true) {
                context.coordinator.presented = nil
                host.view.backgroundColor = .clear
            }
        }
    }

    private func makePhotos(from urls: [URL]) -> [SKPhotoProtocol] {
        let cache = ImageCache.default

        return urls.map { url in
            let key = url.absoluteString

            // 优先用 Kingfisher 内存缓存里的图
            if let cached = cache.retrieveImageInMemoryCache(forKey: key) {
                // ✅ 把 EXIF 方向烤掉
                let fixed = cached.normalizedOrientation()

                let photo = SKPhoto.photoWithImage(fixed)
                photo.shouldCachePhotoURLImage = false   // 不用它再缓存 URL 图了
                return photo
            } else {
                // 没有缓存时退回 URL 模式
                let photo = SKPhoto.photoWithImageURL(key)
                photo.shouldCachePhotoURLImage = true
                return photo
            }
        }
    }




    public func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    final public class Coordinator: NSObject, SKPhotoBrowserDelegate {
        var isPresented: Binding<Bool>
        weak var presented: UIViewController?
        init(isPresented: Binding<Bool>) { self.isPresented = isPresented }

        public func willDismissAtPageIndex(_ index: Int) {
            isPresented.wrappedValue = false
        }
        public func didDismissAtPageIndex(_ index: Int) {
            isPresented.wrappedValue = false
        }
    }
}


// MARK: - 模型（扩展：加入 like/comment/likedByMe/authorId）

struct ResortPost: Identifiable, Hashable {
    let id: UUID
    var author: Author
    var resort: ResortRef
    var title: String?
    var text: String?
    var images: [URL]
    var createdAt: Date
    var rating: Int

    // ✅ 新增
    var userId: UUID
    var likeCount: Int
    var commentCount: Int
    var likedByMe: Bool
    var authorId: UUID? = nil

    var canDelete: Bool = false

    var timeText: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: createdAt, relativeTo: Date())
    }
    var mediaURLs: [URL] { images }
}

struct Author: Hashable {
    var name: String
    var avatarURL: URL?
}

import UIKit

extension UIImage {
    /// 把带 EXIF 方向的图片渲染为 orientation = .up 的位图
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }

        // 左/右方向需要交换宽高
        let needsSwapWH: Bool = {
            switch imageOrientation {
            case .left, .leftMirrored, .right, .rightMirrored: return true
            default: return false
            }
        }()

        let outSize = needsSwapWH ? CGSize(width: size.height, height: size.width) : size

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale   // 保留原图 scale，防止发虚
        // sRGB 即可；不特殊处理 colorSpace

        let rendered = UIGraphicsImageRenderer(size: outSize, format: format).image { _ in
            // 直接 draw 会按 EXIF 正确渲染到 outSize 中，最终得到 .up
            self.draw(in: CGRect(origin: .zero, size: outSize))
        }
        return rendered
    }
}

@MainActor
final class MyResortPostsVM: ObservableObject {
    @Published var items: [ResortPost] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let c = DatabaseManager.shared.client
            guard let u = try? await c.auth.user() else {
                items = []
                error = "请先登录"
                return
            }

            struct Row: Decodable {
                let id: UUID
                let created_at: Date
                let title: String?
                let body: String?
                let rating: Int?
                let resort_id: Int?
                let resort_name: String?
                let user_id: UUID?
                let author_id: UUID?
                let author_name: String?
                let author_avatar_url: String?
                let media_urls: [String]?
                let like_count: Int?
                let comment_count: Int?
                let liked_by_me: Bool?
            }

            // 只取当前用户的帖子
            let rows: [Row] = try await c
                .from("resorts_post_feed")
                .select()
                .eq("author_id", value: u.id)      // 只看自己的
                .order("created_at", ascending: false)
                .limit(80)
                .execute()
                .value

            items = rows.compactMap { r in
                let ownerId = r.user_id ?? r.author_id ?? u.id
                return ResortPost(
                    id: r.id,
                    author: .init(
                        name: r.author_name ?? "我",
                        avatarURL: URL(string: r.author_avatar_url ?? "")
                    ),
                    resort: .init(
                        id: r.resort_id ?? 0,
                        name: r.resort_name ?? "未知雪场"
                    ),
                    title: r.title,
                    text: r.body,
                    images: (r.media_urls ?? []).compactMap { URL(string: $0) },
                    createdAt: r.created_at,
                    rating: r.rating ?? 0,
                    userId: ownerId,
                    likeCount: r.like_count ?? 0,
                    commentCount: r.comment_count ?? 0,
                    likedByMe: r.liked_by_me ?? false,
                    authorId: ownerId,
                    canDelete: true      // 我的帖子全部允许删除
                )
            }

        } catch let err {
            isLoading = false
            self.error = (err as NSError).localizedDescription
        }
    }

    func delete(_ post: ResortPost) async {
        guard let idx = items.firstIndex(where: { $0.id == post.id }) else { return }
        let backup = items[idx]
        items.remove(at: idx)

        do {
            try await DatabaseManager.shared.client
                .from("resorts_post")
                .delete()
                .eq("id", value: post.id)
                .execute()
        } catch {
            items.insert(backup, at: idx)
            self.error = (error as NSError).localizedDescription
        }
    }
}

struct MyResortPostsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = MyResortPostsVM()

    var onSelectPost: (ResortPost) -> Void

    var body: some View {
        List {
            if vm.isLoading && vm.items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if let err = vm.error {
                VStack(spacing: 8) {
                    Text("加载失败").font(.headline)
                    Text(err)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await vm.load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
                .listRowSeparator(.hidden)
            } else if vm.items.isEmpty {
                Text("你还没有在雪圈发过帖子")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .listRowSeparator(.hidden)
            } else {
                // ✅ 小提示：向左滑动可删除自己的帖子（仿顺风车板块）
                HStack(spacing: 6) {
                    
                    Text("提示：向左滑动可以删除自己的帖子")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)

                ForEach(vm.items) { post in
                    MyResortPostRow(
                        post: post,
                        onOpenDetail: {
                            onSelectPost(post)
                            dismiss()
                        },
                        onDelete: {
                            Task { await vm.delete(post) }
                        }
                    )
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("我的帖子")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") { dismiss() }
            }
        }
        .task { await vm.load() }
        .alert("出错了", isPresented: Binding(
            get: { vm.error != nil },
            set: { _ in vm.error = nil }
        )) {
            Button("好的", role: .cancel) { }
        } message: {
            Text(vm.error ?? "")
        }
    }
}

// 单条我的帖子行
private struct MyResortPostRow: View {
    let post: ResortPost
    var onOpenDetail: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ResortTagCapsule(name: post.resort.name)
                Spacer()
                Text(post.timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let t = post.title, !t.isEmpty {
                Text(t)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            if let text = post.text, !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 16) {
                Label("\(post.likeCount)", systemImage: "heart")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(post.commentCount)", systemImage: "message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("查看") { onOpenDetail() }
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .onTapGesture { onOpenDetail() }
        // ✅ 这里改成：滑动后直接删除；不再弹第二个“确认删除”弹窗
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()          // 直接调用父视图的删除逻辑
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}




/*
 
 import SwiftUI
 import Kingfisher
 import Supabase
 import SKPhotoBrowser

 // MARK: - Page

 struct ResortsCommunityView: View {
     @StateObject private var vm = FeedVM()
     @State private var query: String = ""
     @State private var path: NavigationPath = NavigationPath()
     
     @State private var showImageViewer = false
     @State private var viewerIndex = 0
     @State private var viewerURLs: [URL] = []

     // 雪场匹配
     @State private var resortMatches: [ResortRef] = []
     @State private var resortSearching = false
     @State private var resortSearchTask: Task<Void, Never>? = nil

     // 选中的雪场（顶部横卡展示）
     @State private var selectedResort: ResortRef? = nil

     @State private var showingComposer = false
     @State private var showErrorAlert = false

     @FocusState private var searchFocused: Bool

     // 关键词过滤
     private var filteredByQuery: [ResortPost] {
         let src = vm.items
         let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !q.isEmpty else { return src }
         return src.filter {
             ($0.title?.localizedCaseInsensitiveContains(q) ?? false) ||
             ($0.text?.localizedCaseInsensitiveContains(q) ?? false) ||
             $0.author.name.localizedCaseInsensitiveContains(q) ||
             $0.resort.name.localizedCaseInsensitiveContains(q)
         }
     }

     var body: some View {
         NavigationStack(path: $path) {
             ScrollView {
                 VStack(spacing: 0) {

                     // 标题 + 搜索
                     header

                     // 搜索时：展示匹配雪场 chips（未选中时显示）
                     if selectedResort == nil,
                        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                         resortMatchesBlock
                     }

                     // 已选中：顶部横向小卡片
                     if let r = selectedResort {
                         ResortHeaderCard(
                             ref: r,
                             onClear: {
                                 selectedResort = nil
                                 Task { await vm.setResortFilter(nil) }
                             },
                             onOpenDetail: { path.append(r.id) } // 直接压入 Int
                         )
                         .padding(.horizontal, 20)
                         .padding(.top, 12)
                         .padding(.bottom, 8)
                     }

                     // 帖子列表
                     contentList
                 }
                 .background(Color(.systemBackground))
                 .contentShape(Rectangle())
                 .onTapGesture { searchFocused = false } // 点击空白收起键盘
             }
             .background(Color(.systemBackground))
             .navigationTitle("雪场社区")
             .navigationBarTitleDisplayMode(.inline)
             .toolbar { composeToolbar }
             .sheet(isPresented: $showingComposer) { composeSheet }
             .alert("出错了", isPresented: $showErrorAlert, presenting: vm.lastErrorMessage) { _ in
                 Button("好的", role: .cancel) { vm.lastErrorMessage = nil }
             } message: { Text($0) }
             .scrollDismissesKeyboard(.interactively)
             .simultaneousGesture(DragGesture().onChanged { _ in searchFocused = false })

             // 按类型导航，降低类型推断复杂度
             .navigationDestination(for: Int.self) { id in
                 ChartsOfSnowView(resortId: id)
             }
             .navigationDestination(for: ResortPost.self) { post in
                 ResortsPostDetailView(post: post)
             }
             .background(
                             SKPhotoBrowserPresenter(
                                 isPresented: $showImageViewer,
                                 urls: viewerURLs,
                                 startIndex: viewerIndex
                             )
                         )
         }
         .task { await vm.loadInitialIfNeeded() }
         .onChange(of: vm.lastErrorMessage) { _, new in showErrorAlert = (new != nil) }
         .onChange(of: query) { _, newValue in handleQueryChange(newValue) }
     }

     // MARK: - Header

     private var header: some View {
         VStack(alignment: .leading, spacing: 10) {
             Text("雪场社区")
                 .font(.system(size: 28, weight: .bold))
                 .foregroundStyle(.primary)

             // 搜索
             SearchField(text: $query,
                         placeholder: "搜索雪场或帖子",
                         isFocused: $searchFocused)
         }
         .padding(.horizontal, 20)
         .padding(.top, 12)
         .padding(.bottom, 8)
         .background(Color(.systemBackground))
     }

     // MARK: - 雪场匹配 & 选择

     private var resortMatchesBlock: some View {
         VStack(alignment: .leading, spacing: 10) {
             HStack(spacing: 8) {
                 Text("匹配雪场").font(.headline)
                 if resortSearching { ProgressView().scaleEffect(0.8) }
                 Spacer()
             }

             ScrollView(.horizontal, showsIndicators: false) {
                 HStack(spacing: 10) {
                     ForEach(resortMatches, id: \.id) { r in
                         Button {
                             // 选中雪场 → 顶部横卡 + 刷新筛选
                             selectedResort = r
                             query = ""
                             Task { await vm.setResortFilter(r.id) }

                             // 立刻导航到详情（传 Int id）
                             searchFocused = false
                             path.append(r.id)
                         } label: {
                             HStack(spacing: 8) {
                                 Text(r.name)
                                     .font(.subheadline.weight(.semibold))
                             }
                             .padding(.horizontal, 12).padding(.vertical, 8)
                             .background(
                                 RoundedRectangle(cornerRadius: 12, style: .continuous)
                                     .fill(Color(.systemBackground))
                             )
                             .overlay(
                                 RoundedRectangle(cornerRadius: 12, style: .continuous)
                                     .stroke(.black.opacity(0.06), lineWidth: 1 / UIScreen.main.scale)
                             )
                             .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                         }
                         .buttonStyle(.plain)
                     }
                 }
                 .padding(.vertical, 2)
             }
         }
         .padding(.horizontal, 20)
         .padding(.bottom, 8)
     }

     // MARK: - 帖子列表

     @ViewBuilder
     private var contentList: some View {
         if vm.isLoadingInitial {
             VStack(spacing: 16) {
                 ForEach(0..<5, id: \.self) { _ in RowSkeleton().padding(.horizontal, 20) }
             }
             .padding(.top, 12)
         } else if let err = vm.initialError {
             VStack(spacing: 10) {
                 Text("加载失败").font(.headline)
                 Text(err).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                 Button {
                     Task { await vm.refresh() }
                 } label: {
                     Text("重试").bold().padding(.horizontal, 16).padding(.vertical, 10)
                 }
                 .buttonStyle(.borderedProminent)
             }
             .frame(maxWidth: .infinity)
             .padding(.vertical, 40)
             .padding(.horizontal, 20)
         } else if filteredByQuery.isEmpty {
             VStack(spacing: 6) {
                 Text("暂无帖子").font(.headline)
                 Text(selectedResort == nil ? "可先搜索并选择一个雪场" : "这个雪场还没有帖子，去发布一条吧！")
                     .font(.subheadline).foregroundStyle(.secondary)
             }
             .frame(maxWidth: .infinity)
             .padding(.vertical, 40)
         } else {
             LazyVStack(spacing: 0) {
                 ForEach(filteredByQuery) { (p: ResortPost) in
                     PostRow(
                         post: p,
                         onAppearAtEnd: {
                             if p.id == filteredByQuery.last?.id {
                                 Task { await vm.loadMoreIfNeeded() }
                             }
                         },
                         onDelete: { Task { await vm.delete(p) } },
                         onReport: { Task { await vm.report(p) } },
                         onOpenDetail: { path.append(p) },
                         onTapImageAt: { tapped in         // ✅ 统一控制器入口
                             viewerURLs = p.mediaURLs
                             viewerIndex = tapped
                             showImageViewer = true
                         }
                     )
                     Divider().padding(.leading, 20)
                 }


                 if vm.isPaginating {
                     HStack { Spacer(); ProgressView().padding(.vertical, 16); Spacer() }
                 } else if vm.reachedEnd && !vm.items.isEmpty {
                     Text("没有更多了")
                         .font(.footnote)
                         .foregroundStyle(.secondary)
                         .padding(.vertical, 12)
                 }
             }
             .padding(.top, 4)
         }
     }

     // MARK: - Toolbar & Sheet

     private var composeToolbar: some ToolbarContent {
         ToolbarItem(placement: .topBarTrailing) {
             Button { showingComposer = true } label: {
                 Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
             }
             .accessibilityLabel("发布雪场评价")
         }
     }

     @ViewBuilder
     private var composeSheet: some View {
         ResortsPostComposerView { didPost in
             if didPost { Task { await vm.refresh() } }
         }
     }

     // MARK: - 搜索雪场（防抖）

     private func handleQueryChange(_ newValue: String) {
         resortSearchTask?.cancel()
         let text = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !text.isEmpty else {
             resortMatches = []
             resortSearching = false
             return
         }
         guard selectedResort == nil else { return }

         resortSearching = true
         resortSearchTask = Task { @MainActor in
             try? await Task.sleep(nanoseconds: 280_000_000)
             await searchResorts(keyword: text)
         }
     }

     private func searchResorts(keyword: String) async {
         do {
             struct Row: Decodable { let id: Int; let name_resort: String }
             let rows: [Row] = try await DatabaseManager.shared.client
                 .from("Resorts_data")
                 .select("id,name_resort")
                 .ilike("name_resort", pattern: "%\(keyword)%")
                 .limit(10)
                 .execute()
                 .value
             resortMatches = rows.map { .init(id: $0.id, name: $0.name_resort) }
         } catch {
             resortMatches = []
         }
         resortSearching = false
     }
 }

 // MARK: - 顶部小雪场卡片（横向）

 private struct ResortHeaderCard: View {
     let ref: ResortRef
     var onClear: () -> Void
     var onOpenDetail: () -> Void

     var body: some View {
         HStack(spacing: 12) {
             VStack(alignment: .leading, spacing: 2) {
                 Text(ref.name)
                     .font(.headline)
                     .foregroundStyle(.primary)

                 Button(action: onOpenDetail) {
                     HStack(spacing: 4) {
                         Text("查看雪场详情")
                             .font(.footnote.weight(.semibold))
                             .foregroundStyle(.primary)
                         Image(systemName: "chevron.right")
                             .font(.footnote.weight(.semibold))
                             .foregroundStyle(.secondary)
                     }
                 }
                 .buttonStyle(.plain)
             }
             Spacer()
             Button(action: onClear) {
                 Image(systemName: "xmark.circle.fill")
                     .font(.title3)
                     .foregroundStyle(.secondary)
             }
         }
         .padding(12)
         .background(
             RoundedRectangle(cornerRadius: 14, style: .continuous)
                 .fill(Color(.systemBackground))
         )
         .overlay(
             RoundedRectangle(cornerRadius: 14, style: .continuous)
                 .stroke(.black.opacity(0.06), lineWidth: 1 / UIScreen.main.scale)
         )
         .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
     }
 }

 // MARK: - 适配原图比例的远程图（列表用）


 // MARK: - 首页列表图片（按比例分档渲染）
 private struct FeedImage: View {
     let url: URL
     private let corner: CGFloat = 12
     private let containerW: CGFloat = UIScreen.main.bounds.width - 40 // 列表里左右各20的内边距
     private let placeholderH: CGFloat = 240
     private let normalMaxH: CGFloat = 420
     private let tallMaxH: CGFloat = 480

     @State private var aspect: CGFloat? = nil // 宽/高

     // 计算展示高度与模式
     private func layout(for a: CGFloat?) -> (height: CGFloat, fill: Bool) {
         guard let a, a > 0 else {
             return (placeholderH, true) // 未知先给稳定占位，fill 让占位更好看
         }
         if a < 0.8 {
             // 超窄竖 -> 适度裁切 + 上限高度保护
             return (min(containerW / 0.8, tallMaxH), true)
         } else if a > 1.9 {
             // 超宽横 -> 防丝带，固定高度
             return (220, true)
         } else {
             // 常规 -> 等比展示，设上限
             return (min(containerW / a, normalMaxH), false)
         }
     }

     var body: some View {
         let (h, useFill) = layout(for: aspect)

         KFImage(url)
             .onSuccess { r in
                 let sz = r.image.size
                 if sz.width > 0, sz.height > 0 {
                     aspect = sz.width / sz.height
                 }
             }
             .placeholder {
                 Rectangle()
                     .fill(Color.black.opacity(0.06))
                     .overlay(
                         Image(systemName: "photo")
                             .font(.system(size: 22, weight: .semibold))
                             .foregroundStyle(.secondary)
                     )
                     .frame(height: h)
                     .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
             }
             .resizable()
             .modifier(AspectModeModifier(useFill: useFill, aspect: aspect))
             .frame(width: containerW, height: h)
             .clipped()
             .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
             .contentShape(Rectangle())
     }
 }

 // 小工具：根据 useFill 选择 Fill/Fit，不用 GeometryReader，避免 TabView 干扰
 private struct AspectModeModifier: ViewModifier {
     let useFill: Bool
     let aspect: CGFloat?

     func body(content: Content) -> some View {
         if let a = aspect, a > 0, !useFill {
             // 正常档位：等比适配（不会裁切）
             content.aspectRatio(a, contentMode: .fit)
         } else {
             // 需要裁切或比例未知：填充 + 居中裁切
             content.scaledToFill()
         }
     }
 }


 // MARK: - 帖子行（无卡片，简洁列表）

 private struct PostRow: View {
     let post: ResortPost
     var onAppearAtEnd: () -> Void
     var onDelete: (() -> Void)? = nil
     var onReport: (() -> Void)? = nil
     var onOpenDetail: (() -> Void)? = nil
     var onTapImageAt: ((Int) -> Void)? = nil
     @State private var page = 0
     @State private var showDeleteConfirm = false

     

     // 文本显示约束
     private let maxLines = 8           // ✅ 最多 8 行（改成 7 也行）
     private let maxChars = 2000        // ✅ 软字符上限，防极端长文

     var body: some View {
         VStack(alignment: .leading, spacing: 10) {

             // 顶部：作者 + 时间 + 菜单（不变）
             HStack(spacing: 12) {
                 KFImage(post.author.avatarURL)
                     .placeholder { Circle().fill(Color(.tertiarySystemFill)) }
                     .setProcessor(DownsamplingImageProcessor(size: .init(width: 40, height: 40)))
                     .cacheOriginalImage()
                     .resizable().scaledToFill()
                     .frame(width: 40, height: 40)
                     .clipShape(Circle())

                 VStack(alignment: .leading, spacing: 2) {
                     Text(post.author.name).font(.subheadline.weight(.semibold))
                     Text(post.timeText).font(.caption).foregroundStyle(.secondary)
                 }

                 Spacer()

                 Menu {
                     if let onReport { Button("举报") { onReport() } }
                     if onDelete != nil {
                         Button("删除", role: .destructive) { showDeleteConfirm = true }
                     }
                 } label: {
                     Image(systemName: "ellipsis")
                         .foregroundStyle(.secondary)
                         .frame(width: 34, height: 34)
                         .contentShape(Rectangle())
                 }
                 .confirmationDialog("确认删除这条帖子？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                     if let onDelete { Button("删除", role: .destructive) { onDelete() } }
                     Button("取消", role: .cancel) {}
                 }
             }
             .padding(.top, 12)
             .padding(.horizontal, 20)

             // ✅ 卡片主体可点击：点击文字/留白都进详情（图片仍然可点看大图）
             VStack(alignment: .leading, spacing: 8) {

                 if let t = post.title, !t.isEmpty {
                     Text(t)
                         .font(.headline)
                         .foregroundStyle(.primary)
                 }

                 if let text = post.text, !text.isEmpty {
                     let limited = String(text.prefix(maxChars))
                     Text(limited)
                         .font(.body)
                         .foregroundStyle(.primary)
                         .lineLimit(maxLines)
                         .truncationMode(.tail)
                 }
             }
             .padding(.horizontal, 20)
             .contentShape(Rectangle())
             .onTapGesture { onOpenDetail?() }   // ✅ 点击文字/空白 -> 详情

             if !post.mediaURLs.isEmpty {
                 FeedMediaViewKF(urls: post.mediaURLs) { tapped in
                     onTapImageAt?(tapped)   // ← 只抛事件，不在行内展示
                 }
             }



             // 底部胶囊标签（点击胶囊也进入详情，体验更顺畅）
             HStack {
                 ResortTagCapsule(name: post.resort.name)
                     .onTapGesture { onOpenDetail?() }   // ✅
                 Spacer()
             }
             .padding(.horizontal, 20)
             .padding(.bottom, 12)
         }
         
         .onAppear(perform: onAppearAtEnd)
     }
 }


 private struct ImageViewer: View {
     let urls: [URL]
     let startIndex: Int
     @Environment(\.dismiss) private var dismiss
     @State private var index: Int
     @State private var bgOpacity: Double = 1.0  // 下滑时背景渐变

     init(urls: [URL], startIndex: Int) {
         self.urls = urls
         self.startIndex = startIndex
         _index = State(initialValue: startIndex)
     }

     var body: some View {
         ZStack {
             Color.black.opacity(bgOpacity).ignoresSafeArea()

             TabView(selection: $index) {
                 ForEach(urls.indices, id: \.self) { i in
                     ZoomableRemoteImageOne(
                         url: urls[i],
                         onSingleTap: { dismiss() },              // ✅ 单击退出
                         onDragUpdate: { progress in               // 0~1 的进度，越大越透明
                             bgOpacity = max(0.3, 1.0 - progress*0.7)
                         },
                         onDragEnd: { shouldDismiss in
                             if shouldDismiss { dismiss() }
                             else { withAnimation(.spring()) { bgOpacity = 1.0 } }
                         }
                     )
                     .ignoresSafeArea()
                     .tag(i)
                 }
             }
             .tabViewStyle(.page(indexDisplayMode: .automatic))
         }
         .statusBarHidden(true)
     }
 }



 // UIKit 容器：真正的可缩放视图（保留双击缩放）
 private struct ZoomableRemoteImageOne: UIViewRepresentable {
     let url: URL
     var onSingleTap: () -> Void = {}
     var onDragUpdate: (CGFloat) -> Void = { _ in }  // 传 0~1 的进度（用于背景透明度）
     var onDragEnd: (Bool) -> Void = { _ in }        // 是否应当退出

     func makeUIView(context: Context) -> UIScrollView {
         let sv = UIScrollView()
         sv.backgroundColor = .clear
         sv.maximumZoomScale = 4.0
         sv.minimumZoomScale = 1.0
         sv.delegate = context.coordinator
         sv.bouncesZoom = true
         sv.showsHorizontalScrollIndicator = false
         sv.showsVerticalScrollIndicator = false
         sv.contentInsetAdjustmentBehavior = .never

         let iv = UIImageView()
         iv.contentMode = .scaleAspectFit
         iv.isUserInteractionEnabled = true

         // 双击放大/还原
         let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
         doubleTap.numberOfTapsRequired = 2
         iv.addGestureRecognizer(doubleTap)

         // ✅ 单击退出（要求失败于双击）
         let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTapped(_:)))
         singleTap.numberOfTapsRequired = 1
         singleTap.require(toFail: doubleTap)
         iv.addGestureRecognizer(singleTap)

         // ✅ 下滑退出（仅在最小缩放时生效）
         let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
         pan.delegate = context.coordinator
         sv.addGestureRecognizer(pan)

         sv.addSubview(iv)
         context.coordinator.imageView = iv
         context.coordinator.scrollView = sv
         context.coordinator.onSingleTap = onSingleTap
         context.coordinator.onDragUpdate = onDragUpdate
         context.coordinator.onDragEnd = onDragEnd

         context.coordinator.load(url: url)
         return sv
     }

     func updateUIView(_ sv: UIScrollView, context: Context) {
         context.coordinator.updateMinZoomScaleForSize(sv.bounds.size)
         context.coordinator.centerImage()
     }

     func makeCoordinator() -> Coordinator { Coordinator() }

     final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
         weak var imageView: UIImageView?
         weak var scrollView: UIScrollView?
         private var imageSize: CGSize = .zero

         // 回调
         var onSingleTap: () -> Void = {}
         var onDragUpdate: (CGFloat) -> Void = { _ in }
         var onDragEnd: (Bool) -> Void = { _ in }

         // 拖拽状态
         private var initialCenter: CGPoint = .zero
         private var isDraggingToDismiss = false

         func load(url: URL) {
             URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                 guard let self, let data, let img = UIImage(data: data) else { return }
                 DispatchQueue.main.async {
                     self.imageSize = img.size
                     self.imageView?.image = img
                     self.imageView?.frame = CGRect(origin: .zero, size: img.size)
                     self.scrollView?.contentSize = img.size
                     if let sv = self.scrollView {
                         self.updateMinZoomScaleForSize(sv.bounds.size)
                         sv.zoomScale = sv.minimumZoomScale
                         self.centerImage()
                     }
                 }
             }.resume()
         }

         func updateMinZoomScaleForSize(_ size: CGSize) {
             guard imageSize.width > 0, imageSize.height > 0, let sv = scrollView else { return }
             let widthScale  = size.width  / imageSize.width
             let heightScale = size.height / imageSize.height
             let minScale = min(widthScale, heightScale)
             sv.minimumZoomScale = minScale
             if sv.zoomScale < minScale { sv.zoomScale = minScale }
         }

         func centerImage() {
             guard let sv = scrollView, let iv = imageView else { return }
             let offsetX = max((sv.bounds.size.width  - sv.contentSize.width)  * 0.5, 0)
             let offsetY = max((sv.bounds.size.height - sv.contentSize.height) * 0.5, 0)
             iv.center = CGPoint(x: sv.contentSize.width * 0.5 + offsetX,
                                 y: sv.contentSize.height * 0.5 + offsetY)
         }

         // MARK: - Gestures

         @objc func doubleTapped(_ gr: UITapGestureRecognizer) {
             guard let sv = scrollView else { return }
             let pointInView = gr.location(in: imageView)
             let newScale: CGFloat = abs(sv.zoomScale - sv.minimumZoomScale) < 0.01
                 ? min(sv.maximumZoomScale, sv.minimumZoomScale * 2.0)
                 : sv.minimumZoomScale

             let w = sv.bounds.width / newScale
             let h = sv.bounds.height / newScale
             let x = pointInView.x - (w * 0.5)
             let y = pointInView.y - (h * 0.5)
             let rect = CGRect(x: x, y: y, width: w, height: h)
             sv.zoom(to: rect, animated: true)
         }

         @objc func singleTapped(_ gr: UITapGestureRecognizer) {
             guard let sv = scrollView else { return }
             // ✅ 仅在未放大时响应单击退出
             if abs(sv.zoomScale - sv.minimumZoomScale) < 0.01 {
                 onSingleTap()
             }
         }

         // 下滑退出：仅在未放大时生效；竖向拖拽一定距离或速度关闭
         @objc func handlePan(_ gr: UIPanGestureRecognizer) {
             guard let sv = scrollView, abs(sv.zoomScale - sv.minimumZoomScale) < 0.01,
                   let iv = imageView else { return }

             let translation = gr.translation(in: sv)
             let velocity = gr.velocity(in: sv)

             switch gr.state {
             case .began:
                 initialCenter = iv.center
                 isDraggingToDismiss = abs(translation.y) > abs(translation.x) // 竖向意图
             case .changed:
                 guard isDraggingToDismiss else { return }
                 // 只跟随竖向位移
                 let ty = max(translation.y, 0) // 仅向下
                 iv.center = CGPoint(x: initialCenter.x, y: initialCenter.y + ty)
                 // 传递一个 0~1 的进度给 SwiftUI 做背景透明
                 let progress = min(1.0, ty / 300.0)
                 onDragUpdate(progress)
             case .ended, .cancelled, .failed:
                 guard isDraggingToDismiss else { return }
                 let ty = max(translation.y, 0)
                 let shouldDismiss = (ty > 140) || (velocity.y > 900)
                 if shouldDismiss {
                     onDragEnd(true)
                 } else {
                     // 回弹
                     UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                         iv.center = self.initialCenter
                     }
                     onDragEnd(false)
                 }
                 isDraggingToDismiss = false
             default:
                 break
             }
         }

         // 允许与内部滚动/缩放手势并存；只有在最小缩放且竖向滑动时才接管
         func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
             return true
         }

         // MARK: - UIScrollViewDelegate
         func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
         func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
         func scrollViewDidLayoutSubviews(_ scrollView: UIScrollView) {
             updateMinZoomScaleForSize(scrollView.bounds.size)
             centerImage()
         }
     }
 }


 // 胶囊组件

 private struct ResortTagCapsule: View {
     let name: String

     var body: some View {
         Text(name)
             .font(.footnote.weight(.semibold))
             .lineLimit(1)
             .truncationMode(.tail)
             .padding(.horizontal, 12)
             .padding(.vertical, 6)
             .background(
                 Capsule()
                     .fill(Color(.secondarySystemBackground))
             )
             .overlay(
                 Capsule()
                     .stroke(.black.opacity(0.06), lineWidth: 1 / UIScreen.main.scale)
             )
     }
 }

 // 骨架行

 private struct RowSkeleton: View {
     var body: some View {
         VStack(alignment: .leading, spacing: 10) {
             HStack(spacing: 12) {
                 Circle().fill(Color(.tertiarySystemFill)).frame(width: 40, height: 40)
                 VStack(alignment: .leading, spacing: 6) {
                     Rectangle().fill(Color(.tertiarySystemFill)).frame(width: 120, height: 12)
                     Rectangle().fill(Color(.tertiarySystemFill)).frame(width: 80, height: 10)
                 }
                 Spacer()
             }
             Rectangle().fill(Color(.tertiarySystemFill)).frame(height: 12).cornerRadius(3)
             Rectangle().fill(Color(.tertiarySystemFill)).frame(height: 12).cornerRadius(3).opacity(0.9)
             Rectangle().fill(Color(.tertiarySystemFill)).frame(height: 200).cornerRadius(10)
         }
         .padding(.vertical, 12)
         .redacted(reason: .placeholder)
     }
 }

 // MARK: - Search Field（支持焦点绑定）

 private struct SearchField: View {
     @Binding var text: String
     var placeholder: String = "搜索"
     var onSubmit: () -> Void = {}
     var isFocused: FocusState<Bool>.Binding

     var body: some View {
         HStack(spacing: 8) {
             Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
             TextField(placeholder, text: $text)
                 .textInputAutocapitalization(.none)
                 .disableAutocorrection(true)
                 .submitLabel(.search)
                 .focused(isFocused)
                 .onSubmit { onSubmit() }
             if !text.isEmpty {
                 Button { text = "" } label: {
                     Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                 }
                 .buttonStyle(.plain)
             }
         }
         .padding(.horizontal, 12)
         .padding(.vertical, 10)
         .background(
             RoundedRectangle(cornerRadius: 14, style: .continuous)
                 .fill(Color(.secondarySystemBackground))
         )
         .overlay(
             RoundedRectangle(cornerRadius: 14, style: .continuous)
                 .stroke(.black.opacity(0.06), lineWidth: 1 / UIScreen.main.scale)
         )
     }
 }

 // MARK: - 简单模型（本文件用到）

 struct ResortRef: Hashable, Identifiable {
     var id: Int
     var name: String
 }

 struct ResortsPostDetailView: View {
     let post: ResortPost
     @State private var page = 0

     var body: some View {
         ScrollView {
             VStack(alignment: .leading, spacing: 16) {

                 // 顶部：作者 + 时间
                 HStack(spacing: 10) {
                     if let url = post.author.avatarURL {
                         AsyncImage(url: url) { phase in
                             switch phase {
                             case .success(let img): img.resizable()
                             default: Circle().fill(Color(.tertiarySystemFill))
                             }}
                             .scaledToFill()
                             .frame(width: 42, height: 42)
                             .clipShape(Circle())
                     } else {
                         Circle().fill(Color(.tertiarySystemFill))
                             .frame(width: 42, height: 42)
                     }

                     VStack(alignment: .leading, spacing: 2) {
                         Text(post.author.name).font(.subheadline.weight(.semibold))
                         Text(post.timeText).font(.caption).foregroundStyle(.secondary)
                     }
                     Spacer()
                 }
                 .padding(.horizontal, 20)
                 .padding(.top, 12)

                 // 图片（有则轮播）
                 if !post.mediaURLs.isEmpty {
                     TabView(selection: $page) {
                         ForEach(post.mediaURLs.indices, id: \.self) { i in
                             FeedImage(url: post.mediaURLs[i])
                                 .padding(.horizontal, 20)
                                 .tag(i)
                         }
                     }
                     .tabViewStyle(.page(indexDisplayMode: .automatic))
                 }

                 // 标题/正文（详情页展示完整内容）
                 VStack(alignment: .leading, spacing: 10) {
                     if let t = post.title, !t.isEmpty {
                         Text(t).font(.title3.bold())
                     }
                     if let text = post.text, !text.isEmpty {
                         Text(text).font(.body)
                     }
                 }
                 .padding(.horizontal, 20)

                 // 底部胶囊标签
                 HStack {
                     ResortTagCapsule(name: post.resort.name)
                     Spacer()
                 }
                 .padding(.horizontal, 20)

                 Spacer(minLength: 24)
             }
         }
         .navigationBarTitleDisplayMode(.inline)
     }
 }







 struct FeedMediaViewKF: View {
     let urls: [URL]
     var corner: CGFloat = 12
     var gap: CGFloat = 6
     var sidePadding: CGFloat = 20
     var maxRowHeight: CGFloat = 300
     var onTap: (Int) -> Void = { _ in }  // 回调点击索引

     private var containerW: CGFloat {
         UIScreen.main.bounds.width - sidePadding * 2
     }

     var body: some View {
         Group {
             switch urls.count {
             case 1:
                 single(urls[0])
             case 2:
                 two(urls)
             case 3:
                 three(urls)
             default:
                 fourPlus(urls)
             }
         }
         .padding(.horizontal, sidePadding)
     }

     // MARK: - Layouts

     private func single(_ url: URL) -> some View {
         // 单图：按比例会更美，但网格风格里通常统一行高以便视觉稳定
         let rowH = min(maxRowHeight, containerW * 0.75) // 约等于 4:3，可按需调
         return gridCell(url, width: containerW, height: rowH, index: 0)
     }

     private func two(_ urls: [URL]) -> some View {
         let rowH = min(maxRowHeight, containerW * 0.56) // 与 X/Twitter 接近的行高
         return HStack(spacing: gap) {
             gridCell(urls[0], width: (containerW - gap)/2, height: rowH, index: 0)
             gridCell(urls[1], width: (containerW - gap)/2, height: rowH, index: 1)
         }
     }

     private func three(_ urls: [URL]) -> some View {
         let rowH = min(maxRowHeight, containerW * 0.56)
         return HStack(spacing: gap) {
             gridCell(urls[0], width: (containerW - gap) * 0.6, height: rowH, index: 0) // 左大
             VStack(spacing: gap) {
                 gridCell(urls[1], width: (containerW - gap) * 0.4, height: (rowH - gap)/2, index: 1)
                 gridCell(urls[2], width: (containerW - gap) * 0.4, height: (rowH - gap)/2, index: 2)
             }
         }
     }

     private func fourPlus(_ urls: [URL]) -> some View {
         // 只展示前 4 张，多余的用 "+N" 覆盖在第 4 张
         let cellW = (containerW - gap)/2
         let cellH = min(maxRowHeight/2, cellW) // 方形或略矮；视觉稳
         let shown = Array(urls.prefix(4))
         let extra = urls.count - shown.count

         return VStack(spacing: gap) {
             HStack(spacing: gap) {
                 gridCell(shown[0], width: cellW, height: cellH, index: 0)
                 gridCell(shown[1], width: cellW, height: cellH, index: 1)
             }
             HStack(spacing: gap) {
                 gridCell(shown[2], width: cellW, height: cellH, index: 2)
                 ZStack {
                     gridCell(shown[3], width: cellW, height: cellH, index: 3)
                     if extra > 0 {
                         // “+N” 覆盖层
                         Color.black.opacity(0.28)
                             .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                         Text("+\(extra)")
                             .font(.system(size: 22, weight: .bold))
                             .foregroundStyle(.white)
                     }
                 }
             }
         }
     }

     // MARK: - Cell

     @ViewBuilder
     private func gridCell(_ url: URL, width: CGFloat, height: CGFloat, index: Int) -> some View {
         KFImage(url)
             .placeholder {
                 Rectangle().fill(Color.black.opacity(0.06))
                     .overlay(
                         Image(systemName: "photo")
                             .font(.system(size: 18, weight: .semibold))
                             .foregroundStyle(.secondary)
                     )
             }
             .setProcessor(DownsamplingImageProcessor(size: .init(width: 1000, height: 1000)))
             .cacheOriginalImage()
             .resizable()
             .scaledToFill() // 适度裁切以填满格子
             .frame(width: width, height: height)
             .clipped()
             .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
             .contentShape(Rectangle())
             .onTapGesture { onTap(index) }
     }
 }














 /// 通过 UIKit 直接 present/ dismiss SKPhotoBrowser，确保真正铺满屏幕且背景纯黑
 public struct SKPhotoBrowserPresenter: UIViewControllerRepresentable {
     @Binding var isPresented: Bool
     let urls: [URL]
     let startIndex: Int

     public func makeUIViewController(context: Context) -> UIViewController {
         let host = UIViewController()
         host.view.backgroundColor = .clear
         return host
     }

     public func updateUIViewController(_ host: UIViewController, context: Context) {
         if isPresented, host.presentedViewController == nil {
             // 配置选项（关闭 UI、保留手势）
            
             SKPhotoBrowserOptions.displayCounterLabel = false
             SKPhotoBrowserOptions.displayBackAndForwardButton = false
             SKPhotoBrowserOptions.displayAction = false
             SKPhotoBrowserOptions.displayHorizontalScrollIndicator = false
             SKPhotoBrowserOptions.displayVerticalScrollIndicator = false
             SKPhotoBrowserOptions.enableSingleTapDismiss = false
             SKPhotoBrowserOptions.disableVerticalSwipe = false
             SKPhotoBrowserOptions.enableZoomBlackArea = true
             SKPhotoBrowserOptions.backgroundColor = .black

             let photos = urls.map { SKPhoto.photoWithImageURL($0.absoluteString) }
             let browser = SKPhotoBrowser(photos: photos)
             browser.initializePageIndex(startIndex)
             browser.view.backgroundColor = .black
             browser.modalPresentationCapturesStatusBarAppearance = true

             // ✅ 关键：覆盖在当前 VC 之上，杜绝任何底层白色背景透出
             browser.modalPresentationStyle = .overFullScreen

             // 关闭时把绑定复位
             browser.delegate = context.coordinator

             // 把宿主控制器背景也设黑（再兜底）
             host.view.backgroundColor = .black

             host.present(browser, animated: true)
             context.coordinator.presented = browser
         } else if !isPresented, host.presentedViewController != nil {
             host.dismiss(animated: true)
             context.coordinator.presented = nil
         }
     }

     public func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

     final public class Coordinator: NSObject, SKPhotoBrowserDelegate {
         var isPresented: Binding<Bool>
         weak var presented: UIViewController?
         init(isPresented: Binding<Bool>) { self.isPresented = isPresented }

         public func willDismissAtPageIndex(_ index: Int) {
             isPresented.wrappedValue = false
         }
     }
     
     
 }
 
 
 
 */
