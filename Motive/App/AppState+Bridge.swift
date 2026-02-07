//
//  AppState+Bridge.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Combine
import Foundation
import SwiftData

extension AppState {
    func restartAgent() {
        Task {
            await configureBridge()
            await bridge.restart()
        }
    }

    func configureBridge() async {
        // Get signed binary (will auto-import and sign if needed)
        let resolution = await configManager.getSignedBinaryURL()
        guard let binaryURL = resolution.url else {
            lastErrorMessage = resolution.error ?? "OpenCode binary not found. Check Settings."
            menuBarState = .idle
            return
        }
        let config = OpenCodeBridge.Configuration(
            binaryURL: binaryURL,
            environment: configManager.makeEnvironment(),
            model: configManager.getModelString(),
            debugMode: configManager.debugMode
        )
        await bridge.updateConfiguration(config)

        // Sync browser agent API configuration
        BrowserUseBridge.shared.configureAgentAPIKey(
            envName: configManager.browserAgentProvider.envKeyName,
            apiKey: configManager.browserAgentAPIKey,
            baseUrlEnvName: configManager.browserAgentProvider.baseUrlEnvName,
            baseUrl: configManager.browserAgentBaseUrl
        )
    }

    /// Reset the UI-level session timeout whenever we receive an event
    func resetSessionTimeout() {
        sessionTimeoutTask?.cancel()
        
        guard sessionStatus == .running else { return }
        
        sessionTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.sessionTimeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            // Still running after timeout — warn the user
            if sessionStatus == .running {
                Log.debug("⚠️ Session timeout: no events for \(Int(Self.sessionTimeoutSeconds))s while still running")
                lastErrorMessage = "No response from OpenCode for \(Int(Self.sessionTimeoutSeconds)) seconds. The process may be stalled. You can interrupt or wait."
                statusBarController?.showError()
            }
        }
    }

    func handle(event: OpenCodeEvent) {
        // Reset session timeout on every event
        resetSessionTimeout()
        
        // Update UI state based on event kind
        switch event.kind {
        case .thought:
            menuBarState = .reasoning
            currentToolName = nil
            currentToolInput = nil
            // Update CloudKit for remote commands
            updateRemoteCommandStatus(toolName: "Thinking...")

        case .call, .tool:
            menuBarState = .executing
            currentToolName = event.toolName ?? "Processing"
            currentToolInput = event.toolInput  // Store tool input immediately

            // Intercept AskUserQuestion tool calls
            if isAskUserQuestionTool(event.toolName) {
                Log.debug("AskUserQuestion event: kind=\(event.kind.rawValue) hasOutput=\(event.toolOutput != nil) callId=\(event.toolCallId ?? "nil") pendingQ=\(pendingQuestionMessageId?.uuidString.prefix(8) ?? "nil")")

                // tool_use with output AND an existing pending question = already answered
                if event.toolOutput != nil, pendingQuestionMessageId != nil {
                    updateQuestionMessage(response: event.toolOutput ?? "")
                    Log.debug("AskUserQuestion: merged tool_use output with existing question")
                    logEvent(event)
                    return
                }

                // tool_use with output but NO pending question = combined event,
                // create a completed question message directly so it appears in conversation
                if event.toolOutput != nil, pendingQuestionMessageId == nil {
                    if let callId = event.toolCallId,
                       let idx = messages.lastIndex(where: { $0.type == .tool && $0.toolCallId == callId }) {
                        // Merge by callId with existing message
                        let existing = messages[idx]
                        messages[idx] = ConversationMessage(
                            id: existing.id, type: .tool,
                            content: existing.content, timestamp: existing.timestamp,
                            toolName: existing.toolName, toolInput: existing.toolInput,
                            toolOutput: event.toolOutput, toolCallId: existing.toolCallId,
                            status: .completed
                        )
                        Log.debug("AskUserQuestion: merged by callId (no pending question)")
                    } else {
                        // No existing message at all — create a completed question record
                        let inputDict = event.toolInputDict ?? extractAskUserQuestionInput(from: event.rawJson)
                        let questionText = inputDict?["question"] as? String
                            ?? (inputDict?["questions"] as? [[String: Any]])?.first?["question"] as? String
                            ?? "Question"
                        messages.append(ConversationMessage(
                            type: .tool,
                            content: questionText,
                            toolName: "Question",
                            toolInput: questionText,
                            toolOutput: event.toolOutput,
                            toolCallId: event.toolCallId,
                            status: .completed
                        ))
                        Log.debug("AskUserQuestion: created completed question message from tool_use (no prior tool_call)")
                    }
                    logEvent(event)
                    return
                }

                // tool_call without output = new question, show modal
                if let inputDict = event.toolInputDict ?? extractAskUserQuestionInput(from: event.rawJson) {
                    handleAskUserQuestion(input: inputDict, event: event)
                    logEvent(event)
                    return
                }
                Log.debug("AskUserQuestion: matched tool name but no input payload")
            }
            // Update CloudKit for remote commands
            updateRemoteCommandStatus(toolName: event.toolName)

        case .diff:
            menuBarState = .executing
            currentToolName = "Editing file"
            updateRemoteCommandStatus(toolName: "Editing file")

        case .finish:
            // Cancel session timeout on finish
            sessionTimeoutTask?.cancel()
            sessionTimeoutTask = nil
            
            // --- Finish deduplication ---
            // Secondary finish events (session.idle, process exit) are silently absorbed
            // when a primary finish (step_finish) has already been processed.
            // This prevents the "Completed / Session idle / Task completed" triple-spam.
            if event.isSecondaryFinish && sessionStatus == .completed {
                // Already completed — just ensure cleanup, don't add another message
                Log.debug("Ignoring secondary finish event (already completed)")
                return
            }

            menuBarState = .idle
            sessionStatus = .completed
            currentToolName = nil
            currentToolInput = nil

            // Mark all running tool messages as completed (cleanup)
            finalizeRunningMessages()

            // Update session status
            if let session = currentSession {
                session.status = "completed"
            }
            // Show completion in status bar
            statusBarController?.showCompleted()
            // Complete remote command in CloudKit
            if let commandId = currentRemoteCommandId {
                let resultMessage = messages.last(where: { $0.type == .assistant })?.content ?? "Task completed"
                cloudKitManager.completeCommand(commandId: commandId, result: resultMessage)
                currentRemoteCommandId = nil
            }

        case .assistant:
            menuBarState = .reasoning
            currentToolName = nil

        case .user:
            // User messages are added directly in submitIntent
            return

        case .error:
            // Explicit error from OpenCode — always surface to user
            sessionTimeoutTask?.cancel()
            sessionTimeoutTask = nil
            lastErrorMessage = event.text
            sessionStatus = .failed
            menuBarState = .idle
            currentToolName = nil
            currentToolInput = nil
            finalizeRunningMessages()
            if let session = currentSession {
                session.status = "failed"
            }
            statusBarController?.showError()
            if let commandId = currentRemoteCommandId {
                cloudKitManager.failCommand(commandId: commandId, error: event.text)
                currentRemoteCommandId = nil
            }

        case .unknown:
            // Check for various error patterns
            let errorText = detectError(in: event.text, rawJson: event.rawJson)
            if let error = errorText {
                lastErrorMessage = error
                sessionStatus = .failed
                menuBarState = .idle
                currentToolName = nil
                if let session = currentSession {
                    session.status = "failed"
                }
                // Show error in status bar
                statusBarController?.showError()
                // Fail remote command in CloudKit
                if let commandId = currentRemoteCommandId {
                    cloudKitManager.failCommand(commandId: commandId, error: error)
                    currentRemoteCommandId = nil
                }
            }
        }

        // Process event content (save session ID, add messages)
        processEventContent(event)
    }

    // MARK: - Tool Lifecycle Helpers

    /// When a step/task finishes, mark any still-running tool messages as completed.
    private func finalizeRunningMessages() {
        for i in messages.indices where messages[i].type == .tool && messages[i].status == .running {
            messages[i] = messages[i].withStatus(.completed)
        }
    }

    // MARK: - AskUserQuestion

    func isAskUserQuestionTool(_ toolName: String?) -> Bool {
        guard let toolName else { return false }
        let normalized = normalizeToolName(toolName)
        if normalized == "askuserquestion" { return true }
        return normalized.hasSuffix("askuserquestion")
    }

    private func normalizeToolName(_ toolName: String) -> String {
        let base = toolName
            .components(separatedBy: ["/", ":", "."])
            .last ?? toolName
        let lowered = base.lowercased()
        let stripped = lowered.filter { $0.isLetter || $0.isNumber }
        return stripped
    }

    func extractAskUserQuestionInput(from rawJson: String) -> [String: Any]? {
        guard let data = rawJson.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let part = object["part"] as? [String: Any] else {
            return nil
        }

        if let input = extractInputDict(from: part) {
            return input
        }
        if let state = part["state"] as? [String: Any],
           let input = extractInputDict(from: state) {
            return input
        }
        return nil
    }

    private func extractInputDict(from container: [String: Any]) -> [String: Any]? {
        let keys = ["input", "arguments", "args"]
        for key in keys {
            if let dict = container[key] as? [String: Any] { return dict }
        }
        for key in keys {
            if let str = container[key] as? String,
               let data = str.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return dict
            }
        }
        return nil
    }

    /// Update remote command status in CloudKit
    private func updateRemoteCommandStatus(toolName: String?) {
        guard let commandId = currentRemoteCommandId else { return }
        cloudKitManager.updateProgress(commandId: commandId, toolName: toolName)
    }

    /// Handle AskUserQuestion tool call - show popup, add to conversation, and send response via PTY
    private func handleAskUserQuestion(input: [String: Any], event: OpenCodeEvent) {
        Log.debug("Intercepted AskUserQuestion tool call")

        guard let firstQuestion = parseAskUserQuestions(from: input) else { return }

        let questionText = firstQuestion["question"] as? String ?? "Question from AI"
        let header = firstQuestion["header"] as? String ?? "Question"
        let multiSelect = firstQuestion["multiSelect"] as? Bool ?? false
        let (options, optionLabels) = parseQuestionOptions(from: firstQuestion)

        // Add question to conversation as a tool message (waiting for user response)
        let questionMessageId = UUID()
        pendingQuestionMessageId = questionMessageId
        let optionsSummary = optionLabels.isEmpty ? "" : " [\(optionLabels.joined(separator: " / "))]"
        messages.append(ConversationMessage(
            id: questionMessageId,
            type: .tool,
            content: questionText,
            toolName: "Question",
            toolInput: questionText + optionsSummary,
            toolCallId: event.toolCallId,
            status: .running  // Waiting for user response
        ))

        // If this is a remote command, send question to iOS via CloudKit
        if let commandId = currentRemoteCommandId {
            sendQuestionToRemote(commandId: commandId, header: header, question: questionText, options: optionLabels)
            return
        }

        // For local commands, show QuickConfirm
        showLocalQuestionPrompt(
            question: questionText, header: header,
            options: options, multiSelect: multiSelect
        )
    }

    /// Parse the questions array from AskUserQuestion input.
    /// Supports both `"questions": [...]` and single `"question": "..."` shapes.
    private func parseAskUserQuestions(from input: [String: Any]) -> [String: Any]? {
        let questions: [[String: Any]]
        if let rawQuestions = input["questions"] as? [[String: Any]] {
            questions = rawQuestions
        } else if let question = input["question"] as? String {
            var single: [String: Any] = ["question": question]
            if let h = input["header"] as? String { single["header"] = h }
            if let o = input["options"] { single["options"] = o }
            if let m = input["multiSelect"] { single["multiSelect"] = m }
            questions = [single]
        } else {
            Log.debug("AskUserQuestion: no questions found in input")
            return nil
        }
        guard let first = questions.first else {
            Log.debug("AskUserQuestion: empty questions array")
            return nil
        }
        return first
    }

    /// Parse question options into structured options and label strings.
    private func parseQuestionOptions(from question: [String: Any]) -> ([PermissionRequest.QuestionOption], [String]) {
        var options: [PermissionRequest.QuestionOption] = []
        var labels: [String] = []

        if let rawOptions = question["options"] as? [[String: Any]] {
            for opt in rawOptions {
                let label = opt["label"] as? String ?? ""
                labels.append(label)
                options.append(PermissionRequest.QuestionOption(label: label, description: opt["description"] as? String))
            }
        } else if let rawOptions = question["options"] as? [String] {
            for label in rawOptions {
                labels.append(label)
                options.append(PermissionRequest.QuestionOption(label: label))
            }
        }

        // Default Yes/No/Other when no options provided
        if options.isEmpty {
            options = [
                PermissionRequest.QuestionOption(label: "Yes"),
                PermissionRequest.QuestionOption(label: "No"),
                PermissionRequest.QuestionOption(label: "Other", description: "Custom response"),
            ]
            labels = ["Yes", "No", "Other"]
        }

        return (options, labels)
    }

    /// Forward a question to iOS via CloudKit (for remote commands).
    private func sendQuestionToRemote(commandId: String, header: String, question: String, options: [String]) {
        Log.debug("Sending question to iOS via CloudKit for remote command: \(commandId)")
        Task {
            let response = await cloudKitManager.sendPermissionRequest(
                commandId: commandId,
                question: "\(header): \(question)",
                options: options
            )
            Log.debug(response != nil ? "Got response from iOS: \(response!)" : "No response from iOS, sending empty response")
            updateQuestionMessage(response: response ?? "User declined to answer.")
            await bridge.sendResponse(response ?? "")
            updateStatusBar()
        }
    }

    /// Show a local QuickConfirm prompt for AskUserQuestion.
    private func showLocalQuestionPrompt(
        question: String, header: String,
        options: [PermissionRequest.QuestionOption], multiSelect: Bool
    ) {
        let requestId = "askuser_\(UUID().uuidString)"
        let request = PermissionRequest(
            id: requestId, taskId: requestId, type: .question,
            question: question, header: header,
            options: options, multiSelect: multiSelect
        )

        if quickConfirmController == nil {
            quickConfirmController = QuickConfirmWindowController()
        }

        quickConfirmController?.show(
            request: request,
            anchorFrame: statusBarController?.buttonFrame,
            onResponse: { [weak self] (response: String) in
                Log.debug("AskUserQuestion response: \(response)")
                self?.updateQuestionMessage(response: response)
                Task { [weak self] in await self?.bridge.sendResponse(response) }
                self?.updateStatusBar()
            },
            onCancel: { [weak self] in
                Log.debug("AskUserQuestion cancelled")
                self?.updateQuestionMessage(response: "User declined to answer.")
                Task { [weak self] in await self?.bridge.sendResponse("") }
                self?.updateStatusBar()
            }
        )
    }

    /// Update the pending AskUserQuestion message with the user's response
    private func updateQuestionMessage(response: String) {
        guard let messageId = pendingQuestionMessageId,
              let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let existing = messages[index]
        let displayResponse = response.isEmpty ? "User declined to answer." : response
        messages[index] = ConversationMessage(
            id: existing.id,
            type: .tool,
            content: existing.content,
            timestamp: existing.timestamp,
            toolName: existing.toolName,
            toolInput: existing.toolInput,
            toolOutput: displayResponse,
            toolCallId: existing.toolCallId,
            status: .completed
        )
        pendingQuestionMessageId = nil
    }

    /// Detect errors from OpenCode output using a table-driven approach.
    private func detectError(in text: String, rawJson: String) -> String? {
        let lowerText = text.lowercased()

        // Ordered list: (keywords-to-match, user-facing message or nil for raw text)
        // Each entry is ([keywords], message). ALL keywords must be present.
        typealias Rule = (keywords: [String], message: String?)
        let rules: [Rule] = [
            (["opencode not configured"],                                nil),
            (["not configured"],                                         nil),
            (["authentication"],                                         "API authentication failed. Check your API key in Settings."),
            (["unauthorized"],                                           "API authentication failed. Check your API key in Settings."),
            (["invalid api key"],                                        "API authentication failed. Check your API key in Settings."),
            (["401"],                                                    "API authentication failed. Check your API key in Settings."),
            (["rate limit"],                                             "Rate limit exceeded. Please wait and try again."),
            (["429"],                                                    "Rate limit exceeded. Please wait and try again."),
            (["too many requests"],                                      "Rate limit exceeded. Please wait and try again."),
            (["model not found"],                                        "Model not found. Check your model name in Settings."),
            (["does not exist"],                                         "Model not found. Check your model name in Settings."),
            (["invalid model"],                                          "Model not found. Check your model name in Settings."),
            (["connection", "refused"],                                   "Connection failed. Check your Base URL or network."),
            (["connection", "failed"],                                    "Connection failed. Check your Base URL or network."),
            (["econnrefused"],                                           "Network error. Check your internet connection."),
            (["network error"],                                          "Network error. Check your internet connection."),
            (["ollama", "not running"],                                   "Ollama is not running. Start Ollama and try again."),
            (["ollama", "not found"],                                    "Ollama is not running. Start Ollama and try again."),
        ]

        for rule in rules {
            if rule.keywords.allSatisfy({ lowerText.contains($0) }) {
                return rule.message ?? text
            }
        }

        // Encrypted content verification → clear session and suggest retry
        if lowerText.contains("encrypted content")
            && (lowerText.contains("could not be verified") || lowerText.contains("invalid_encrypted_content")) {
            if let session = currentSession {
                Log.debug("Encrypted content verification failed - clearing session ID (likely project mismatch)")
                session.openCodeSessionId = nil
            }
            Task { await bridge.setSessionId(nil) }
            return "Session context mismatch. Please try again - a new session will be started."
        }

        // Generic error detection
        let lowerJson = rawJson.lowercased()
        if lowerText.contains("error") || lowerJson.contains("\"error\"") {
            return text.count < 200 ? text : "An error occurred. Check the console for details."
        }

        return nil
    }

    // MARK: - Event Content Processing

    private func processEventContent(_ event: OpenCodeEvent) {
        // Save OpenCode session ID to our session for resume capability
        if let sessionId = event.sessionId, let session = currentSession, session.openCodeSessionId == nil {
            session.openCodeSessionId = sessionId
            Log.debug("Saved OpenCode session ID to session: \(sessionId)")
        }

        // --- Tool event lifecycle logging ---
        if event.kind == .tool || event.kind == .call {
            let hasOutput = event.toolOutput != nil
            let phase = hasOutput ? "result" : "call"
            Log.debug("Tool event [\(phase)]: \(event.toolName ?? "?") callId=\(event.toolCallId ?? "nil") hasOutput=\(hasOutput)")
        }

        // --- TodoWrite interception ---
        if event.kind == .tool, let toolName = event.toolName, toolName.isTodoWriteTool {
            handleTodoWriteEvent(event)
            logEvent(event)
            return
        }

        // Convert event to conversation message and add to list
        guard let message = event.toMessage() else {
            logEvent(event)
            return
        }

        // --- Finish event handling ---
        // Secondary finish events with empty text are silent (just for state cleanup)
        if message.type == .system && event.isSecondaryFinish {
            if message.content.isEmpty {
                // Silent cleanup finish — don't add any message
                logEvent(event)
                return
            }
            // Non-empty secondary finish (e.g., first finish was session.idle before step_finish)
            // Only add if no completion message exists yet
            let hasCompletionMessage = messages.contains { $0.type == .system && isCompletionText($0.content) }
            if hasCompletionMessage {
                logEvent(event)
                return
            }
        }

        // --- Primary finish: only add if no completion message already ---
        if message.type == .system && isCompletionText(message.content) {
            let hasCompletionMessage = messages.contains { $0.type == .system && isCompletionText($0.content) }
            if hasCompletionMessage {
                logEvent(event)
                return
            }
        }

        // --- Assistant message streaming merge ---
        if message.type == .assistant,
           let lastIndex = messages.lastIndex(where: { $0.type == .assistant }),
           lastIndex == messages.count - 1 {
            messages[lastIndex] = messages[lastIndex].withContent(messages[lastIndex].content + message.content)
        }
        // --- Tool message lifecycle merge ---
        else if message.type == .tool {
            processToolMessage(message)
        }
        // --- Everything else: append ---
        else {
            messages.append(message)
        }

        // @Observable handles change tracking automatically
        logEvent(event)
    }

    /// Process tool messages with proper lifecycle: running -> completed
    private func processToolMessage(_ message: ConversationMessage) {
        // Strategy 1: Merge by toolCallId (most reliable)
        if let toolCallId = message.toolCallId,
           let idx = messages.lastIndex(where: { $0.type == .tool && $0.toolCallId == toolCallId }) {
            Log.debug("Tool merge [callId]: \(messages[idx].toolName ?? "?") \(messages[idx].status.rawValue) → \(message.toolOutput != nil ? "completed" : messages[idx].status.rawValue)")
            messages[idx] = messages[idx].mergingToolData(from: message)
        }
        // Strategy 2: Merge consecutive tool messages (fallback for missing toolCallId)
        else if let lastIdx = messages.lastIndex(where: { $0.type == .tool }),
                lastIdx == messages.count - 1,
                messages[lastIdx].toolOutput == nil,
                message.toolOutput != nil,
                (message.toolName == "Result" || message.toolName == messages[lastIdx].toolName) {
            Log.debug("Tool merge [consecutive]: \(messages[lastIdx].toolName ?? "?") → completed")
            messages[lastIdx] = messages[lastIdx].mergingToolData(from: message)
        }
        // No merge target — append as new message
        else {
            Log.debug("Tool append [new]: \(message.toolName ?? "?") status=\(message.status.rawValue) hasOutput=\(message.toolOutput != nil)")
            messages.append(message)
        }
    }

    /// Check if text represents a completion message
    func isCompletionText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower == "completed"
            || lower == "session idle"
            || lower == "task completed"
            || lower.hasPrefix("task completed with exit code")
    }

    // MARK: - TodoWrite Handling

    /// Intercept TodoWrite tool calls and create/update a dedicated todo message
    private func handleTodoWriteEvent(_ event: OpenCodeEvent) {
        // Parse todo items from the tool input
        let todoItems = parseTodoItems(from: event)
        guard !todoItems.isEmpty else {
            Log.debug("TodoWrite: no items parsed from event")
            // If we can't parse todos, fall back to normal tool display
            if let message = event.toMessage() {
                processToolMessage(message)
            }
            return
        }

        // Determine if we should merge with existing todo message
        let merge = parseTodoMerge(from: event)
        Log.debug("TodoWrite: \(todoItems.count) items, merge=\(merge)")
        for item in todoItems {
            Log.debug("  todo[\(item.id)]: status=\(item.status.rawValue), content=\"\(item.content.prefix(40))\"")
        }

        // Find existing todo message to update
        if let existingIndex = messages.lastIndex(where: { $0.type == .todo }) {
            let existing = messages[existingIndex]
            let finalItems: [TodoItem]
            if merge, let existingItems = existing.todoItems {
                // Merge: update existing items by ID, preserve content when new item has none
                var itemMap = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
                for item in todoItems {
                    if let existingItem = itemMap[item.id], item.content.isEmpty {
                        // Status-only update: keep existing content, apply new status
                        itemMap[item.id] = TodoItem(id: item.id, content: existingItem.content, status: item.status)
                    } else {
                        itemMap[item.id] = item
                    }
                }
                finalItems = itemMap.values.sorted { $0.id < $1.id }
            } else {
                finalItems = todoItems
            }
            messages[existingIndex] = existing.withTodos(finalItems, summary: todoSummary(finalItems))
        } else {
            messages.append(ConversationMessage(
                type: .todo, content: todoSummary(todoItems),
                status: .completed, todoItems: todoItems
            ))
        }
    }

    /// Parse todo items from a TodoWrite event
    private func parseTodoItems(from event: OpenCodeEvent) -> [TodoItem] {
        // Try toolInputDict first (parsed from tool_call)
        if let inputDict = event.toolInputDict {
            return parseTodoItemsFromDict(inputDict)
        }

        // Try parsing from rawJson (fallback)
        guard let data = event.rawJson.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let part = object["part"] as? [String: Any] else {
            return []
        }

        // tool_call format
        if let input = extractInputDict(from: part) {
            return parseTodoItemsFromDict(input)
        }

        // tool_use format
        if let state = part["state"] as? [String: Any],
           let input = extractInputDict(from: state) {
            return parseTodoItemsFromDict(input)
        }

        return []
    }

    /// Parse the "merge" flag from a TodoWrite event
    private func parseTodoMerge(from event: OpenCodeEvent) -> Bool {
        // Try toolInputDict first (set during event parsing)
        if let inputDict = event.toolInputDict {
            return inputDict["merge"] as? Bool ?? false
        }
        // Fallback: parse from rawJson
        guard let data = event.rawJson.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let part = object["part"] as? [String: Any] else {
            return false
        }
        // tool_call format
        if let input = extractInputDict(from: part) {
            return input["merge"] as? Bool ?? false
        }
        // tool_use format
        if let state = part["state"] as? [String: Any],
           let input = extractInputDict(from: state) {
            return input["merge"] as? Bool ?? false
        }
        return false
    }

    /// Parse todo items from a dictionary
    private func parseTodoItemsFromDict(_ dict: [String: Any]) -> [TodoItem] {
        guard let todosArray = dict["todos"] as? [[String: Any]] else {
            return []
        }
        return todosArray.compactMap { TodoItem(from: $0) }
    }

    /// Generate a summary string for todo items
    func todoSummary(_ items: [TodoItem]) -> String {
        let completed = items.filter { $0.status == .completed }.count
        let total = items.count
        return "\(completed)/\(total) tasks completed"
    }

    // MARK: - Log Persistence

    private func logEvent(_ event: OpenCodeEvent) {
        if let session = currentSession {
            let entry = LogEntry(rawJson: event.rawJson, kind: event.kind.rawValue)
            modelContext?.insert(entry)
            session.logs.append(entry)
        }
    }
}
