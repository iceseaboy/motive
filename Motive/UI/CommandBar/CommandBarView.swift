//
//  CommandBarView.swift
//  Motive
//
//  Aurora Design System - CommandBar (Spotlight Enhanced)
//  State machine driven transforming command center
//

import AppKit
import SwiftUI

// MARK: - CommandBar State

enum CommandBarMode: Equatable {
    case idle                           // Initial state, ready for input
    case input                          // User is typing intent
    case command(fromSession: Bool)     // User typed /, showing command suggestions
    case histories(fromSession: Bool)   // Showing /histories list
    case running                        // Task is running
    case completed                      // Task completed, showing summary
    case error(String)                  // Error occurred
    
    var showsFooter: Bool { true }
    
    var isCommand: Bool {
        if case .command = self { return true }
        return false
    }
    
    var isHistories: Bool {
        if case .histories = self { return true }
        return false
    }
    
    /// Whether this mode was triggered from a session state (completed/running)
    var isFromSession: Bool {
        switch self {
        case .command(let fromSession), .histories(let fromSession):
            return fromSession
        default:
            return false
        }
    }
    
    var dynamicHeight: CGFloat {
        // Layout: [status bar ~50] + input(52) + [list] + footer(40) + padding
        switch self {
        case .idle, .input: 
            return 100   // input + footer + padding
        case .command(let fromSession): 
            // Same height as histories for consistency
            return fromSession ? 450 : 400   // status(50) + input + footer + list(280) + padding
        case .histories(let fromSession): 
            return fromSession ? 450 : 400   // status(50) + input + footer + list(280) + padding
        case .running, .completed, .error: 
            return 160   // status + input + footer + padding
        }
    }
    
    var modeName: String {
        switch self {
        case .idle: return "idle"
        case .input: return "input"
        case .command: return "command"
        case .histories: return "histories"
        case .running: return "running"
        case .completed: return "completed"
        case .error: return "error"
        }
    }
}

// MARK: - Command Definition

struct CommandDefinition: Identifiable {
    let id: String
    let name: String
    let shortcut: String?
    let icon: String
    let description: String
    
    static let allCommands: [CommandDefinition] = [
        CommandDefinition(id: "histories", name: "histories", shortcut: "h", icon: "clock.arrow.circlepath", description: "View session history"),
        CommandDefinition(id: "settings", name: "settings", shortcut: "s", icon: "gearshape", description: "Open settings"),
        CommandDefinition(id: "new", name: "new", shortcut: "n", icon: "plus.circle", description: "Start new session"),
        CommandDefinition(id: "clear", name: "clear", shortcut: nil, icon: "trash", description: "Clear current conversation"),
    ]
    
    static func matching(_ query: String) -> [CommandDefinition] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return allCommands }
        return allCommands.filter { cmd in
            cmd.name.hasPrefix(q) || cmd.shortcut == q
        }
    }
}

// MARK: - Root View

struct CommandBarRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @State private var didAttachContext = false

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                guard !didAttachContext else { return }
                didAttachContext = true
                appState.attachModelContext(modelContext)
            }
    }
}

// MARK: - Main CommandBar View

struct CommandBarView: View {
    @EnvironmentObject private var configManager: ConfigManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    @State private var inputText: String = ""
    @State private var mode: CommandBarMode = .idle
    @State private var showEntrance: Bool = false
    @State private var selectedCommandIndex: Int = 0
    @State private var selectedHistoryIndex: Int = 0
    @State private var historySessions: [Session] = []
    @State private var showDeleteConfirmation: Bool = false
    @FocusState private var isInputFocused: Bool
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Filtered commands based on input
    private var filteredCommands: [CommandDefinition] {
        let query = inputText.hasPrefix("/") ? String(inputText.dropFirst()) : ""
        return CommandDefinition.matching(query)
    }
    
    var body: some View {
        mainContent
            .onAppear(perform: handleOnAppear)
            .onChange(of: appState.commandBarResetTrigger) { _, _ in recenterAndFocus() }
            .onChange(of: inputText) { _, newValue in handleInputChange(newValue) }
            .onChange(of: mode) { oldMode, newMode in handleModeChange(from: oldMode, to: newMode) }
            .onChange(of: appState.sessionStatus) { _, newStatus in handleSessionStatusChange(newStatus) }
            .onExitCommand { handleEscape() }
            .onKeyPress(.upArrow, action: { handleUpArrow(); return .handled })
            .onKeyPress(.downArrow, action: { handleDownArrow(); return .handled })
            .onKeyPress(.tab, action: { handleTab(); return .handled })
            .onKeyPress(keys: [.init("n")], phases: .down) { press in
                if press.modifiers.contains(.command) {
                    handleCmdN()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.delete, phases: .down) { press in
                if press.modifiers.contains(.command) {
                    handleCmdDelete()
                    return .handled
                }
                return .ignored
            }
            .confirmationDialog("Delete this session?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: confirmDeleteSession)
                Button("Cancel", role: .cancel) {}
            }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            if showsAboveContent {
                aboveInputContent
                Divider().background(Color.Aurora.border)
            }
            inputAreaView
            if showsBelowContent {
                Divider().background(Color.Aurora.border)
                belowInputContent
            } else {
                // Only use spacer when no list content
                Spacer(minLength: 0)
            }
            footerView
        }
        .frame(width: 600, height: mode.dynamicHeight)
        .background(commandBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous))
        .overlay(borderOverlay)  // Border on top of everything
        .scaleEffect(showEntrance ? 1.0 : 0.96)
        .opacity(showEntrance ? 1.0 : 0)
    }
    
    private func handleOnAppear() {
        withAnimation(.auroraSpring) {
            showEntrance = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isInputFocused = true
        }
    }
    
    private func confirmDeleteSession() {
        guard selectedHistoryIndex < filteredHistorySessions.count else { return }
        let session = filteredHistorySessions[selectedHistoryIndex]
        appState.deleteSession(session)
        historySessions = appState.getAllSessions()
        if selectedHistoryIndex >= filteredHistorySessions.count {
            selectedHistoryIndex = max(0, filteredHistorySessions.count - 1)
        }
    }
    
    // MARK: - Keyboard Navigation
    
    private func handleUpArrow() {
        if mode.isCommand {
            if selectedCommandIndex > 0 {
                selectedCommandIndex -= 1
            }
        } else if mode.isHistories {
            if selectedHistoryIndex > 0 {
                selectedHistoryIndex -= 1
            }
        }
    }
    
    private func handleDownArrow() {
        if mode.isCommand {
            if selectedCommandIndex < filteredCommands.count - 1 {
                selectedCommandIndex += 1
            }
        } else if mode.isHistories {
            if selectedHistoryIndex < filteredHistorySessions.count - 1 {
                selectedHistoryIndex += 1
            }
        }
    }
    
    private func handleTab() {
        // Tab completion for commands
        if mode.isCommand && !filteredCommands.isEmpty {
            let command = filteredCommands[selectedCommandIndex]
            inputText = "/\(command.name)"
        }
    }
    
    private func handleCmdN() {
        // Cmd+N to create new session (works in any mode)
        appState.startNewEmptySession()
        inputText = ""
        mode = .completed  // Show "New Task" status
    }
    
    private func handleCmdDelete() {
        // Cmd+Delete to delete selected session in histories mode
        if mode.isHistories && selectedHistoryIndex < filteredHistorySessions.count {
            showDeleteConfirmation = true
        }
    }
    
    // Content ABOVE input (session status)
    private var showsAboveContent: Bool {
        switch mode {
        case .running, .completed, .error:
            return true
        case .command(let fromSession), .histories(let fromSession):
            // Keep status visible when command/histories triggered from session
            return fromSession
        default:
            return false
        }
    }
    
    // Content BELOW input (lists)
    private var showsBelowContent: Bool {
        mode.isCommand || mode.isHistories
    }
    
    // MARK: - Above Input Content (Session Status)
    
    @ViewBuilder
    private var aboveInputContent: some View {
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
            case .histories(let fromSession) where fromSession:
                // Show completed status when histories triggered from session
                completedSummaryView
            default:
                EmptyView()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    // MARK: - Below Input Content (Lists)
    
    @ViewBuilder
    private var belowInputContent: some View {
        Group {
            if mode.isCommand {
                commandListView
            } else if mode.isHistories {
                historiesListView
            } else {
                EmptyView()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
    
    // MARK: - Histories List (below input)
    
    private var historiesListView: some View {
        CommandBarHistoriesView(
            sessions: filteredHistorySessions,
            selectedIndex: $selectedHistoryIndex,
            onSelect: selectHistorySession,
            onDelete: deleteHistorySession
        )
    }
    
    private var filteredHistorySessions: [Session] {
        if inputText.isEmpty {
            return Array(historySessions.prefix(20))
        }
        return historySessions.filter { $0.intent.localizedCaseInsensitiveContains(inputText) }.prefix(20).map { $0 }
    }
    
    private func loadHistorySessions() {
        historySessions = appState.getAllSessions()
        selectedHistoryIndex = 0
    }
    
    private func selectHistorySession(_ session: Session) {
        appState.switchToSession(session)
        inputText = ""
        // Stay in CommandBar, switch to appropriate mode based on session status
        if appState.sessionStatus == .running {
            mode = .running
        } else {
            mode = .completed
        }
    }
    
    private func deleteHistorySession(at index: Int) {
        guard index < filteredHistorySessions.count else { return }
        let session = filteredHistorySessions[index]
        appState.deleteSession(session)
        historySessions = appState.getAllSessions()
        if selectedHistoryIndex >= filteredHistorySessions.count {
            selectedHistoryIndex = max(0, filteredHistorySessions.count - 1)
        }
    }
    
    // MARK: - Running Status (above input)
    
    private var runningStatusView: some View {
        HStack(spacing: AuroraSpacing.space3) {
            AuroraPulsingDot()
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Running")
                    .font(.Aurora.caption.weight(.semibold))
                    .foregroundColor(Color.Aurora.textPrimary)
                
                Text(appState.currentToolName?.simplifiedToolName ?? "Processing...")
                    .font(.Aurora.caption)
                    .foregroundColor(Color.Aurora.textMuted)
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
            
            // Open drawer button
            Button(action: {
                appState.toggleDrawer()
                appState.hideCommandBar()
            }) {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.Aurora.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Color.Aurora.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AuroraSpacing.space5)
        .padding(.vertical, AuroraSpacing.space3)
    }
    
    // MARK: - Completed Summary (above input)
    
    private var completedSummaryView: some View {
        let isNewSession = appState.messages.isEmpty
        let statusTitle = isNewSession ? "New Task" : "Completed"
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
                    Text("Type your request below")
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
                    Text("Details")
                        .font(.Aurora.caption)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(Color.Aurora.textSecondary)
                .padding(.horizontal, AuroraSpacing.space3)
                .padding(.vertical, AuroraSpacing.space2)
                .background(Color.Aurora.surface)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AuroraSpacing.space5)
        .padding(.vertical, AuroraSpacing.space3)
    }
    
    // MARK: - Error Status (above input)
    
    private func errorStatusView(message: String) -> some View {
        HStack(spacing: AuroraSpacing.space3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(Color.Aurora.error)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Error")
                    .font(.Aurora.caption.weight(.semibold))
                    .foregroundColor(Color.Aurora.textPrimary)
                
                Text(message)
                    .font(.Aurora.caption)
                    .foregroundColor(Color.Aurora.textMuted)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: { mode = .idle }) {
                Text("Dismiss")
                    .font(.Aurora.caption)
                    .foregroundColor(Color.Aurora.textSecondary)
                    .padding(.horizontal, AuroraSpacing.space3)
                    .padding(.vertical, AuroraSpacing.space2)
                    .background(Color.Aurora.surface)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AuroraSpacing.space5)
        .padding(.vertical, AuroraSpacing.space3)
    }
    
    // MARK: - Input Area (Always Visible - No icons, status shown above)
    
    private var inputAreaView: some View {
        HStack(spacing: AuroraSpacing.space3) {
            // Input field - no icon prefix
            TextField("", text: $inputText, prompt: Text(placeholderText)
                .foregroundColor(Color.Aurora.textMuted))
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(Color.Aurora.textPrimary)
                .focused($isInputFocused)
                .onSubmit { handleSubmit() }
                .disabled(mode == .running)
            
            // Action button
            actionButton
        }
        .frame(height: 52)
        .padding(.horizontal, AuroraSpacing.space5)
    }
    
    private var placeholderText: String {
        switch mode {
        case .command:
            return "Type a command..."
        case .histories:
            return "Search sessions..."
        case .running, .completed, .error:
            return "Follow up..."  // Status shown above, not in placeholder
        default:
            return L10n.CommandBar.placeholder
        }
    }
    
    // MARK: - Action Button
    
    @ViewBuilder
    private var actionButton: some View {
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
        } else if case .error = mode {
            Button(action: { mode = .idle }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.Aurora.error)
            }
            .buttonStyle(.plain)
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
            } else {
                EmptyView()
            }
        }
    }
    
    // MARK: - Command List View (Below Input)
    
    private var commandListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                        CommandListItem(
                            command: command,
                            isSelected: index == selectedCommandIndex
                        ) {
                            executeCommand(command)
                        }
                        .id(index)
                    }
                }
                .padding(.vertical, AuroraSpacing.space2)
                .padding(.horizontal, AuroraSpacing.space3)
            }
            .onChange(of: selectedCommandIndex) { _, newIndex in
                withAnimation(.auroraFast) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(maxHeight: .infinity)  // Fill available space
    }
    
    // MARK: - Footer View
    
    private var footerView: some View {
        HStack(spacing: 0) {
            // Left side: status or hints
            leftFooterContent
            
            Spacer()
            
            // Right side: keyboard shortcuts
            rightFooterContent
        }
        .frame(height: 40)
        .padding(.horizontal, AuroraSpacing.space5)
        .background(Color.Aurora.backgroundDeep.opacity(isDark ? 0.5 : 0.3))
    }
    
    @ViewBuilder
    private var leftFooterContent: some View {
        // Status is shown in above content area, not duplicated in footer
        EmptyView()
    }
    
    @ViewBuilder
    private var rightFooterContent: some View {
        HStack(spacing: AuroraSpacing.space4) {
            if mode.isCommand {
                AuroraShortcutBadge(keys: ["↵"], label: "Select")
                AuroraShortcutBadge(keys: ["tab"], label: "Complete")
                AuroraShortcutBadge(keys: ["↑↓"], label: "Navigate")
                AuroraShortcutBadge(keys: ["esc"], label: "Back")
            } else if mode.isHistories {
                AuroraShortcutBadge(keys: ["↵"], label: "Open")
                AuroraShortcutBadge(keys: ["⌘", "⌫"], label: "Delete")
                AuroraShortcutBadge(keys: ["↑↓"], label: "Navigate")
                AuroraShortcutBadge(keys: ["esc"], label: "Back")
            } else {
                switch mode {
                case .idle, .input:
                    AuroraShortcutBadge(keys: ["↵"], label: L10n.CommandBar.run)
                    AuroraShortcutBadge(keys: ["⌘", "N"], label: "New")
                    AuroraShortcutBadge(keys: ["/"], label: "Commands")
                    AuroraShortcutBadge(keys: ["esc"], label: L10n.CommandBar.close)
                case .running:
                    AuroraShortcutBadge(keys: ["⌘", "N"], label: "New")
                    AuroraShortcutBadge(keys: ["esc"], label: "Stop")
                    AuroraShortcutBadge(keys: ["⌘", "D"], label: "Drawer")
                case .completed:
                    AuroraShortcutBadge(keys: ["↵"], label: "Send")
                    AuroraShortcutBadge(keys: ["⌘", "N"], label: "New")
                    AuroraShortcutBadge(keys: ["/"], label: "Commands")
                    AuroraShortcutBadge(keys: ["esc"], label: "Close")
                case .error:
                    AuroraShortcutBadge(keys: ["↵"], label: "Retry")
                    AuroraShortcutBadge(keys: ["/"], label: "Commands")
                    AuroraShortcutBadge(keys: ["esc"], label: "Close")
                default:
                    EmptyView()
                }
            }
        }
    }
    
    // MARK: - Border Overlay
    
    @ViewBuilder
    private var borderOverlay: some View {
        // Use strokeBorder instead of stroke to keep the line fully inside the shape
        // This prevents the outer clipShape from cutting off half the border
        switch mode {
        case .running:
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .strokeBorder(Color.Aurora.primary.opacity(0.8), lineWidth: 1.0)
                .modifier(PulsingBorderModifier())
        case .completed:
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .strokeBorder(Color.Aurora.accent.opacity(0.5), lineWidth: 1.0)
        case .error:
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .strokeBorder(Color.Aurora.error.opacity(0.6), lineWidth: 1.0)
        default:
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .strokeBorder(Color.Aurora.accent.opacity(0.4), lineWidth: 1.0)
        }
    }
    
    // MARK: - Background
    
    private var commandBarBackground: some View {
        ZStack {
            VisualEffectView(
                material: .menu,
                blendingMode: .behindWindow,
                state: .active,
                cornerRadius: AuroraRadius.xl,
                masksToBounds: true
            )
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .fill(Color.Aurora.background.opacity(0.85))
        }
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous))
    }
    
    // MARK: - State Handlers
    
    private func handleInputChange(_ newValue: String) {
        // In histories mode, input is used for filtering, don't change mode
        if mode.isHistories {
            return
        }
        
        // In running mode, ignore input changes
        if mode == .running {
            return
        }
        
        // Track if we're coming from a session state
        let isInSession = mode == .completed || mode == .running || mode.isFromSession
        
        // Allow "/" command trigger from any state (including completed/error)
        if newValue.hasPrefix("/") {
            if !mode.isCommand {
                mode = .command(fromSession: isInSession || !appState.messages.isEmpty)
                selectedCommandIndex = 0
            }
        } else if mode.isCommand && !newValue.hasPrefix("/") {
            // Exiting command mode - return to previous session state or idle
            if mode.isFromSession || !appState.messages.isEmpty {
                mode = .completed
            } else {
                mode = newValue.isEmpty ? .idle : .input
            }
        } else if case .completed = mode {
            // In completed, typing non-command text stays in current mode (for follow-up)
            return
        } else if case .error = mode {
            // In error, typing non-command text stays in current mode (for follow-up)
            return
        } else if !newValue.isEmpty {
            mode = .input
        } else {
            mode = .idle
        }
    }
    
    private func handleModeChange(from oldMode: CommandBarMode, to newMode: CommandBarMode) {
        // Update window height for new mode
        appState.updateCommandBarHeight(for: newMode.modeName)
        
        // Load data when entering specific modes
        if newMode.isHistories {
            loadHistorySessions()
        }
        
        // Keep input focused in all modes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isInputFocused = true
        }
    }
    
    private func handleSessionStatusChange(_ status: AppState.SessionStatus) {
        // Don't change mode if user is browsing commands/histories
        if mode.isCommand || mode.isHistories {
            return
        }
        
        switch status {
        case .running:
            mode = .running
        case .completed:
            mode = .completed
        case .failed:
            mode = .error(appState.lastErrorMessage ?? "An error occurred")
        case .idle, .interrupted:
            if mode == .running {
                mode = .idle
            }
        }
    }
    
    private func handleSubmit() {
        if mode.isCommand {
            executeSelectedCommand()
        } else if mode.isHistories {
            // Select the highlighted session
            if selectedHistoryIndex < filteredHistorySessions.count {
                selectHistorySession(filteredHistorySessions[selectedHistoryIndex])
            }
        } else if case .completed = mode {
            sendFollowUp()
        } else {
            submitIntent()
        }
    }
    
    private func handleEscape() {
        if mode.isCommand || mode.isHistories {
            // Return to previous mode (session or idle)
            if appState.sessionStatus == .running {
                mode = .running
            } else if mode.isFromSession || !appState.messages.isEmpty {
                mode = .completed
            } else {
                mode = .idle
            }
            inputText = ""
        } else {
            switch mode {
            case .running:
                // ESC during running = interrupt and hide
                appState.interruptSession()
                appState.hideCommandBar()
            case .completed, .error, .idle, .input:
                // ESC = hide CommandBar
                appState.hideCommandBar()
            default:
                appState.hideCommandBar()
            }
        }
    }
    
    private func submitIntent() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        appState.submitIntent(text)
        // Mode will change to .running via sessionStatus observer
        // CommandBar stays visible - only ESC or focus loss hides it
    }
    
    private func executeSelectedCommand() {
        guard selectedCommandIndex < filteredCommands.count else { return }
        executeCommand(filteredCommands[selectedCommandIndex])
    }
    
    private func executeCommand(_ command: CommandDefinition) {
        let wasFromSession = mode.isFromSession || !appState.messages.isEmpty
        switch command.id {
        case "histories":
            inputText = ""
            mode = .histories(fromSession: wasFromSession)
            selectedHistoryIndex = 0
        case "settings":
            inputText = ""
            appState.hideCommandBar()
            SettingsWindowController.shared.show(tab: .general)
        case "new":
            inputText = ""
            appState.startNewEmptySession()
            mode = .idle
        case "clear":
            inputText = ""
            appState.clearCurrentSession()
            mode = .idle
        default:
            break
        }
    }
    
    private func sendFollowUp() {
        // Use the main inputText for follow-up messages
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        appState.resumeSession(with: text)
        // CommandBar stays visible - mode will change to .running via sessionStatus observer
    }
    
    /// Re-center window and refocus input when CommandBar is shown
    /// Does NOT clear input - user may want to continue typing
    private func recenterAndFocus() {
        // Update window height to match current mode
        appState.updateCommandBarHeight(for: mode.modeName)
        
        // Refocus input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isInputFocused = true
        }
    }
}

// MARK: - Command List Item

private struct CommandListItem: View {
    let command: CommandDefinition
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AuroraSpacing.space3) {
                Image(systemName: command.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? Color.Aurora.accent : Color.Aurora.textSecondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AuroraSpacing.space2) {
                        Text("/\(command.name)")
                            .font(.Aurora.body.weight(.medium))
                            .foregroundColor(Color.Aurora.textPrimary)
                        
                        if let shortcut = command.shortcut {
                            Text("/\(shortcut)")
                                .font(.Aurora.caption)
                                .foregroundColor(Color.Aurora.textMuted)
                        }
                    }
                    
                    Text(command.description)
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textMuted)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.Aurora.textMuted)
                }
            }
            .padding(.horizontal, AuroraSpacing.space3)
            .padding(.vertical, AuroraSpacing.space2)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(isSelected ? Color.Aurora.accent.opacity(0.1) : (isHovering ? Color.Aurora.surfaceElevated : Color.clear))
            )
            .overlay(
                HStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.Aurora.auroraGradient)
                            .frame(width: 3)
                    }
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Aurora Action Pill

struct AuroraActionPill: View {
    let icon: String
    let label: String
    let style: Style
    let action: () -> Void
    
    @State private var isHovering = false
    @State private var isPressed = false
    
    enum Style {
        case primary, warning, error
        
        var gradientColors: [Color] {
            switch self {
            case .primary: return Color.Aurora.auroraGradientColors
            case .warning: return [Color.Aurora.warning, Color.Aurora.warning.opacity(0.8)]
            case .error: return [Color.Aurora.error, Color.Aurora.error.opacity(0.8)]
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AuroraSpacing.space2) {
                Text(label)
                    .font(.Aurora.caption.weight(.semibold))
                    .foregroundColor(.white)
                
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, AuroraSpacing.space4)
            .frame(height: 36)
            .background(
                LinearGradient(
                    colors: style.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: style.gradientColors.first?.opacity(0.3) ?? Color.clear, radius: isHovering ? 12 : 6, y: 3)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(.auroraSpringStiff, value: isHovering)
        .animation(.auroraSpringStiff, value: isPressed)
    }
}

// MARK: - Aurora Shortcut Badge

struct AuroraShortcutBadge: View {
    let keys: [String]
    let label: String
    
    var body: some View {
        HStack(spacing: AuroraSpacing.space1) {
            ForEach(keys, id: \.self) { key in
                Group {
                    if key == "↵" {
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.Aurora.textSecondary)
                            .frame(width: 16, height: 16)
                    } else {
                        Text(key)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(Color.Aurora.textSecondary)
                            .frame(minWidth: 16)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                        .fill(Color.Aurora.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                        .stroke(Color.Aurora.border, lineWidth: 0.5)
                )
            }
            
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(Color.Aurora.textSecondary)
        }
    }
}

// MARK: - Aurora Pulsing Dot

struct AuroraPulsingDot: View {
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.Aurora.primary.opacity(0.4))
                .frame(width: 12, height: 12)
                .scaleEffect(isPulsing ? 1.5 : 1)
                .opacity(isPulsing ? 0 : 0.6)
            
            Circle()
                .fill(Color.Aurora.primary)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Pulsing Border Modifier

private struct PulsingBorderModifier: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.6 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Menu Bar State Display Text

extension AppState.MenuBarState {
    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .reasoning: return "Thinking…"
        case .executing: return "Running…"
        }
    }
}
