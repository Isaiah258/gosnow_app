//
//  LostAndFoundCard.swift
//  GoSnow
//
//  Created by federico Liu on 2024/12/23.
//

import SwiftUI

struct LostAndFoundCard: View {
    let item: LostAndFoundItems
    var resortName: String? = nil  // 由父级传（可选）

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶部：类型 + 雪场 + 时间
            HStack(spacing: 8) {
                Tag(text: item.type == "lost" ? "丢失" : "拾到")

                if let resortName, !resortName.isEmpty {
                    Tag(text: resortName, icon: "mountain.2.fill")
                }

                Spacer()

                if let date = item.created_at {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(item.item_description)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !item.contact_info.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(.secondary)
                        Text(item.contact_info)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
    }
}

private struct Tag: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(text).font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                .background(
                    Capsule().fill(Color.secondary.opacity(0.08))
                )
        )
        .foregroundStyle(.secondary)
    }
}




