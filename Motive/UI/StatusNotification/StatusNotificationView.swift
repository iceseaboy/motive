//
//  StatusNotificationView.swift
//  Motive
//
//  Simple notification popup below status bar.
//

import SwiftUI

enum StatusNotificationType {
    case success
    case error
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        // 保留彩色以区分成功/失败
        switch self {
        case .success: return .green
        case .error: return .red
        }
    }
    
    var title: String {
        switch self {
        case .success: return L10n.Drawer.completed
        case .error: return L10n.Drawer.failed
        }
    }
}

struct StatusNotificationView: View {
    let type: StatusNotificationType
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(type.color)
            
            Text(type.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.Velvet.textPrimary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .fixedSize()
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                (isDark ? Color(hex: "1A1A1C").opacity(0.85) : Color.white.opacity(0.92))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isDark ? 0.3 : 0.1), radius: 12, x: 0, y: 6)
        .onTapGesture { onDismiss() }
    }
}
