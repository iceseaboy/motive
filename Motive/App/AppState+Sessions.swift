//
//  AppState+Sessions.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import Combine
import SwiftData
import SwiftUI

extension AppState {
    func submitIntent(_ text: String) {
        submitIntent(text, workingDirectory: nil)
    }

    func submitIntent(_ text: String, workingDirectory: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Check provider configuration
        if let configError = configManager.providerConfigurationError {
            lastErrorMessage = configError
            // Update CloudKit if this is a remote command
            if let commandId = currentRemoteCommandId {
                cloudKitManager.failCommand(commandId: commandId, error: configError)
                currentRemoteCommandId = nil
            }
            return
        }

        lastErrorMessage = nil
        // Immediately update status bar so user sees feedback
        menuBarState = .executing
        sessionStatus = .running
        updateStatusBar()
        // Start UI-level session timeout
        resetSessionTimeout()
        // Don't hide CommandBar - it will switch to running mode
        // Only ESC or focus loss should hide it
        startNewSession(intent: trimmed)

        // Add user message to conversation
        let userMessage = ConversationMessage(
            type: .user,
            content: trimmed
        )
        messages.append(userMessage)

        // Use provided working directory or configured project directory
        let cwd = workingDirectory ?? configManager.currentProjectURL.path
        Task { await bridge.submitIntent(text: trimmed, cwd: cwd) }
    }

    func sendFollowUp(_ text: String) {
        // Use resumeSession to continue the current session properly
        resumeSession(with: text)
    }

    /// Interrupt the current running session (like Ctrl+C)
    func interruptSession() {
        guard sessionStatus == .running else { return }

        Task {
            await bridge.interrupt()
        }

        sessionTimeoutTask?.cancel()
        sessionTimeoutTask = nil
        sessionStatus = .interrupted
        menuBarState = .idle
        currentToolName = nil

        // Mark all running tool messages as failed (interrupted)
        for i in messages.indices where messages[i].type == .tool && messages[i].status == .running {
            messages[i] = messages[i].withStatus(.failed)
        }

        // Add system message
        let systemMessage = ConversationMessage(
            type: .system,
            content: "Session interrupted by user"
        )
        messages.append(systemMessage)
    }

    /// Get all sessions sorted by date (newest first)
    func getAllSessions() -> [Session] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Seed recent projects list from stored sessions
    func seedRecentProjectsFromSessions() {
        let sessions = getAllSessions()
        for session in sessions {
            if !session.projectPath.isEmpty {
                configManager.recordRecentProject(session.projectPath)
            }
        }
    }

    /// Switch to a different session
    func switchToSession(_ session: Session) {
        currentSession = session
        sessionStatus = SessionStatus(rawValue: session.status) ?? .completed

        // Sync OpenCodeBridge session ID
        Task { await bridge.setSessionId(session.openCodeSessionId) }

        // Restore project directory for this session
        restoreProjectDirectory(for: session)

        // Rebuild messages from logs
        messages = [ConversationMessage(type: .user, content: session.intent, timestamp: session.createdAt)]
        replaySessionLogs(session.logs)
    }

    /// Restore the project directory to match the session's original cwd.
    private func restoreProjectDirectory(for session: Session) {
        guard !session.projectPath.isEmpty else { return }
        let defaultPath = ConfigManager.defaultProjectDirectory.path
        if session.projectPath == defaultPath {
            _ = configManager.setProjectDirectory(nil)
        } else {
            _ = configManager.setProjectDirectory(session.projectPath)
        }
    }

    /// Replay historical logs into the messages array with proper merging.
    private func replaySessionLogs(_ logs: [LogEntry]) {
        for log in logs {
            let event = OpenCodeEvent(rawJson: log.rawJson)

            // Handle TodoWrite during replay
            if event.kind == .tool, let toolName = event.toolName, toolName.isTodoWriteTool {
                replayTodoEvent(event)
                continue
            }

            // Handle AskUserQuestion during replay — show as "Question" with response
            if event.kind == .tool, isAskUserQuestionTool(event.toolName) {
                replayAskUserQuestionEvent(event)
                continue
            }

            guard let message = event.toMessage() else { continue }

            // Skip redundant completion messages
            if message.type == .system && isCompletionText(message.content) {
                let alreadyHas = messages.contains { $0.type == .system && $0.content.lowercased() == "completed" }
                if alreadyHas || message.content.lowercased() != "completed" { continue }
            }

            // All historical tool messages are completed; merge by toolCallId
            if message.type == .tool {
                let completed = message.withStatus(.completed)
                if let callId = completed.toolCallId,
                   let idx = messages.lastIndex(where: { $0.type == .tool && $0.toolCallId == callId }) {
                    messages[idx] = messages[idx].mergingToolData(from: completed)
                } else {
                    messages.append(completed)
                }
            } else {
                messages.append(message)
            }
        }
    }

    /// Replay a single TodoWrite event into the messages array.
    private func replayTodoEvent(_ event: OpenCodeEvent) {
        let todoItems = parseTodoItemsForReplay(from: event)
        guard !todoItems.isEmpty else { return }
        let summary = todoSummary(todoItems)
        if let idx = messages.lastIndex(where: { $0.type == .todo }) {
            messages[idx] = messages[idx].withTodos(todoItems, summary: summary)
        } else {
            messages.append(ConversationMessage(
                type: .todo, content: summary,
                status: .completed, todoItems: todoItems
            ))
        }
    }

    /// Start a new empty session (for "New Chat" button)
    func startNewEmptySession() {
        currentSession = nil
        messages = []
        sessionStatus = .idle
        menuBarState = .idle
        currentToolName = nil

        // Clear OpenCodeBridge session ID for fresh start
        Task { await bridge.setSessionId(nil) }
        // @Observable handles change tracking automatically
    }

    /// Clear current session messages without deleting
    func clearCurrentSession() {
        messages = []
        currentSession = nil
        sessionStatus = .idle
        menuBarState = .idle
        currentToolName = nil

        Task { await bridge.setSessionId(nil) }
        // @Observable handles change tracking automatically
    }

    /// Delete a session from storage
    func deleteSession(_ session: Session) {
        guard let modelContext else { return }

        // If deleting current session, clear it first
        if currentSession?.id == session.id {
            clearCurrentSession()
        }

        modelContext.delete(session)
        try? modelContext.save()
        
        // Trigger list refresh so CommandBarView updates
        sessionListRefreshTrigger += 1
        // @Observable handles change tracking automatically
    }

    /// Delete a session by id (robust against stale references)
    func deleteSession(id: UUID) {
        guard let modelContext else { return }

        if currentSession?.id == id {
            clearCurrentSession()
        }

        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.id == id }
        )
        if let session = try? modelContext.fetch(descriptor).first {
            modelContext.delete(session)
            try? modelContext.save()
            
            // Trigger list refresh so CommandBarView updates
            sessionListRefreshTrigger += 1
            // @Observable handles change tracking automatically
        }
    }

    /// Switch to a different project directory
    /// This clears the current session to avoid context confusion
    /// - Parameter path: The directory path, or nil to use default ~/.motive
    /// - Returns: true if the directory was set successfully
    @discardableResult
    func switchProjectDirectory(_ path: String?) -> Bool {
        // Clear current session first to avoid mixing contexts
        if sessionStatus == .running {
            interruptSession()
        }
        clearCurrentSession()

        // Set the new directory
        let success = configManager.setProjectDirectory(path)
        // @Observable handles change tracking automatically

        return success
    }

    /// Open a folder picker dialog to select project directory
    func showProjectPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory"
        panel.prompt = "Select"

        // Hide command bar during picker
        hideCommandBar()

        panel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = panel.url {
                self.switchProjectDirectory(url.path)
            }
            // Reshow command bar after picker closes
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                self.showCommandBar()
            }
        }
    }

    /// Resume a session with a follow-up message
    func resumeSession(with text: String) {
        guard let session = currentSession,
              let openCodeSessionId = session.openCodeSessionId else {
            // No session to resume, start a new one
            submitIntent(text)
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        sessionStatus = .running
        menuBarState = .executing
        session.status = "running"

        // Add user message
        let userMessage = ConversationMessage(
            type: .user,
            content: trimmed
        )
        messages.append(userMessage)

        // Use the project directory that this session was created with
        let cwd = session.projectPath.isEmpty ? configManager.currentProjectURL.path : session.projectPath
        Task { await bridge.resumeSession(sessionId: openCodeSessionId, text: trimmed, cwd: cwd) }
    }

    /// Replay a single AskUserQuestion event into the messages array.
    private func replayAskUserQuestionEvent(_ event: OpenCodeEvent) {
        let inputDict: [String: Any]? = event.toolInputDict ?? extractAskUserQuestionInput(from: event.rawJson)
        let questionText: String
        if let q = inputDict?["question"] as? String {
            questionText = q
        } else if let questions = inputDict?["questions"] as? [[String: Any]],
                  let firstQ = questions.first?["question"] as? String {
            questionText = firstQ
        } else {
            questionText = "Question"
        }

        // Merge by toolCallId if a question message already exists
        if let callId = event.toolCallId,
           let idx = messages.lastIndex(where: { $0.type == .tool && $0.toolCallId == callId }) {
            let existing = messages[idx]
            messages[idx] = ConversationMessage(
                id: existing.id, type: .tool,
                content: existing.content, timestamp: existing.timestamp,
                toolName: "Question", toolInput: existing.toolInput,
                toolOutput: event.toolOutput ?? existing.toolOutput,
                toolCallId: existing.toolCallId,
                status: .completed
            )
        } else {
            messages.append(ConversationMessage(
                type: .tool,
                content: questionText,
                toolName: "Question",
                toolInput: questionText,
                toolOutput: event.toolOutput,
                toolCallId: event.toolCallId,
                status: .completed
            ))
        }
    }

    /// Parse todo items during session replay (simplified version for historical data)
    private func parseTodoItemsForReplay(from event: OpenCodeEvent) -> [TodoItem] {
        if let inputDict = event.toolInputDict,
           let todosArray = inputDict["todos"] as? [[String: Any]] {
            return todosArray.compactMap { TodoItem(from: $0) }
        }
        guard let data = event.rawJson.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let part = object["part"] as? [String: Any] else {
            return []
        }
        // Try tool_call format
        if let input = part["input"] as? [String: Any],
           let todosArray = input["todos"] as? [[String: Any]] {
            return todosArray.compactMap { TodoItem(from: $0) }
        }
        // Try tool_use format
        if let state = part["state"] as? [String: Any],
           let input = state["input"] as? [String: Any],
           let todosArray = input["todos"] as? [[String: Any]] {
            return todosArray.compactMap { TodoItem(from: $0) }
        }
        return []
    }

    private func startNewSession(intent: String) {
        messages = []
        menuBarState = .executing
        sessionStatus = .running
        currentToolName = nil

        // Clear OpenCodeBridge session ID for fresh start
        Task { await bridge.setSessionId(nil) }

        let sessionProjectPath = configManager.currentProjectURL.path
        let session = Session(intent: intent, projectPath: sessionProjectPath)
        currentSession = session
        modelContext?.insert(session)
    }
}
