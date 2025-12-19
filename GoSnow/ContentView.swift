import SwiftUI
import PopupView
import Supabase

// MARK: - 主 Tab 定义
enum MainTab: Hashable {
    case home, resorts, community

    var icon: String {
        switch self {
        case .home:      return "record.circle.fill"
        case .resorts:   return "map.fill"
        case .community: return "sparkles"
        }
    }

    var title: String {
        switch self {
        case .home:      return "记录"
        case .resorts:   return "雪圈"
        case .community: return "发现"
        }
    }
}

struct ContentView: View {
    @StateObject var userData = UserData()
    let statsStore: StatsStore

    // 欢迎页标记
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false

    // 登录状态
    @ObservedObject private var auth = AuthManager.shared

    // 当前 Tab
    @State private var tab: MainTab = .home

    // Gate
    @State private var showWelcomeGate = false   // 欢迎页（登录后且未看过）
    @State private var showLoginGate   = false   // 登录入口（未登录）

    // ✅ 更新弹窗中心：真实后端拉取
    @StateObject private var updateCenter = UpdateBannerCenter()

    #if DEBUG
    @State private var showUpdateMock = false    // ✅ PopupView 的展示开关（由发现页点击触发）
    #endif

    var body: some View {
        ZStack {
            // 背景渐变（和你原来一致）
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // MARK: - 原生 TabView 作为主导航
            TabView(selection: $tab) {
                NavigationStack {
                    HomeDashboardView(store: statsStore)
                }
                .tabItem {
                    Image(systemName: MainTab.home.icon)
                    Text(MainTab.home.title)
                }
                .tag(MainTab.home)

                NavigationStack {
                    ResortsCommunityView()
                }
                .tabItem {
                    Image(systemName: MainTab.resorts.icon)
                    Text(MainTab.resorts.title)
                }
                .tag(MainTab.resorts)

                NavigationStack {
                    DailySnowView()
                }
                .tabItem {
                    Image(systemName: MainTab.community.icon)
                    Text(MainTab.community.title)
                }
                .tag(MainTab.community)
            }
            .onChange(of: tab) { _, _ in
                let g = UIImpactFeedbackGenerator(style: .light)
                g.prepare()
                g.impactOccurred()
            }

        }
        .environmentObject(userData)
        .preferredColorScheme(.light)

        // MARK: - ✅ 监听“发现页点击触发”的通知 -> 弹出 PopupView（仅 Debug 预览）
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugShowUpdatePopup)) { _ in
            // 避免 Gate 期间弹出
            guard !showLoginGate, !showWelcomeGate else { return }
            showUpdateMock = true
        }
        #endif

        // ✅ Debug 预览：保留你原来的 preview popup，不影响线上逻辑
        #if DEBUG
        .popup(isPresented: $showUpdateMock) {
            UpdateBannerCard(
                bannerImageURL: "https://picsum.photos/900/320",
                title: "新版本已上线",
                message: "本次更新优化了记录稳定性，并提升地图与雪道展示的流畅度。",
                appStoreURL: URL(string: "https://apps.apple.com/app/id1234567890")!,
                onDismiss: { showUpdateMock = false },
                horizontalInset: 0
            )
        } customize: { cfg in
            cfg
                .type(.toast)                              // ✅ 无左右 padding，铺满
                .position(.bottom)
                .appearFrom(.bottomSlide)
                .animation(.interactiveSpring(response: 0.45, dampingFraction: 0.86, blendDuration: 0.25))
                .displayMode(.sheet)                       // ✅ 背景不穿透
                .backgroundColor(.black.opacity(0.35))
                .closeOnTapOutside(true)
                .dragToDismiss(false)
        }
        #endif

        // ✅ 正式：后端拉取后的真实弹窗（active != nil 才弹）
        .popup(
            isPresented: Binding(
                get: { updateCenter.active != nil },
                set: { presented in
                    if !presented { updateCenter.dismiss() }
                }
            )
        ) {
            if let p = updateCenter.active {
                UpdateBannerCard(
                    bannerImageURL: p.bannerImageURL,
                    title: p.title,
                    message: p.message,
                    appStoreURL: p.appStoreURL,
                    onDismiss: { updateCenter.dismiss() },
                    horizontalInset: 0
                )
            }
        } customize: { cfg in
            cfg
                .type(.toast)                              // ✅ 无左右 padding，铺满
                .position(.bottom)
                .appearFrom(.bottomSlide)
                .animation(.interactiveSpring(response: 0.45, dampingFraction: 0.86, blendDuration: 0.25))
                .displayMode(.sheet)                       // ✅ 背景不穿透
                .backgroundColor(.black.opacity(0.35))
                .closeOnTapOutside(true)
                .dragToDismiss(false)
        }

        // MARK: - 欢迎页 Gate（已登录但没看过欢迎）
        .fullScreenCover(isPresented: $showWelcomeGate) {
            WelcomeFlowView()
                .interactiveDismissDisabled(true)
        }

        // MARK: - 登录 Gate（未登录时）
        .fullScreenCover(isPresented: $showLoginGate) {
            WelcomeAuthIntroView()
                .interactiveDismissDisabled(true)
                .onDisappear {
                    Task { await AuthManager.shared.bootstrap() }
                }
        }

        // 冷启动：拉会话 -> 决定先登录还是直接欢迎
        .task {
            await AuthManager.shared.bootstrap()

            if auth.session == nil {
                // 未登录 → 先登录
                showLoginGate = true
            } else if !hasSeenOnboarding {
                // 已登录但没看过欢迎页 → 弹欢迎
                showWelcomeGate = true
            } else {
                // ✅ 已登录且已看过欢迎页 -> 拉取更新公告
                await updateCenter.checkAndPresentFromBackend()
            }
        }

        // 欢迎页状态变化
        .onChange(of: hasSeenOnboarding) { _, seen in
            if seen {
                showWelcomeGate = false
                // ✅ 欢迎页结束后再拉一次（防止首次启动先欢迎页，导致没拉公告）
                Task { await updateCenter.checkAndPresentFromBackend() }
            }
        }

        // 会话变化联动
        .onChange(of: auth.session) { _, session in
            if session == nil {
                // 丢会话 → 去登录
                if !showWelcomeGate {
                    showLoginGate = true
                }
            } else {
                // 登录成功 → 若尚未看过欢迎页，则弹出欢迎；否则恢复主界面 + 拉公告
                if !hasSeenOnboarding {
                    showWelcomeGate = true
                } else {
                    showLoginGate = false
                    Task { await updateCenter.checkAndPresentFromBackend() }
                }
            }
        }

        // 兼容你的登出广播
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("userDidSignOut"))) { _ in
            if !showWelcomeGate {
                showLoginGate = true
            }
        }
    }
}

// MARK: - Root Flow (TabView 分页 + 统一 CTA)
struct WelcomeFlowView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                WelcomePage1View().tag(0)
                WelcomePage2View().tag(1)
                WelcomePage3View().tag(2)
                WelcomePage4View().tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // 统一底部 CTA（黑底白字）
            Button {
                if page < 3 {
                    page += 1
                    lightHaptic()
                } else {
                    rigidHaptic()
                    hasSeenOnboarding = true
                }
            } label: {
                Text(page == 3 ? "开始使用" : "继续")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.primary.opacity(0.9))
                    .foregroundStyle(Color(UIColor.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
        }
        .background(Color(UIColor.systemBackground))
        .interactiveDismissDisabled(true)
    }

    private func lightHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func rigidHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }
}

// ✅ DEBUG 通知名（发现页点击预览卡片触发）
extension Notification.Name {
    static let debugShowUpdatePopup = Notification.Name("debugShowUpdatePopup")
}
