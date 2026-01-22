//
//  DrawerView.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

struct DrawerView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var configManager: ConfigManager
    @StateObject private var permissionManager = PermissionManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showContent = false
    @State private var inputText = ""
    @State private var showSessionPicker = false
    @FocusState private var isInputFocused: Bool
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Adaptive colors
    private var buttonBackground: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }
    private var buttonBorder: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)
    }

    var body: some View {
        ZStack {
            // Adaptive glass background
            DarkGlassBackground(cornerRadius: 16)
            
            VStack(spacing: 0) {
                // Header with session picker
                conversationHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                
                // Divider
                Rectangle()
                    .fill(Color.Velvet.border)
                    .frame(height: 1)
                
                // Error banner (if any)
                if let error = appState.lastErrorMessage {
                    errorBanner(error)
                }
                
                // Content
                if appState.messages.isEmpty && appState.lastErrorMessage == nil {
                    emptyState
                } else if !appState.messages.isEmpty {
                    conversationContent
                } else {
                    Spacer()
                }
                
                // Input area (always visible)
                chatInputArea
            }
            
            // Session picker overlay
            if showSessionPicker {
                sessionPickerOverlay
            }
            
            // Permission request overlay
            if permissionManager.isShowingRequest, let request = permissionManager.currentRequest {
                PermissionRequestView(request: request) { response in
                    permissionManager.respond(with: response)
                }
                .transition(.opacity)
            }
        }
        .frame(width: 380, height: 540)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(isDark ? 0.4 : 0.15), radius: 40, y: 15)
        .onAppear {
            withAnimation(.velvetSpring.delay(0.1)) {
                showContent = true
            }
        }
    }
    
    // MARK: - Header
    
    private var conversationHeader: some View {
        HStack(spacing: 10) {
            // Session selector button
            Button(action: { showSessionPicker.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.Velvet.textSecondary)
                    
                    Text(currentSessionTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.Velvet.textPrimary)
                        .lineLimit(1)
                    
                    Image(systemName: showSessionPicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color.Velvet.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(buttonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(buttonBorder, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Status badge
            SessionStatusBadge(status: appState.sessionStatus, currentTool: appState.currentToolName)
            
            // New chat button
            Button(action: { appState.startNewEmptySession() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.Velvet.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(buttonBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(buttonBorder, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            
            // Close button
            Button(action: { appState.hideDrawer() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.Velvet.textMuted)
                    .frame(width: 26, height: 26)
                    .background(buttonBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(buttonBorder, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help(L10n.Drawer.close)
        }
    }
    
    private var currentSessionTitle: String {
        if appState.messages.isEmpty {
            return L10n.Drawer.newChat
        }
        // Use first user message as title
        if let firstUser = appState.messages.first(where: { $0.type == .user }) {
            let text = firstUser.content
            return String(text.prefix(24)) + (text.count > 24 ? "…" : "")
        }
        return L10n.Drawer.conversation
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(Color.Velvet.textPrimary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.error)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.Velvet.textPrimary)
                
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Color.Velvet.textSecondary)
                    .lineLimit(3)
            }
            
            Spacer()
            
            Button {
                appState.lastErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.Velvet.textMuted)
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 72, height: 72)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Color.Velvet.textSecondary)
            }
            
            VStack(spacing: 6) {
                Text(L10n.Drawer.startConversation)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.Velvet.textPrimary)
                
                Text(L10n.Drawer.startHint)
                    .font(.system(size: 12))
                    .foregroundColor(Color.Velvet.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            
            Spacer()
        }
        .padding(24)
    }
    
    // MARK: - Conversation Content
    
    private var conversationContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(appState.messages.enumerated()), id: \.element.id) { index, message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 8)
                            .animation(
                                .velvetSpring.delay(Double(index) * 0.015),
                                value: showContent
                            )
                    }
                    
                    // Thinking indicator
                    if appState.sessionStatus == .running {
                        ThinkingIndicator(toolName: appState.currentToolName)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .onChange(of: appState.messages.count) { _, _ in
                if let last = appState.messages.last {
                    withAnimation(.velvetSpring) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Chat Input Area
    
    // Adaptive colors for input area
    private var inputFieldBackground: Color {
        isDark ? Color.white.opacity(0.04) : Color.white
    }
    private var inputFieldBorder: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)
    }
    private var inputAreaBackground: Color {
        isDark ? Color.black.opacity(0.2) : Color.black.opacity(0.03)
    }
    private var sendButtonDisabledBg: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    
    private var chatInputArea: some View {
        VStack(spacing: 0) {
            // Top border
            Rectangle()
                .fill(Color.Velvet.border)
                .frame(height: 1)
            
            HStack(spacing: 10) {
                if appState.sessionStatus == .running {
                    // Running state with shimmer effect
                    HStack(spacing: 8) {
                        ShimmerText(text: L10n.Drawer.processing, isDark: isDark)
                    }
                    
                    Spacer()
                    
                    Button(action: { appState.interruptSession() }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    // Input field with styled background
                    HStack(spacing: 8) {
                        TextField(L10n.Drawer.messagePlaceholder, text: $inputText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(Color.Velvet.textPrimary)
                            .focused($isInputFocused)
                            .onSubmit(sendMessage)
                        
                        // Send button
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(inputText.isEmpty ? Color.Velvet.textMuted : (isDark ? .black : .white))
                                .frame(width: 24, height: 24)
                                .background(
                                    inputText.isEmpty
                                        ? sendButtonDisabledBg
                                        : (isDark ? Color.white : Color.black)
                                )
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(inputFieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(inputFieldBorder, lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(inputAreaBackground)
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        
        if appState.messages.isEmpty {
            // Start new session
            appState.submitIntent(text)
        } else {
            // Continue existing session
            appState.resumeSession(with: text)
        }
    }
    
    // MARK: - Session Picker Overlay
    
    private var sessionPickerOverlay: some View {
        ZStack {
            // Dismiss background
            Color.black.opacity(isDark ? 0.4 : 0.2)
                .ignoresSafeArea()
                .onTapGesture { showSessionPicker = false }
            
            // Session list
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(L10n.Drawer.history)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.Velvet.textPrimary)
                    
                    Spacer()
                    
                    Button(action: { showSessionPicker = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.Velvet.textMuted)
                            .frame(width: 20, height: 20)
                            .background(buttonBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                
                Rectangle()
                    .fill(Color.Velvet.border)
                    .frame(height: 1)
                
                // Session list
                let sessions = appState.getAllSessions()
                if sessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(Color.Velvet.textMuted)
                        Text(L10n.Drawer.noHistory)
                            .font(.system(size: 12))
                            .foregroundColor(Color.Velvet.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(sessions.prefix(15), id: \.id) { session in
                                SessionListItem(session: session, isDark: isDark) {
                                    appState.switchToSession(session)
                                    showSessionPicker = false
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 280)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDark ? Color(hex: "1A1A1C") : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .shadow(color: .black.opacity(isDark ? 0.4 : 0.15), radius: 30, y: 10)
            .frame(width: 320)
            .padding(.top, 50)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
    
}

// MARK: - Session List Item

private struct SessionListItem: View {
    let session: Session
    var isDark: Bool = true
    let onSelect: () -> Void
    @State private var isHovering = false
    
    private var hoverBackground: Color {
        isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04)
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                
                // Content
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.intent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.Velvet.textPrimary)
                        .lineLimit(1)
                    
                    Text(timeAgo)
                        .font(.system(size: 10))
                        .foregroundColor(Color.Velvet.textMuted)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.Velvet.textMuted)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isHovering ? hoverBackground : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    private var statusColor: Color {
        // 保留彩色以区分状态
        switch session.status {
        case "running": return .blue
        case "completed": return .green
        case "failed": return .red
        default: return Color.Velvet.textMuted
        }
    }
    
    private var timeAgo: String {
        let now = Date()
        let diff = now.timeIntervalSince(session.createdAt)
        
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        return "\(Int(diff / 86400))d"
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ConversationMessage
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Adaptive colors for bubbles
    private var bubbleBackground: Color {
        isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04)
    }
    private var bubbleBorder: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.08)
    }

    var body: some View {
        HStack {
            if message.type == .user {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.type == .user ? .trailing : .leading, spacing: 0) {
                // Message content with overlay timestamp
                ZStack(alignment: message.type == .user ? .topTrailing : .topLeading) {
                    // Message content
                    Group {
                        switch message.type {
                        case .user:
                            userBubble
                        case .assistant:
                            assistantBubble
                        case .tool:
                            toolBubble
                        case .system:
                            systemBubble
                        }
                    }
                    
                    // Timestamp overlay (show on hover)
                    if isHovering {
                        Text(message.timestamp, style: .time)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.7))
                            )
                            .offset(
                                x: message.type == .user ? -6 : 6,
                                y: -6
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
            }
            .animation(.easeOut(duration: 0.15), value: isHovering)
            
            if message.type != .user {
                Spacer(minLength: 30)
            }
        }
        .onHover { isHovering = $0 }
    }
    
    private var userBubble: some View {
        Text(message.content)
            .font(.system(size: 13))
            .foregroundColor(isDark ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDark ? Color.white : Color.black)
            )
            .textSelection(.enabled)
    }
    
    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Avatar
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.purple)
                
                Text(L10n.Drawer.assistant)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.Velvet.textSecondary)
            }
            
            Text(message.content)
                .font(.system(size: 13))
                .foregroundColor(Color.Velvet.textPrimary)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(bubbleBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(bubbleBorder, lineWidth: 0.5)
        )
    }
    
    private var toolBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: toolIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(message.toolName?.simplifiedToolName ?? L10n.Drawer.tool)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.Velvet.textSecondary)
                
                if !message.content.isEmpty && message.content != "…" {
                    Text(message.content)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color.Velvet.textMuted)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.green.opacity(0.15), lineWidth: 0.5)
        )
    }
    
    private var systemBubble: some View {
        HStack(spacing: 5) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundColor(Color.Velvet.textMuted)
            
            Text(message.content)
                .font(.system(size: 11))
                .foregroundColor(Color.Velvet.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
    
    private var toolIcon: String {
        guard let toolName = message.toolName?.lowercased() else { return "terminal" }
        
        switch toolName {
        case "read", "read_file": return "doc.text"
        case "write", "write_file": return "square.and.pencil"
        case "edit", "edit_file": return "pencil"
        case "bash", "shell", "command": return "terminal"
        case "glob", "find", "search": return "magnifyingglass"
        case "grep": return "text.magnifyingglass"
        case "task", "agent": return "brain"
        default: return "wrench"
        }
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    let toolName: String?
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        ShimmerText(
            text: toolName?.simplifiedToolName ?? L10n.Drawer.thinking,
            isDark: isDark
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04))
        )
    }
}

// MARK: - Session Status Badge

struct SessionStatusBadge: View {
    let status: AppState.SessionStatus
    let currentTool: String?
    
    var body: some View {
        HStack(spacing: 5) {
            statusIcon
                .font(.system(size: 9, weight: .bold))
            
            Text(statusText)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(statusColor.opacity(0.1))
        )
    }
    
    private var statusIcon: some View {
        Group {
            switch status {
            case .idle:
                Image(systemName: "circle")
            case .running:
                Image(systemName: "circle.fill")
                    .foregroundColor(.blue)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
            case .failed:
                Image(systemName: "xmark.circle.fill")
            case .interrupted:
                Image(systemName: "pause.circle.fill")
            }
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
    
    private var statusColor: Color {
        // 保留彩色以区分状态
        switch status {
        case .idle:
            return Color.Velvet.textMuted
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .interrupted:
            return .orange
        }
    }
}

// MARK: - Shimmer Text Effect

struct ShimmerText: View {
    let text: String
    var isDark: Bool = true
    @State private var offset: CGFloat = -1
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isDark ? .white.opacity(0.6) : .black.opacity(0.6))
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: shimmerColor, location: 0.4),
                                .init(color: shimmerColor.opacity(0.5), location: 0.5),
                                .init(color: shimmerColor, location: 0.6),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: offset * 200)
                    .mask(
                        Text(text)
                            .font(.system(size: 12, weight: .medium))
                    )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    offset = 2
                }
            }
    }
    
    private var shimmerColor: Color {
        isDark ? .white : .black
    }
}
