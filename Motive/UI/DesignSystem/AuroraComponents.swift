//
//  AuroraComponents.swift
//  Motive
//
//  Aurora Design System - UI Components
//

import AppKit
import SwiftUI

// MARK: - Aurora Gradient Border

struct AuroraGradientBorder: View {
    var cornerRadius: CGFloat = AuroraRadius.lg
    var lineWidth: CGFloat = 1.5
    var opacity: Double = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.Aurora.accent, lineWidth: lineWidth)
            .opacity(opacity)
    }
}

// MARK: - Aurora Background

struct AuroraBackground: View {
    var cornerRadius: CGFloat = AuroraRadius.lg
    var showGradientBorder: Bool = true
    var borderOpacity: Double = 0.4

    var body: some View {
        ZStack {
            // Solid background
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.Aurora.surface)

            // Subtle gradient overlay for depth
            EmptyView()

            // Gradient border
            if showGradientBorder {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.Aurora.border, lineWidth: 1)
                    .opacity(borderOpacity)
            }
        }
    }
}

// MARK: - Aurora Surface (for cards/elevated content)

struct AuroraSurface: View {
    var cornerRadius: CGFloat = AuroraRadius.md
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.Aurora.surface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.Aurora.border, lineWidth: 1)
            )
    }
}

// MARK: - Legacy Glass Backgrounds (for compatibility)

struct GlassBackground: View {
    var cornerRadius: CGFloat = CornerRadius.large
    var opacity: Double = 0.85
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
            Color.Aurora.background.opacity(opacity)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.Aurora.border, lineWidth: 0.5)
        )
    }
}

struct DarkGlassBackground: View {
    var cornerRadius: CGFloat = CornerRadius.large
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VisualEffectView(
                material: colorScheme == .dark ? .sidebar : .hudWindow,
                blendingMode: .behindWindow,
                state: .active
            )
            Color.Aurora.backgroundDeep.opacity(0.9)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.Aurora.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Aurora Status Indicator

struct AuroraStatusIndicator: View {
    let state: AppState.MenuBarState
    @State private var isPulsing = false
    @State private var gradientRotation: Double = 0

    var body: some View {
        ZStack {
            // Outer glow for active states
            if state != .idle {
                Circle()
                    .fill(stateColor.opacity(0.2))
                    .frame(width: 14, height: 14)
                    .scaleEffect(isPulsing ? 1.5 : 1.0)
                    .opacity(isPulsing ? 0 : 0.5)
            }

            // Main indicator
            Circle()
                .fill(AnyShapeStyle(stateColor))
                .frame(width: 8, height: 8)
        }
        .onAppear {
            if state != .idle {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: state) { _, newState in
            isPulsing = false
            if newState != .idle {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
        }
    }

    private var stateColor: Color {
        switch state {
        case .idle: return Color.Aurora.textMuted
        case .reasoning: return Color.Aurora.primary
        case .executing: return Color.Aurora.primaryLight
        case .responding: return Color.Aurora.primaryLight
        }
    }
}

// Legacy StatusIndicator for compatibility
struct StatusIndicator: View {
    let state: AppState.MenuBarState

    var body: some View {
        AuroraStatusIndicator(state: state)
    }
}

// MARK: - Aurora Button Style

struct AuroraButtonStyle: ButtonStyle {
    enum Style {
        case primary    // Gradient fill
        case secondary  // Outline
        case ghost      // No background
    }

    var style: Style = .primary
    var size: Size = .medium

    enum Size {
        case small, medium, large

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return AuroraSpacing.space3
            case .medium: return AuroraSpacing.space4
            case .large: return AuroraSpacing.space5
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small: return AuroraSpacing.space2
            case .medium: return AuroraSpacing.space3
            case .large: return AuroraSpacing.space4
            }
        }

        var font: Font {
            switch self {
            case .small: return .Aurora.caption
            case .medium: return .Aurora.bodySmall
            case .large: return .Aurora.body
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font.weight(.semibold))
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(background(isPressed: configuration.isPressed))
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
            .overlay(overlay)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.auroraSpringStiff, value: configuration.isPressed)
    }

    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        switch style {
        case .primary:
            Color.Aurora.primary
                .opacity(isPressed ? 0.85 : 1.0)
        case .secondary:
            Color.Aurora.surface
                .opacity(isPressed ? 0.8 : 1.0)
        case .ghost:
            Color.clear
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary, .ghost: return Color.Aurora.textPrimary
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if style == .secondary {
            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                .stroke(Color.Aurora.border, lineWidth: 1)
        }
    }
}


// MARK: - Aurora Text Field Style

// MARK: - Aurora Styled TextField (View-based component)
// NOTE: TextFieldStyle cannot use .textFieldStyle(.plain) inside _body
// Use this View component directly instead of TextFieldStyle

struct AuroraStyledTextField: View {
    let placeholder: String
    @Binding var text: String
    var isFocused: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    private var backgroundColor: Color {
        isDark ? Color.Aurora.backgroundDeep : Color.Aurora.surface
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.Aurora.body)
            .foregroundColor(Color.Aurora.textPrimary)
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space3)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .stroke(
                        isFocused ? Color.Aurora.borderFocus : Color.Aurora.border,
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .animation(.auroraFast, value: isFocused)
    }
}

// Legacy TextFieldStyle (kept for compatibility, does nothing special)
struct AuroraTextFieldStyle: TextFieldStyle {
    var isFocused: Bool = false
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
    }
}


// MARK: - Aurora Card Component

struct AuroraCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = AuroraSpacing.space4

    init(padding: CGFloat = AuroraSpacing.space4, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background(AuroraSurface())
    }
}


// MARK: - Aurora Section Header

struct AuroraSectionHeader: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: AuroraSpacing.space2) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.Aurora.accent)
            }
            Text(title)
                .font(.Aurora.caption)
                .foregroundColor(Color.Aurora.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }
}

// Legacy SectionHeader
struct SectionHeader: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        AuroraSectionHeader(title: title, icon: icon)
    }
}

// MARK: - Aurora Empty State

struct AuroraEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AuroraSpacing.space4) {
            ZStack {
                Circle()
                    .fill(Color.Aurora.accent.opacity(0.1))
                    .frame(width: 72, height: 72)

                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.Aurora.auroraGradient)
            }

            VStack(spacing: AuroraSpacing.space2) {
                Text(title)
                    .font(.Aurora.headline)
                    .foregroundColor(Color.Aurora.textPrimary)

                Text(message)
                    .font(.Aurora.bodySmall)
                    .foregroundColor(Color.Aurora.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Legacy EmptyStateView
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        AuroraEmptyState(icon: icon, title: title, message: message)
    }
}

// MARK: - Aurora Shimmer Effect

struct AuroraShimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    var isDark: Bool = true

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: shimmerColor.opacity(0.4), location: 0.4),
                            .init(color: shimmerColor.opacity(0.6), location: 0.5),
                            .init(color: shimmerColor.opacity(0.4), location: 0.6),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }

    private var shimmerColor: Color {
        isDark ? Color.Aurora.accentMid : Color.Aurora.accentStart
    }
}

extension View {
    func auroraShimmer(isDark: Bool = true) -> some View {
        modifier(AuroraShimmer(isDark: isDark))
    }
}
