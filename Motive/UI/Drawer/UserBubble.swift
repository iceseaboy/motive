//
//  UserBubble.swift
//  Motive
//
//  Aurora Design System - User message bubble component
//

import SwiftUI

struct UserBubble: View {
    let message: ConversationMessage
    let isDark: Bool

    var body: some View {
        Text(message.content)
            .font(.Aurora.body)
            .foregroundColor(Color.Aurora.textPrimary)
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space3)
            .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.10 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                    .strokeBorder(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.08), lineWidth: 0.5)
            )
            .textSelection(.enabled)
    }
}
