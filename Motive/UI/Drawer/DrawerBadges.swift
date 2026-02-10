//
//  DrawerBadges.swift
//  Motive
//
//  Aurora Design System - Drawer Components
//

import SwiftUI

// MARK: - Session Status Badge

struct SessionStatusBadge: View {
    let status: SessionStatus
    let currentTool: String?
    let isThinking: Bool

    var body: some View {
        HStack(spacing: AuroraSpacing.space1) {
            statusIcon
                .font(.system(size: 10, weight: .bold))

            if status == .running && isThinking {
                ShimmerText(text: statusText)
            } else {
                Text(statusText)
                    .font(.Aurora.micro.weight(.semibold))
            }
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, AuroraSpacing.space2)
        .padding(.vertical, AuroraSpacing.space1)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(backgroundColor)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .idle:
            Image(systemName: "circle")
        case .running:
            Image(systemName: "circle.fill")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "xmark.circle.fill")
        case .interrupted:
            Image(systemName: "pause.circle.fill")
        }
    }

    private var statusText: String {
        switch status {
        case .idle:
            return L10n.StatusBar.idle
        case .running:
            return currentTool?.simplifiedToolName ?? L10n.Drawer.running
        case .completed:
            return L10n.Drawer.completed
        case .failed:
            return L10n.Drawer.failed
        case .interrupted:
            return L10n.Drawer.interrupted
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .idle: return Color.Aurora.textMuted
        case .running: return Color.Aurora.primary
        case .completed: return Color.Aurora.success
        case .failed: return Color.Aurora.error
        case .interrupted: return Color.Aurora.warning
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.12)
    }
}

// MARK: - Context Size Badge

struct ContextSizeBadge: View {
    let tokens: Int

    var body: some View {
        HStack(spacing: AuroraSpacing.space1) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 10, weight: .bold))

            Text("CTX \(TokenUsageFormatter.formatTokens(tokens))")
                .font(.Aurora.micro.weight(.semibold))
        }
        .foregroundColor(Color.Aurora.textSecondary)
        .padding(.horizontal, AuroraSpacing.space2)
        .padding(.vertical, AuroraSpacing.space1)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(0.08))
        )
    }
}
