//
//  DrawerIndicators.swift
//  Motive
//
//  Aurora Design System - Drawer Components
//

import SwiftUI
import MarkdownUI

// MARK: - Tool Running Indicator (small spinner for tool bubble)

struct ToolRunningIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        Image(systemName: "arrow.trianglehead.2.counterclockwise")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color.Aurora.primary)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        // Metallic shimmer text — matches menu bar animation style.
        ShimmerText(
            text: L10n.Drawer.thinking,
            font: .Aurora.caption.weight(.medium)
        )
        .padding(.horizontal, AuroraSpacing.space3)
        .padding(.vertical, AuroraSpacing.space2)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.08))
        )
    }
}

// MARK: - Aurora Loading Dots

struct AuroraLoadingDots: View {
    @State private var animationPhase: Int = 0
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.Aurora.primary)
                    .frame(width: 4, height: 4)
                    .scaleEffect(animationPhase == index ? 1.3 : 0.8)
                    .opacity(animationPhase == index ? 1.0 : 0.4)
            }
        }
        .onAppear {
            animationTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        animationPhase = (animationPhase + 1) % 3
                    }
                }
            }
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }
}

// MARK: - Shimmer Text (thin wrapper over AuroraShimmer)

struct ShimmerText: View {
    let text: String
    var font: Font = .Aurora.micro.weight(.semibold)
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(font)
            .auroraShimmer(isDark: colorScheme == .dark)
    }
}

// MARK: - Transient Reasoning Bubble

/// A standalone bubble that shows live reasoning text during the thinking phase.
/// This is NOT a message — it appears transiently and disappears when thinking ends.
struct TransientReasoningBubble: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let maxLines = 5
        let isTruncated = lines.count > maxLines
        let displayLines = isExpanded ? lines : Array(lines.suffix(maxLines))
        let displayText = displayLines.joined(separator: "\n")

        HStack {
            VStack(alignment: .leading, spacing: AuroraSpacing.space2) {
                HStack(spacing: AuroraSpacing.space2) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.Aurora.textSecondary)
                    Text(L10n.Drawer.thinking)
                        .font(.Aurora.micro.weight(.semibold))
                        .foregroundColor(Color.Aurora.textSecondary)
                        .auroraShimmer(isDark: isDark)
                    Spacer()
                    if isTruncated {
                        Button(action: { withAnimation(.auroraFast) { isExpanded.toggle() } }) {
                            Text(isExpanded ? L10n.collapse : L10n.expand)
                                .font(.Aurora.micro.weight(.medium))
                                .foregroundColor(Color.Aurora.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !trimmed.isEmpty {
                    Markdown(displayText)
                        .markdownTextStyle {
                            FontSize(12)
                            ForegroundColor(Color.Aurora.textPrimary)
                        }
                        .markdownBlockStyle(\.codeBlock) { configuration in
                            configuration.label
                                .padding(6)
                                .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.05 : 0.04))
                                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xs))
                        }
                        .textSelection(.enabled)
                }
            }
            .padding(AuroraSpacing.space3)
            .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                    .strokeBorder(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.06), lineWidth: 0.5)
            )

            Spacer(minLength: 40)
        }
    }
}
