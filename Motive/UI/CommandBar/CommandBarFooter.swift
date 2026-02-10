//
//  CommandBarFooter.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension CommandBarView {
    // MARK: - Footer View

    var footerView: some View {
        HStack(spacing: 0) {
            // Left side: status or hints
            leftFooterContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

            // Right side: keyboard shortcuts (keep visible)
            rightFooterContent
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .frame(height: 38)
        .padding(.horizontal, AuroraSpacing.space6)
        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.03))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.06))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    var leftFooterContent: some View {
        // Show current project directory
        HStack(spacing: AuroraSpacing.space2) {
            Image(systemName: "folder")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.Aurora.textMuted)

            Text(configManager.currentProjectShortPath)
                .font(.Aurora.micro)
                .foregroundColor(Color.Aurora.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, AuroraSpacing.space1)
        .padding(.vertical, AuroraSpacing.space1)
        .onTapGesture {
            // Quick access to /project command
            inputText = "/"
            mode = .command(fromSession: !appState.messages.isEmpty)
            selectedCommandIndex = 0  // /project is first in the list
        }
    }

    @ViewBuilder
    var rightFooterContent: some View {
        if mode.isCommand {
            InlineShortcutHint(items: [
                (L10n.CommandBar.select, "↵"),
                (L10n.CommandBar.complete, "tab"),
                (L10n.CommandBar.navigate, "↑↓"),
                (L10n.CommandBar.back, "esc"),
            ])
        } else if mode.isHistory {
            InlineShortcutHint(items: [
                (L10n.CommandBar.open, "↵"),
                (L10n.CommandBar.delete, "⌘⌫"),
                (L10n.CommandBar.navigate, "↑↓"),
                (L10n.CommandBar.back, "esc"),
            ])
        } else if mode.isProjects {
            InlineShortcutHint(items: [
                (L10n.CommandBar.select, "↵"),
                (L10n.CommandBar.navigate, "↑↓"),
                (L10n.CommandBar.back, "esc"),
            ])
        } else {
            switch mode {
            case .idle, .input:
                InlineShortcutHint(items: [
                    (L10n.CommandBar.run, "↵"),
                    (L10n.CommandBar.commands, "/"),
                    (L10n.CommandBar.close, "esc"),
                ])
            case .running:
                InlineShortcutHint(items: [
                    (L10n.CommandBar.close, "esc"),
                ])
            case .completed:
                InlineShortcutHint(items: [
                    (L10n.CommandBar.send, "↵"),
                    (L10n.CommandBar.new, "⌘N"),
                    (L10n.CommandBar.commands, "/"),
                    (L10n.CommandBar.close, "esc"),
                ])
            case .error:
                InlineShortcutHint(items: [
                    (L10n.CommandBar.retry, "↵"),
                    (L10n.CommandBar.commands, "/"),
                    (L10n.CommandBar.close, "esc"),
                ])
            default:
                EmptyView()
            }
        }
    }

    // MARK: - Border Overlay

    var borderOverlay: some View {
        ZStack {
            // Base border — tinted by mode
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)

            // Top-edge inner luminance (mimics light reflection on glass)
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.Aurora.glassOverlay.opacity(0.15), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 0.5
                )
        }
    }

    /// Border tint color that adapts to the current mode
    private var borderColor: Color {
        switch mode {
        case .running:
            Color.Aurora.primary.opacity(0.45)
        case .error:
            Color.Aurora.error.opacity(0.5)
        default:
            Color.Aurora.glassOverlay.opacity(0.08)
        }
    }

    // MARK: - Background

    var commandBarBackground: some View {
        ZStack {
            // Layer 1: Deep vibrancy blur (primary translucency)
            VisualEffectView(
                material: .popover,
                blendingMode: .behindWindow,
                state: .active
            )
            // Layer 2: Very subtle tint overlay — low opacity lets the desktop show through
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .fill(Color.Aurora.background.opacity(0.45))
        }
    }
}
