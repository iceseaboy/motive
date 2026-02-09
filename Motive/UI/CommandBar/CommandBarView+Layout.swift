//
//  CommandBarView+Layout.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension CommandBarView {
    var isDark: Bool { colorScheme == .dark }

    // Filtered commands based on input
    var filteredCommands: [CommandDefinition] {
        let query = inputText.hasPrefix("/") ? String(inputText.dropFirst()) : ""
        return CommandDefinition.matching(query)
    }

    var mainContent: some View {
        VStack(spacing: 0) {
            if showsAboveContent {
                aboveInputContent
                Rectangle()
                    .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.12))
                    .frame(height: 0.5)
            }
            inputAreaView
            if showsBelowContent {
                Rectangle()
                    .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.12))
                    .frame(height: 0.5)
                belowInputContent
            } else {
                // Only use spacer when no list content
                Spacer(minLength: 0)
            }
            footerView
        }
        .frame(width: 680, height: currentHeight)
        .background(commandBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous))
        .overlay(borderOverlay)
        // Note: Window-level fade animation is handled by CommandBarWindowController
        // Removed SwiftUI-level entrance animation to prevent double animation
    }

    // Content ABOVE input (session status)
    var showsAboveContent: Bool {
        switch mode {
        case .running, .completed, .error:
            return true
        case .command(let fromSession), .history(let fromSession):
            // Keep status visible when command/history triggered from session
            return fromSession
        default:
            return false
        }
    }

    // Content BELOW input (lists)
    var showsBelowContent: Bool {
        mode.isCommand || mode.isHistory || mode.isProjects
            || isFileCompletionActive
    }

    /// Height to use when file completion is showing (matches command list)
    var fileCompletionHeight: CGFloat {
        showsAboveContent ? 450 : 400
    }

    /// Whether file completion should actively affect height.
    /// Guards against stale `showFileCompletion` state by cross-checking the input.
    var isFileCompletionActive: Bool {
        showFileCompletion
            && !fileCompletion.items.isEmpty
            && currentAtToken(in: inputText) != nil
    }

    /// Current command bar height
    var currentHeight: CGFloat {
        isFileCompletionActive ? fileCompletionHeight : mode.dynamicHeight
    }

    // MARK: - Above Input Content (Session Status)

    @ViewBuilder
    var aboveInputContent: some View {
        Group {
            switch mode {
            case .running:
                runningStatusView
            case .completed:
                completedSummaryView
            case .error(let message):
                errorStatusView(message: message)
            case .command(let fromSession) where fromSession:
                // Show completed status when command triggered from session
                completedSummaryView
            case .history(let fromSession) where fromSession:
                // Show completed status when history triggered from session
                completedSummaryView
            default:
                EmptyView()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Below Input Content (Lists)

    @ViewBuilder
    var belowInputContent: some View {
        Group {
            if isFileCompletionActive {
                // File completion takes priority
                fileCompletionListView
            } else if mode.isCommand {
                commandListView
            } else if mode.isHistory {
                historiesListView
            } else if mode.isProjects {
                projectsListView
            } else {
                EmptyView()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - File Completion List (below input)

    var fileCompletionListView: some View {
        FileCompletionView(
            items: fileCompletion.items,
            selectedIndex: selectedFileIndex,
            currentPath: fileCompletion.currentPath,
            onSelect: selectFileCompletion
        )
        .id("fileCompletion-\(fileCompletion.currentPath)-\(fileCompletion.items.count)")
    }

    // MARK: - Running Status (above input)

    var runningStatusView: some View {
        HStack(spacing: AuroraSpacing.space3) {
            AuroraPulsingDot()

            VStack(alignment: .leading, spacing: 2) {
                Text(runningStatusTitle)
                    .font(.Aurora.caption.weight(.semibold))
                    .foregroundColor(Color.Aurora.textPrimary)
                    .auroraShimmer(isDark: isDark)

                Text(runningStatusDetail)
                    .font(.Aurora.caption)
                    .foregroundColor(Color.Aurora.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .auroraShimmer(isDark: isDark)
            }

            Spacer()

            // Stop button
            Button(action: { appState.interruptSession() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.Aurora.error)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop")
            .accessibilityHint("Interrupts the current task")

            // Open drawer button
            Button(action: {
                appState.toggleDrawer()
                appState.hideCommandBar()
            }) {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.Aurora.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Color.Aurora.glassOverlay.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open conversation")
            .accessibilityHint("Opens the conversation drawer")
        }
        .padding(.horizontal, AuroraSpacing.space6)
        .padding(.vertical, AuroraSpacing.space3)
    }
    
    /// Title for running status - overall task state
    private var runningStatusTitle: String {
        L10n.CommandBar.running  // Always "Running" as the task is in progress
    }
    
    /// Detail for running status - current action (thinking or tool execution)
    private var runningStatusDetail: String {
        // When AI is thinking/reasoning
        if appState.menuBarState == .reasoning {
            return L10n.Drawer.thinking
        }
        
        // When executing a tool, show tool name and details
        if let toolName = appState.currentToolName {
            let simpleName = toolName.simplifiedToolName
            
            // Use currentToolInput directly (set when tool_call is received)
            if let input = appState.currentToolInput, !input.isEmpty {
                return "\(simpleName): \(input)"
            }
            
            return simpleName
        }
        
        // Default to thinking if no tool info
        return L10n.Drawer.thinking
    }

    // MARK: - Completed Summary (above input)

    var completedSummaryView: some View {
        let isNewSession = appState.messages.isEmpty
        let statusTitle = isNewSession ? L10n.CommandBar.newTask : L10n.CommandBar.completed
        let statusIcon = isNewSession ? "plus.circle.fill" : "checkmark.circle.fill"
        let statusColor = isNewSession ? Color.Aurora.primary : Color.Aurora.accent

        return HStack(spacing: AuroraSpacing.space3) {
            Image(systemName: statusIcon)
                .font(.system(size: 16))
                .foregroundColor(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.Aurora.caption.weight(.semibold))
                    .foregroundColor(Color.Aurora.textPrimary)

                if let lastAssistant = appState.messages.last(where: { $0.type == .assistant }) {
                    Text(lastAssistant.content.prefix(60) + (lastAssistant.content.count > 60 ? "..." : ""))
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textMuted)
                        .lineLimit(1)
                } else {
                    Text(L10n.CommandBar.typeRequest)
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Open drawer button
            Button(action: {
                appState.toggleDrawer()
                appState.hideCommandBar()
            }) {
                HStack(spacing: 4) {
                    Text(L10n.CommandBar.details)
                        .font(.Aurora.caption)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(Color.Aurora.textSecondary)
                .padding(.horizontal, AuroraSpacing.space3)
                .padding(.vertical, AuroraSpacing.space2)
                .background(Color.Aurora.glassOverlay.opacity(0.1))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.Aurora.glassOverlay.opacity(0.06), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AuroraSpacing.space6)
        .padding(.vertical, AuroraSpacing.space3)
    }

    // MARK: - Error Status (above input)

    func errorStatusView(message: String) -> some View {
        HStack(spacing: AuroraSpacing.space3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(Color.Aurora.error)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.CommandBar.error)
                    .font(.Aurora.caption.weight(.semibold))
                    .foregroundColor(Color.Aurora.textPrimary)

                Text(message)
                    .font(.Aurora.caption)
                    .foregroundColor(Color.Aurora.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: { mode = .idle }) {
                Text(L10n.CommandBar.dismiss)
                    .font(.Aurora.caption)
                    .foregroundColor(Color.Aurora.textSecondary)
                    .padding(.horizontal, AuroraSpacing.space3)
                    .padding(.vertical, AuroraSpacing.space2)
                    .background(Color.Aurora.glassOverlay.opacity(0.1))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.Aurora.glassOverlay.opacity(0.06), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AuroraSpacing.space6)
        .padding(.vertical, AuroraSpacing.space3)
    }

    // MARK: - Input Area (Always Visible - No icons, status shown above)

    /// Autocomplete hint for command input (Raycast style)
    var autocompleteHint: String? {
        // Only show hint when input starts with "/" and we have matching commands
        guard inputText.hasPrefix("/"), !filteredCommands.isEmpty else { return nil }

        let query = String(inputText.dropFirst()) // Remove "/"
        let firstMatch = filteredCommands[selectedCommandIndex]

        // Return the full command name for hint
        return "/\(firstMatch.name)"
    }

    /// The portion of hint that should be shown as completion (gray text after input)
    var autocompleteCompletion: String? {
        guard let hint = autocompleteHint else { return nil }

        // If input is shorter than hint, return the remaining part
        if inputText.count < hint.count && hint.lowercased().hasPrefix(inputText.lowercased()) {
            return String(hint.dropFirst(inputText.count))
        }
        return nil
    }

    var inputAreaView: some View {
        HStack(spacing: AuroraSpacing.space3) {
            // Input field with inline autocomplete hint
            ZStack(alignment: .leading) {
                // Autocomplete hint (gray completion text)
                if let completion = autocompleteCompletion {
                    HStack(spacing: 0) {
                        // Invisible spacer for the typed text width
                        Text(inputText)
                            .font(.system(size: 17, weight: .regular))
                            .opacity(0)

                        // Gray completion hint
                        Text(completion)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(Color.Aurora.textMuted)
                    }
                }

                // Actual input field
                CommandBarTextField(
                    text: $inputText,
                    placeholder: placeholderText,
                    isDisabled: mode == .running,
                    onSubmit: handleSubmit,
                    onCmdDelete: {
                        if mode.isHistory {
                            handleCmdDelete()
                        }
                    },
                    onCmdN: handleCmdN,
                    onEscape: handleEscape
                )
                .focused($isInputFocused)
                .accessibilityLabel("Command input")
                .accessibilityHint("Type a command or question, then press Return to submit")
            }

            // Tab hint when autocomplete is available
            if autocompleteCompletion != nil {
                Text(L10n.CommandBar.tab)
                    .font(.Aurora.micro.weight(.medium))
                    .foregroundColor(Color.Aurora.textMuted)
                    .padding(.horizontal, AuroraSpacing.space2)
                    .padding(.vertical, AuroraSpacing.space1)
                    .background(
                        RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                            .fill(Color.Aurora.glassOverlay.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                            .strokeBorder(Color.Aurora.glassOverlay.opacity(0.1), lineWidth: 0.5)
                    )
            }

            // Action button
            actionButton
        }
        .frame(height: 54)
        .padding(.horizontal, AuroraSpacing.space6)
    }

    var placeholderText: String {
        switch mode {
        case .command:
            return L10n.CommandBar.typeCommand
        case .history:
            return L10n.CommandBar.searchSessions
        case .running, .completed, .error:
            return L10n.CommandBar.followUp
        default:
            return L10n.CommandBar.placeholder
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    var actionButton: some View {
        if !configManager.hasAPIKey {
            Button(action: {
                appState.hideCommandBar()
                SettingsWindowController.shared.show(tab: .model)
            }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.Aurora.warning)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("API key required")
            .accessibilityHint("Opens settings to configure API key")
        } else if case .error = mode {
            Button(action: { mode = .idle }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.Aurora.error)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry")
            .accessibilityHint("Clears the error and allows you to try again")
        } else {
            let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isCommandInput = inputText.hasPrefix("/")
            if canSend && !isCommandInput {
                Button(action: handleSubmit) {
                    Image(systemName: "return")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.Aurora.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Submit")
                .accessibilityHint("Sends your command to the AI assistant")
            } else {
                EmptyView()
            }
        }
    }

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
        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.08))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.18))
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

            if let contextTokens = appState.currentContextTokens {
                Circle()
                    .fill(Color.Aurora.textMuted.opacity(0.4))
                    .frame(width: 3, height: 3)

                Text("CTX \(TokenUsageFormatter.formatTokens(contextTokens))")
                    .font(.Aurora.micro.weight(.medium))
                    .foregroundColor(Color.Aurora.textMuted)
            }
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
            // Always white — it's a bright highlight at the glass edge
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(isDark ? 0.15 : 0.5), Color.clear],
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
            Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.15)
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
            // Layer 2: Tint overlay — more opaque in light mode for text contrast
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .fill(Color.Aurora.background.opacity(isDark ? 0.45 : 0.65))
        }
    }
}
