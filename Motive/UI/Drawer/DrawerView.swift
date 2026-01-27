//
//  DrawerView.swift
//  Motive
//
//  Aurora Design System - Drawer (Conversation Panel)
//  Session management via dropdown menu in header
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
    @State private var sessions: [Session] = []
    @FocusState private var isInputFocused: Bool
    
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            // Aurora background
            drawerBackground
            
            VStack(spacing: 0) {
                // Header with session dropdown
                conversationHeader
                    .padding(.horizontal, AuroraSpacing.space4)
                    .padding(.top, AuroraSpacing.space4)
                    .padding(.bottom, AuroraSpacing.space3)
                
                // Aurora accent bar
                Rectangle()
                    .fill(Color.Aurora.auroraGradient)
                    .frame(height: 2)
                    .opacity(0.6)
                
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
        .frame(width: 400, height: 600)
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .stroke(Color.Aurora.border, lineWidth: 1)
        )
        .shadow(color: Color.Aurora.accentMid.opacity(isDark ? 0.15 : 0.08), radius: 30, y: 10)
        .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.15), radius: 25, y: 15)
        .onAppear {
            withAnimation(.auroraSpring.delay(0.1)) {
                showContent = true
            }
            loadSessions()
        }
    }
    
    private func loadSessions() {
        sessions = appState.getAllSessions()
    }
    
    // MARK: - Background
    
    private var drawerBackground: some View {
        ZStack {
            VisualEffectView(
                material: isDark ? .sidebar : .popover,
                blendingMode: .behindWindow,
                state: .active
            )
            
            Color.Aurora.backgroundDeep.opacity(0.97)
            
            if isDark {
                LinearGradient(
                    colors: [
                        Color.Aurora.accentMid.opacity(0.02),
                        Color.clear,
                        Color.Aurora.accentStart.opacity(0.01)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
    
    // MARK: - Header with Session Dropdown
    
    private var conversationHeader: some View {
        HStack(spacing: AuroraSpacing.space3) {
            // Session dropdown button
            Button(action: { 
                loadSessions()
                withAnimation(.auroraFast) {
                    showSessionPicker.toggle()
                }
            }) {
                HStack(spacing: AuroraSpacing.space2) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.Aurora.textSecondary)
                    
                    Text(currentSessionTitle)
                        .font(.Aurora.bodySmall.weight(.medium))
                        .foregroundColor(Color.Aurora.textPrimary)
                        .lineLimit(1)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.Aurora.textMuted)
                        .rotationEffect(.degrees(showSessionPicker ? 180 : 0))
                }
                .padding(.horizontal, AuroraSpacing.space2)
                .padding(.vertical, AuroraSpacing.space1)
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                        .fill(showSessionPicker ? Color.Aurora.surface : Color.clear)
                )
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Status badge
            SessionStatusBadge(status: appState.sessionStatus, currentTool: appState.currentToolName)
            
            // New chat button
            Button(action: { 
                appState.startNewEmptySession()
                loadSessions()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.Aurora.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.Aurora.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                            .stroke(Color.Aurora.border, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help(L10n.Drawer.newChat)
            
            // Close button
            Button(action: { appState.hideDrawer() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.Aurora.textMuted)
                    .frame(width: 28, height: 28)
                    .background(Color.Aurora.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                            .stroke(Color.Aurora.border, lineWidth: 0.5)
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
        if let firstUser = appState.messages.first(where: { $0.type == .user }) {
            let text = firstUser.content
            return String(text.prefix(24)) + (text.count > 24 ? "…" : "")
        }
        return L10n.Drawer.conversation
    }
    
    // MARK: - Session Picker Overlay
    
    private var sessionPickerOverlay: some View {
        ZStack(alignment: .topLeading) {
            // Dismiss area
            Color.black.opacity(0.01)
                .onTapGesture {
                    withAnimation(.auroraFast) {
                        showSessionPicker = false
                    }
                }
            
            // Dropdown menu
            VStack(spacing: 0) {
                if sessions.isEmpty {
                    Text("No sessions yet")
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textMuted)
                        .padding(AuroraSpacing.space4)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(sessions.prefix(15)) { session in
                                SessionPickerItem(session: session) {
                                    appState.switchToSession(session)
                                    withAnimation(.auroraFast) {
                                        showSessionPicker = false
                                    }
                                } onDelete: {
                                    appState.deleteSession(session)
                                    loadSessions()
                                }
                            }
                        }
                        .padding(AuroraSpacing.space2)
                    }
                    .frame(maxHeight: 300)
                }
            }
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .fill(Color.Aurora.backgroundDeep)
                    .shadow(color: Color.black.opacity(0.2), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .stroke(Color.Aurora.border, lineWidth: 0.5)
            )
            .padding(.top, 52) // Below header
            .padding(.leading, AuroraSpacing.space4)
        }
        .transition(.opacity)
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: AuroraSpacing.space3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(Color.Aurora.error)
            
            VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                Text(L10n.error)
                    .font(.Aurora.bodySmall.weight(.semibold))
                    .foregroundColor(Color.Aurora.textPrimary)
                
                Text(error)
                    .font(.Aurora.caption)
                    .foregroundColor(Color.Aurora.textSecondary)
                    .lineLimit(3)
            }
            
            Spacer()
            
            Button {
                appState.lastErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.Aurora.textMuted)
                    .frame(width: 22, height: 22)
                    .background(Color.Aurora.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(AuroraSpacing.space3)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(Color.Aurora.error.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .stroke(Color.Aurora.error.opacity(0.2), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, AuroraSpacing.space4)
        .padding(.vertical, AuroraSpacing.space3)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: AuroraSpacing.space5) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: Color.Aurora.auroraGradientColors.map { $0.opacity(0.15) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.Aurora.auroraGradient)
            }
            
            VStack(spacing: AuroraSpacing.space2) {
                Text(L10n.Drawer.startConversation)
                    .font(.Aurora.headline)
                    .foregroundColor(Color.Aurora.textPrimary)
                
                Text(L10n.Drawer.startHint)
                    .font(.Aurora.bodySmall)
                    .foregroundColor(Color.Aurora.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            
            // Hint about session dropdown
            Text("Tip: Click the title above to switch sessions")
                .font(.Aurora.caption)
                .foregroundColor(Color.Aurora.textMuted)
            
            Spacer()
        }
        .padding(AuroraSpacing.space6)
    }
    
    // MARK: - Conversation Content
    
    private var conversationContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AuroraSpacing.space3) {
                    ForEach(Array(appState.messages.enumerated()), id: \.element.id) { index, message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 8)
                            .animation(
                                .auroraSpring.delay(Double(index) * 0.02),
                                value: showContent
                            )
                    }
                    
                    // Thinking indicator
                    if appState.sessionStatus == .running {
                        ThinkingIndicator(toolName: appState.currentToolName)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, AuroraSpacing.space4)
                .padding(.vertical, AuroraSpacing.space4)
            }
            .onChange(of: appState.messages.count) { _, _ in
                if let last = appState.messages.last {
                    withAnimation(.auroraSpring) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Chat Input Area
    
    private var chatInputArea: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.Aurora.border)
                .frame(height: 1)
            
            HStack(spacing: AuroraSpacing.space3) {
                if appState.sessionStatus == .running {
                    HStack(spacing: AuroraSpacing.space2) {
                        AuroraLoadingDots()
                        ShimmerText(text: L10n.Drawer.processing, isDark: isDark)
                    }
                    
                    Spacer()
                    
                    Button(action: { appState.interruptSession() }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.Aurora.error)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: AuroraSpacing.space2) {
                        TextField("", text: $inputText, prompt: Text(L10n.Drawer.messagePlaceholder)
                            .foregroundColor(Color.Aurora.textMuted))
                            .textFieldStyle(.plain)
                            .font(.Aurora.body)
                            .foregroundColor(Color.Aurora.textPrimary)
                            .focused($isInputFocused)
                            .onSubmit(sendMessage)
                        
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(inputText.isEmpty ? Color.Aurora.textMuted : Color.Aurora.primary)
                        }
                        .buttonStyle(.plain)
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, AuroraSpacing.space3)
                    .padding(.vertical, AuroraSpacing.space2)
                    .background(Color.Aurora.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                            .stroke(
                                isInputFocused ? Color.Aurora.borderFocus : Color.Aurora.border,
                                lineWidth: isInputFocused ? 1.5 : 0.5
                            )
                    )
                    .animation(.auroraFast, value: isInputFocused)
                }
            }
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space3)
            .background(Color.Aurora.backgroundDeep.opacity(0.5))
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        
        if appState.messages.isEmpty {
            appState.submitIntent(text)
        } else {
            appState.resumeSession(with: text)
        }
    }
}

// MARK: - Session Picker Item

private struct SessionPickerItem: View {
    let session: Session
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    @State private var showDeleteConfirm = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AuroraSpacing.space3) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.intent)
                        .font(.Aurora.bodySmall.weight(.medium))
                        .foregroundColor(Color.Aurora.textPrimary)
                        .lineLimit(1)
                    
                    Text(timeAgo)
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textMuted)
                }
                
                Spacer()
                
                // Delete button
                if isHovering {
                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.Aurora.textMuted)
                            .frame(width: 20, height: 20)
                            .background(Color.Aurora.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, AuroraSpacing.space3)
            .padding(.vertical, AuroraSpacing.space2)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(isHovering ? Color.Aurora.surfaceElevated : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.auroraFast, value: isHovering)
        .confirmationDialog("Delete this session?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private var statusColor: Color {
        switch session.status {
        case "running": return Color.Aurora.primary
        case "completed": return Color.Aurora.accent
        case "failed": return Color.Aurora.error
        default: return Color.Aurora.textMuted
        }
    }
    
    private var timeAgo: String {
        let now = Date()
        let diff = now.timeIntervalSince(session.createdAt)
        
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        if diff < 604800 { return "\(Int(diff / 86400))d ago" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: session.createdAt)
    }
}
