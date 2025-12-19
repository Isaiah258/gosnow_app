//
//  SessionSummaryScreen.swift
//  雪兔滑行
//
//  Created by federico Liu on 2025/10/30.
//

import SwiftUI

struct SessionSummaryScreen: View {
    let summary: SessionSummary
    let routeImage: UIImage?
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            SessionSummarySheet(summary: summary, routeImage: routeImage)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("完成") { onClose() }
                    }
                }
        }
        .interactiveDismissDisabled(true)
    }
}

