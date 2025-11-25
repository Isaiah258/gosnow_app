import Foundation
import SwiftUI
import Supabase

@MainActor
final class UpdateBannerCenter: ObservableObject {

    struct Payload: Identifiable, Equatable {
        let id: UUID
        let bannerImageURL: String?
        let title: String
        let message: String
        let appStoreURL: URL
    }

    @Published var active: Payload? = nil
    private let dismissedKey = "update_banner_last_dismissed_id"

    func dismiss() {
        if let id = active?.id {
            UserDefaults.standard.set(id.uuidString, forKey: dismissedKey)
        }
        active = nil
    }

    func presentIfNeeded(_ payload: Payload) {
        let last = UserDefaults.standard.string(forKey: dismissedKey)
        guard last != payload.id.uuidString else { return }
        active = payload
    }

    struct AppUpdateRow: Codable {
        let id: UUID
        let platform: String
        let is_active: Bool
        let title: String
        let message: String
        let banner_url: String?
        let appstore_url: String
        let latest_build: Int?
        let created_at: String?   // 不强依赖 Date，避免 decoder 配置差异
    }

    func checkAndPresentFromBackend() async {
        do {
            let currentBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
            let client = DatabaseManager.shared.client

            let rows: [AppUpdateRow] = try await client
                .from("app_update_notice")
                .select("id,platform,is_active,title,message,banner_url,appstore_url,latest_build,created_at")
                .eq("platform", value: "ios")
                .eq("is_active", value: true)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            guard let row = rows.first else { return }

            // ✅ 你不想做强制更新：只按 latest_build 做“弱更新”即可
            if let latest = row.latest_build, currentBuild >= latest {
                return
            }

            guard let url = URL(string: row.appstore_url) else { return }

            presentIfNeeded(
                .init(
                    id: row.id,
                    bannerImageURL: row.banner_url,
                    title: row.title,
                    message: row.message,
                    appStoreURL: url
                )
            )
        } catch {
            print("checkAndPresentFromBackend error:", error)
        }
    }
}
