//
//  RoommateModels.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/11/30.
//

import Foundation

// roommate_posts 底表（与后端列一一对应）
public struct RoommatePost: Codable, Identifiable {
    public let id: UUID
    public let user_id: UUID
    public let resort_id: Int

    public let content: String

    public let is_hidden: Bool
    public let canceled_at: Date?
    public let created_at: Date
    public let updated_at: Date
}

// 插入载荷
public struct RoommatePostInsert: Codable {
    public let user_id: UUID
    public let resort_id: Int
    public let content: String
    public var is_hidden: Bool = false
}

