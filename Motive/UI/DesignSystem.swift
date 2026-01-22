//
//  DesignSystem.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import SwiftUI

// MARK: - Color Palette (Monochrome - Next.js/Linear Style)

extension Color {
    enum Velvet {
        // Primary - pure black/white adaptive
        static var primary: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor.white : NSColor.black
            })
        }
        
        static var primaryDark: Color { primary }
        static var primaryLight: Color { primary.opacity(0.7) }
        
        // Accent - same as primary (monochrome)
        static var accent: Color { primary }
        static var accentDark: Color { primary }
        
        // Semantic status colors - all monochrome with varying opacity
        static var idle: Color { primary.opacity(0.4) }
        static var reasoning: Color { primary }
        static var executing: Color { primary }
        static var success: Color { primary }
        static var warning: Color { primary }
        static var error: Color { primary }
        
        // MARK: - Adaptive Surface Colors
        
        static var surface: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "1C1C1E") : NSColor(hex: "FFFFFF")
            })
        }
        
        static var surfaceElevated: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "2C2C2E") : NSColor(hex: "F5F5F7")
            })
        }
        
        static var surfaceLight: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "3A3A3C") : NSColor(hex: "E5E5EA")
            })
        }
        
        static var surfaceDark: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor(hex: "0D0D0F") : NSColor(hex: "FAFAFA")
            })
        }
        
        static var surfaceOverlay: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark 
                    ? NSColor.black.withAlphaComponent(0.5) 
                    : NSColor.black.withAlphaComponent(0.03)
            })
        }
        
        // MARK: - Adaptive Text Colors
        
        static var textPrimary: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark ? NSColor.white : NSColor(hex: "1D1D1F")
            })
        }
        
        static var textSecondary: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark 
                    ? NSColor.white.withAlphaComponent(0.7) 
                    : NSColor(hex: "6E6E73")
            })
        }
        
        static var textMuted: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark 
                    ? NSColor.white.withAlphaComponent(0.45) 
                    : NSColor(hex: "8E8E93")
            })
        }
        
        static var textOnDark: Color { .white }
        static var textOnDarkMuted: Color { Color.white.opacity(0.6) }
        
        // MARK: - Adaptive Border Colors
        
        static var border: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark 
                    ? NSColor.white.withAlphaComponent(0.08) 
                    : NSColor.black.withAlphaComponent(0.08)
            })
        }
        
        static var borderLight: Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.isDark 
                    ? NSColor.white.withAlphaComponent(0.12) 
                    : NSColor.black.withAlphaComponent(0.12)
            })
        }
        
        static let borderFocused = Color.Velvet.primary.opacity(0.3)
        
        // Event kind colors - monochrome with varying opacity
        static func eventColor(for kind: OpenCodeEvent.Kind) -> Color {
            return primary.opacity(0.8)
        }
    }
}

// MARK: - NSColor Helpers

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}

// MARK: - Typography

extension Font {
    enum Velvet {
        // Display - for large titles
        static let displayLarge = Font.system(size: 28, weight: .bold, design: .rounded)
        static let displayMedium = Font.system(size: 24, weight: .semibold, design: .rounded)
        
        // Headlines
        static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
        static let subheadline = Font.system(size: 14, weight: .medium, design: .rounded)
        
        // Body text
        static let body = Font.system(size: 14, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 14, weight: .medium, design: .default)
        
        // Monospace for code/technical
        static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
        
        // Caption & labels
        static let caption = Font.system(size: 11, weight: .regular, design: .default)
        static let label = Font.system(size: 12, weight: .medium, design: .rounded)
    }
}

// MARK: - Spacing

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Corner Radius

enum CornerRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 14
    static let xlarge: CGFloat = 20
}

// MARK: - Shadows

extension View {
    func velvetShadow(opacity: Double = 0.15, radius: CGFloat = 20, y: CGFloat = 8) -> some View {
        self.shadow(color: Color.black.opacity(opacity), radius: radius, x: 0, y: y)
    }
    
    func subtleShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Glass Effect Background (Adaptive)

struct GlassBackground: View {
    var cornerRadius: CGFloat = CornerRadius.large
    var opacity: Double = 0.85
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Blur effect
            VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)
            
            // Overlay for consistent appearance
            if colorScheme == .dark {
                Color(hex: "1C1C1E").opacity(opacity)
            } else {
                Color.white.opacity(0.85)
            }
            
            // Subtle top highlight for depth
            LinearGradient(
                colors: colorScheme == .dark 
                    ? [Color.white.opacity(0.06), Color.clear]
                    : [Color.white.opacity(0.8), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    colorScheme == .dark 
                        ? Color.white.opacity(0.12) 
                        : Color.black.opacity(0.1),
                    lineWidth: 0.5
                )
        )
    }
}

// MARK: - Dark Glass Background (Adaptive - for Drawer & CommandBar)

struct DarkGlassBackground: View {
    var cornerRadius: CGFloat = CornerRadius.large
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Blur effect
            VisualEffectView(
                material: colorScheme == .dark ? .sidebar : .popover,
                blendingMode: .behindWindow,
                state: .active
            )
            
            // Base overlay
            if colorScheme == .dark {
                Color(hex: "141416").opacity(0.92)
            } else {
                Color.white.opacity(0.92)
            }
            
            // Gradient texture
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.white.opacity(0.03), Color.clear, Color.black.opacity(0.1)]
                    : [Color.white.opacity(0.5), Color.clear, Color.black.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.15), Color.white.opacity(0.05)]
                            : [Color.black.opacity(0.1), Color.black.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
    }
}

// MARK: - Animated Status Indicator

struct StatusIndicator: View {
    let state: AppState.MenuBarState
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing && state != .idle ? 1.2 : 1.0)
            .opacity(isPulsing && state != .idle ? 0.7 : 1.0)
            .animation(
                state != .idle
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear { isPulsing = true }
            .onChange(of: state) { _, _ in isPulsing = true }
    }
    
    private var stateColor: Color {
        switch state {
        case .idle: return Color.Velvet.idle
        case .reasoning: return Color.Velvet.reasoning
        case .executing: return Color.Velvet.executing
        }
    }
}

// MARK: - Button Styles

struct VelvetButtonStyle: ButtonStyle {
    var isPrimary: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.Velvet.label)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(
                Group {
                    if isPrimary {
                        // Dark mode: white bg, Light mode: black bg
                        colorScheme == .dark ? Color.white : Color.black
                    } else {
                        Color.primary.opacity(0.08)
                    }
                }
            )
            // Dark mode: black text, Light mode: white text
            .foregroundColor(isPrimary ? (colorScheme == .dark ? .black : .white) : Color.Velvet.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct VelvetSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.Velvet.label)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(Color.black.opacity(configuration.isPressed ? 0.15 : 0.08))
            .foregroundColor(Color.Velvet.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Input Field Style

struct VelvetTextFieldStyle: TextFieldStyle {
    var isFocused: Bool = false
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.Velvet.body)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm + 2)
            .background(Color.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .stroke(
                        isFocused ? Color.Velvet.primary.opacity(0.3) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Card Component

struct VelvetCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = Spacing.md
    
    init(padding: CGFloat = Spacing.md, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.Velvet.primary.opacity(0.6))
            }
            Text(title)
                .font(.Velvet.subheadline)
                .foregroundColor(Color.Velvet.textSecondary)
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundColor(Color.Velvet.textMuted)
            
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.Velvet.headline)
                    .foregroundColor(Color.Velvet.textSecondary)
                
                Text(message)
                    .font(.Velvet.caption)
                    .foregroundColor(Color.Velvet.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Spring Animation Presets

extension Animation {
    static let velvetSpring = Animation.spring(response: 0.35, dampingFraction: 0.75)
    static let quickSpring = Animation.spring(response: 0.25, dampingFraction: 0.7)
}
