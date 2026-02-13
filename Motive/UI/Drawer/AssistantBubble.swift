//
//  AssistantBubble.swift
//  Motive
//
//  Aurora Design System - Assistant message bubble component
//

import MarkdownUI
import SwiftUI

struct AssistantBubble: View {
    let message: ConversationMessage
    let isDark: Bool

    /// Get agent identity for display
    private var agentIdentity: AgentIdentity? {
        WorkspaceManager.shared.loadIdentity()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space2) {
            HStack(spacing: AuroraSpacing.space2) {
                if let identity = agentIdentity, identity.hasValues(), let emoji = identity.emoji {
                    Text(emoji)
                        .font(.system(size: 12))
                } else {
                    Circle()
                        .fill(Color.Aurora.primary)
                        .frame(width: 6, height: 6)
                }

                Text(agentIdentity?.displayName ?? L10n.Drawer.assistant)
                    .font(.Aurora.micro.weight(.semibold))
                    .foregroundColor(Color.Aurora.textSecondary)
            }

            Markdown(message.content)
                .markdownTextStyle {
                    FontSize(13)
                    ForegroundColor(Color.Aurora.textPrimary)
                }
                .markdownBlockStyle(\.codeBlock) { configuration in
                    configuration.label
                        .padding(8)
                        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.05))
                        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm))
                }
                .textSelection(.enabled)
        }
        .padding(AuroraSpacing.space3)
        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .strokeBorder(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.06), lineWidth: 0.5)
        )
    }
}
