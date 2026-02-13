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
    /// Current agent mode (e.g. "plan").
    var agent: String = "agent"

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

// MARK: - Agent Mode Toggle

/// Compact segmented toggle for switching between Agent and Plan modes.
struct AgentModeToggle: View {
    let currentAgent: String
    let isRunning: Bool
    let onChange: (String) -> Void

    private struct ModeOption: Hashable {
        let value: String
        let label: String
        let icon: String
    }

    private var modeOptions: [ModeOption] {
        var base: [ModeOption] = [
            ModeOption(value: "agent", label: "Agent", icon: "sparkle"),
            ModeOption(value: "plan", label: "Plan", icon: "checklist"),
        ]
        if !base.contains(where: { $0.value == currentAgent }) {
            base.append(
                ModeOption(
                    value: currentAgent,
                    label: modeDisplayName(currentAgent),
                    icon: "circle.hexagongrid.fill"
                )
            )
        }
        return base
    }

    var body: some View {
        Menu {
            ForEach(modeOptions, id: \.value) { option in
                Button {
                    onChange(option.value)
                } label: {
                    Label(option.label, systemImage: option.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconForMode(currentAgent))
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12, height: 12)
                Text(modeDisplayName(currentAgent))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(Color.Aurora.textMuted)
            }
            .foregroundColor(activeColor(for: currentAgent))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                    .fill(activeColor(for: currentAgent).opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                    .stroke(activeColor(for: currentAgent).opacity(0.25), lineWidth: 0.5)
            )
            .frame(height: 20)
        }
        .menuStyle(.borderlessButton)
        .disabled(isRunning)
        .opacity(isRunning ? 0.5 : 1.0)
    }

    private func iconForMode(_ value: String) -> String {
        switch value {
        case "plan": return "checklist"
        case "agent": return "sparkle"
        default: return "circle.hexagongrid.fill"
        }
    }

    private func modeDisplayName(_ value: String) -> String {
        guard !value.isEmpty else { return "Agent" }
        return value.prefix(1).uppercased() + String(value.dropFirst())
    }

    private func activeColor(for value: String) -> Color {
        value == "plan" ? Color.Aurora.planAccent : Color.Aurora.primary
    }
}

// MARK: - Agent Mode Badge

/// Compact badge showing the current agent mode (e.g. "Plan").
struct AgentModeBadge: View {
    let agent: String

    private var displayName: String {
        guard !agent.isEmpty else { return "Agent" }
        return agent.prefix(1).uppercased() + String(agent.dropFirst())
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checklist")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 10, height: 10)
            Text(displayName)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundColor(Color.Aurora.planAccent)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(Color.Aurora.planAccent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .strokeBorder(Color.Aurora.planAccent.opacity(0.25), lineWidth: 0.5)
        )
        .frame(height: 20)
    }
}

// MARK: - Context Size Badge

struct ContextSizeBadge: View {
    let tokens: Int
    private let softCapTokens: Double = 120_000

    private var usageRatio: Double {
        min(max(Double(tokens) / softCapTokens, 0), 1)
    }

    private var fillColor: Color {
        if usageRatio > 0.9 { return Color.Aurora.error }
        if usageRatio > 0.75 { return Color.Aurora.warning }
        return Color.Aurora.primary
    }

    private var formattedTokens: String {
        TokenUsageFormatter.formatTokens(tokens)
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.Aurora.glassOverlay.opacity(0.10))
                    Capsule(style: .continuous)
                        .fill(fillColor)
                        .frame(width: width * usageRatio)
                }
            }
            .frame(width: 46, height: 8)

            Text(formattedTokens)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundColor(Color.Aurora.textPrimary.opacity(0.9))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .strokeBorder(Color.Aurora.glassOverlay.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityLabel("Context tokens \(formattedTokens)")
    }
}
