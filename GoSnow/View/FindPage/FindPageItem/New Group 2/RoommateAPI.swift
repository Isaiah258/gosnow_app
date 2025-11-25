//
//  RoommateAPI.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/11/30.
//

import Foundation
import Supabase

enum RoommateAPI {
    static var client: SupabaseClient { DatabaseManager.shared.client }
}

// MARK: - 公共：取雪场列表（复用 Resorts_data）
extension RoommateAPI {
    static func fetchAllResorts() async throws -> [Resorts_data] {
        try await client
            .from("Resorts_data")
            .select()
            .order("name_resort", ascending: true)
            .execute()
            .value
    }
}

// MARK: - 发帖 / 列表 / 我的
extension RoommateAPI {

    static func createPost(
        resortID: Int,
        content: String
    ) async throws -> RoommatePost {
        guard let u = DatabaseManager.shared.getCurrentUser() else {
            throw NSError(domain: "Roommate", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "未登录"])
        }

        let payload = RoommatePostInsert(
            user_id: u.id,
            resort_id: resortID,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            is_hidden: false
        )

        return try await client
            .from("roommate_posts")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    /// 按雪场筛选列表，resortID 为 nil 时表示所有雪场
    static func fetchPosts(
        resortID: Int?,
        page: Int,
        pageSize: Int
    ) async throws -> [RoommatePost] {
        var q = client
            .from("roommate_posts")
            .select()
            .eq("is_hidden", value: false)
            .is("canceled_at", value: nil)

        if let rid = resortID {
            q = q.eq("resort_id", value: rid)
        }

        let from = page * pageSize
        let to = from + pageSize - 1

        return try await q
            .order("created_at", ascending: false)
            .range(from: from, to: to)
            .execute()
            .value
    }

    /// 我的拼房帖子（RLS 限制为当前用户）
    static func fetchMyPosts() async throws -> [RoommatePost] {
        try await client
            .from("roommate_posts")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }
}

// MARK: - 取消 / 恢复
extension RoommateAPI {
    struct CancelPatch: Encodable {
        let is_hidden: Bool
        let canceled_at: String?
    }

    static func cancelPost(id: UUID) async throws {
        let patch = CancelPatch(
            is_hidden: true,
            canceled_at: ISO8601Z.string(Date())
        )
        _ = try await client
            .from("roommate_posts")
            .update(patch)
            .eq("id", value: id.uuidString)
            .execute()
    }

    static func restorePost(id: UUID) async throws {
        let patch = CancelPatch(
            is_hidden: false,
            canceled_at: nil
        )
        _ = try await client
            .from("roommate_posts")
            .update(patch)
            .eq("id", value: id.uuidString)
            .execute()
    }
}
