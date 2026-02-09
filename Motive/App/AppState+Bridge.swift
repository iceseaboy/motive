//
//  AppState+Bridge.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//
//  Handles OpenCode SSE events routed through OpenCodeBridge.
//  Uses native question/permission system (no MCP sidecar).
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
            debugMode: configManager.debugMode,
            projectDirectory: configManager.currentProjectURL.path
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
                Log.debug("Session timeout: no events for \(Int(Self.sessionTimeoutSeconds))s while still running")
                lastErrorMessage = "No response from OpenCode for \(Int(Self.sessionTimeoutSeconds)) seconds. The process may be stalled. You can interrupt or wait."
                statusBarController?.showError()
            }
        }
    }

    func handle(event: OpenCodeEvent) {
        // Log every event arrival for diagnostics — full text, no truncation
        Log.bridge("⬇︎ Event: kind=\(event.kind.rawValue) tool=\(event.toolName ?? "-") session=\(event.sessionId ?? "-") text=«\(event.text)»")

        // Once the user has manually interrupted, ignore all subsequent events.
        // OpenCode may send trailing tool/error events (e.g. "MessageAbortedError")
        // that would overwrite the interrupted state and confuse the UI.
        if sessionStatus == .interrupted {
            Log.debug("Ignoring post-interrupt event: \(event.kind.rawValue)")
            logEvent(event)
            return
        }

        // Reset session timeout on every event
        resetSessionTimeout()
        
        // Update UI state based on event kind
        switch event.kind {
        case .usage:
            applyUsageUpdate(event)

        case .thought:
            menuBarState = .reasoning
            currentToolName = nil
            currentToolInput = nil
            // Cancel any pending dismiss — new reasoning is arriving
            reasoningDismissTask?.cancel()
            reasoningDismissTask = nil
            // Accumulate reasoning text into transient state (not messages)
            if !event.text.isEmpty {
                currentReasoningText = (currentReasoningText ?? "") + event.text
            }
            // Update CloudKit for remote commands
            updateRemoteCommandStatus(toolName: "Thinking...")
            // Don't flow to processEventContent — reasoning is transient
            logEvent(event)
            return

        case .call, .tool:
            // Thinking is over — fade out transient reasoning
            dismissReasoningAfterDelay()
            menuBarState = .executing
            currentToolName = event.toolName ?? "Processing"
            currentToolInput = event.toolInput

            // Intercept native question events from SSE
            if let inputDict = event.toolInputDict,
               inputDict["_isNativeQuestion"] as? Bool == true {
                handleNativeQuestion(inputDict: inputDict, event: event)
                logEvent(event)
                return
            }

            // Intercept native permission events from SSE
            if let inputDict = event.toolInputDict,
               inputDict["_isNativePermission"] as? Bool == true {
                handleNativePermission(inputDict: inputDict, event: event)
                logEvent(event)
                return
            }

            // Update CloudKit for remote commands
            updateRemoteCommandStatus(toolName: event.toolName)

        case .diff:
            dismissReasoningAfterDelay()
            menuBarState = .executing
            currentToolName = "Editing file"
            updateRemoteCommandStatus(toolName: "Editing file")

        case .finish:
            // Cancel session timeout on finish
            sessionTimeoutTask?.cancel()
            sessionTimeoutTask = nil
            reasoningDismissTask?.cancel()
            reasoningDismissTask = nil
            currentReasoningText = nil
            
            // --- Finish deduplication ---
            if event.isSecondaryFinish && sessionStatus == .completed {
                Log.debug("Ignoring secondary finish event (already completed)")
                return
            }

            menuBarState = .idle
            sessionStatus = .completed
            currentToolName = nil
            currentToolInput = nil

            // Mark all running tool messages as completed (cleanup)
            finalizeRunningMessages()

            // Update session status and snapshot messages
            if let session = currentSession {
                session.status = "completed"
                session.messagesData = ConversationMessage.serializeMessages(messages)
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
            dismissReasoningAfterDelay()
            // Model is actively outputting response text — NOT thinking/waiting.
            menuBarState = .responding
            currentToolName = nil

        case .user:
            // User messages are added directly in submitIntent
            return

        case .error:
            // Explicit error from OpenCode — always surface to user
            sessionTimeoutTask?.cancel()
            sessionTimeoutTask = nil
            reasoningDismissTask?.cancel()
            reasoningDismissTask = nil
            currentReasoningText = nil
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
            // With SSE, unknown events are rare — just log them
            if !event.text.isEmpty {
                Log.debug("Unknown event: \(event.text.prefix(200))")
            }
        }

        // Process event content (save session ID, add messages)
        processEventContent(event)
    }

    // MARK: - Reasoning Lifecycle

    /// Dismiss transient reasoning text after a short delay, giving the user time to see it.
    /// If new reasoning arrives before the delay, the task is cancelled and reasoning stays.
    private func dismissReasoningAfterDelay() {
        guard currentReasoningText != nil else { return }
        reasoningDismissTask?.cancel()
        reasoningDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.currentReasoningText = nil
        }
    }

    // MARK: - Tool Lifecycle Helpers

    /// When a step/task finishes, mark any still-running tool messages as completed.
    private func finalizeRunningMessages() {
        for i in messages.indices where messages[i].type == .tool && messages[i].status == .running {
            messages[i] = messages[i].withStatus(.completed)
        }
    }

    // MARK: - Native Question Handling

    /// Handle a native question from OpenCode's question tool (via SSE).
    private func handleNativeQuestion(inputDict: [String: Any], event: OpenCodeEvent) {
        let questionID = inputDict["_nativeQuestionID"] as? String ?? UUID().uuidString
        let questionText = inputDict["question"] as? String ?? "Question from AI"
        let custom = inputDict["custom"] as? Bool ?? true
        let multiple = inputDict["multiple"] as? Bool ?? false

        // Parse options
        var options: [PermissionRequest.QuestionOption] = []
        var optionLabels: [String] = []
        if let rawOptions = inputDict["options"] as? [[String: Any]] {
            for opt in rawOptions {
                let label = opt["label"] as? String ?? ""
                let description = opt["description"] as? String
                options.append(PermissionRequest.QuestionOption(label: label, description: description))
                optionLabels.append(label)
            }
        }

        // Add custom "Other" option if custom input is enabled and not already present
        if custom && !options.contains(where: { $0.label.lowercased() == "other" }) {
            options.append(PermissionRequest.QuestionOption(label: "Other", description: "Type your own answer"))
            optionLabels.append("Other")
        }

        // Default options if none provided
        if options.isEmpty {
            options = [
                PermissionRequest.QuestionOption(label: "Yes"),
                PermissionRequest.QuestionOption(label: "No"),
                PermissionRequest.QuestionOption(label: "Other", description: "Custom response"),
            ]
            optionLabels = ["Yes", "No", "Other"]
        }

        Log.debug("Native question: \(questionText) options=\(optionLabels)")

        // Add question to conversation as a tool message (waiting for user response)
        let questionMessageId = UUID()
        pendingQuestionMessageId = questionMessageId
        let optionsSummary = " [\(optionLabels.joined(separator: " / "))]"
        messages.append(ConversationMessage(
            id: questionMessageId,
            type: .tool,
            content: questionText,
            toolName: "Question",
            toolInput: questionText + optionsSummary,
            toolCallId: event.toolCallId,
            status: .running
        ))

        // If this is a remote command, send question to iOS via CloudKit
        if let commandId = currentRemoteCommandId {
            sendQuestionToRemote(commandId: commandId, questionID: questionID, question: questionText, options: optionLabels)
            return
        }

        // Show local QuickConfirm
        showNativeQuestionPrompt(
            questionID: questionID,
            question: questionText,
            options: options,
            multiSelect: multiple
        )
    }

    /// Show a local QuickConfirm prompt for a native question.
    private func showNativeQuestionPrompt(
        questionID: String,
        question: String,
        options: [PermissionRequest.QuestionOption],
        multiSelect: Bool
    ) {
        let request = PermissionRequest(
            id: questionID, taskId: questionID, type: .question,
            question: question, header: "Question",
            options: options, multiSelect: multiSelect
        )

        if quickConfirmController == nil {
            quickConfirmController = QuickConfirmWindowController()
        }

        quickConfirmController?.show(
            request: request,
            anchorFrame: statusBarController?.buttonFrame,
            onResponse: { [weak self] (response: String) in
                Log.debug("Native question response: \(response)")
                self?.updateQuestionMessage(response: response)
                Task { [weak self] in
                    await self?.bridge.replyToQuestion(
                        requestID: questionID,
                        answers: [[response]]
                    )
                }
                self?.updateStatusBar()
            },
            onCancel: { [weak self] in
                Log.debug("Native question cancelled")
                self?.updateQuestionMessage(response: "User declined to answer.")
                Task { [weak self] in
                    await self?.bridge.rejectQuestion(requestID: questionID)
                }
                self?.updateStatusBar()
            }
        )
    }

    // MARK: - Native Permission Handling

    /// Handle a native permission request from OpenCode (via SSE).
    private func handleNativePermission(inputDict: [String: Any], event: OpenCodeEvent) {
        let permissionID = inputDict["_nativePermissionID"] as? String ?? UUID().uuidString
        let permission = inputDict["permission"] as? String ?? "unknown"
        let patterns = inputDict["patterns"] as? [String] ?? []
        let metadata = inputDict["metadata"] as? [String: String] ?? [:]
        let diff = metadata["diff"]

        Log.debug("Native permission: \(permission) patterns=\(patterns)")

        // Add permission to conversation
        let permMessageId = UUID()
        pendingQuestionMessageId = permMessageId
        let patternsStr = patterns.joined(separator: ", ")
        messages.append(ConversationMessage(
            id: permMessageId,
            type: .tool,
            content: "\(permission): \(patternsStr)",
            toolName: "Permission",
            toolInput: patternsStr,
            toolCallId: event.toolCallId,
            status: .running
        ))

        // Build options for the permission dialog
        var options: [PermissionRequest.QuestionOption] = [
            PermissionRequest.QuestionOption(label: "Allow Once", description: "Allow this specific action"),
            PermissionRequest.QuestionOption(label: "Always Allow", description: "Allow and remember for this pattern"),
            PermissionRequest.QuestionOption(label: "Reject", description: "Deny this action"),
        ]

        // Include diff preview in the question text if available
        var questionText = "Allow \(permission) for \(patternsStr)?"
        if let diff, !diff.isEmpty {
            questionText += "\n\n```diff\n\(diff)\n```"
        }

        // If remote command, handle via CloudKit
        if let commandId = currentRemoteCommandId {
            sendPermissionToRemote(commandId: commandId, permissionID: permissionID, question: questionText, options: options.map(\.label))
            return
        }

        // Show local QuickConfirm
        var request = PermissionRequest(
            id: permissionID, taskId: permissionID, type: .permission,
            question: questionText, header: "Permission Request",
            options: options, multiSelect: false
        )
        // Set permission-specific fields for permissionContent view
        request.permissionType = permission
        request.patterns = patterns
        request.diff = diff

        if quickConfirmController == nil {
            quickConfirmController = QuickConfirmWindowController()
        }

        quickConfirmController?.show(
            request: request,
            anchorFrame: statusBarController?.buttonFrame,
            onResponse: { [weak self] (response: String) in
                Log.debug("Native permission response: \(response)")
                self?.updateQuestionMessage(response: response)

                let reply: OpenCodeAPIClient.PermissionReply
                switch response.lowercased() {
                case "always allow":
                    reply = .always
                case "reject":
                    reply = .reject(nil)
                default:
                    reply = .once
                }

                Task { [weak self] in
                    await self?.bridge.replyToPermission(requestID: permissionID, reply: reply)
                }
                self?.updateStatusBar()
            },
            onCancel: { [weak self] in
                Log.debug("Native permission rejected")
                self?.updateQuestionMessage(response: "Rejected")
                Task { [weak self] in
                    await self?.bridge.replyToPermission(requestID: permissionID, reply: .reject("User rejected"))
                }
                self?.updateStatusBar()
            }
        )
    }

    // MARK: - Remote (CloudKit) Helpers

    /// Forward a native question to iOS via CloudKit (for remote commands).
    private func sendQuestionToRemote(commandId: String, questionID: String, question: String, options: [String]) {
        Log.debug("Sending question to iOS via CloudKit for remote command: \(commandId)")
        Task {
            let response = await cloudKitManager.sendPermissionRequest(
                commandId: commandId,
                question: question,
                options: options
            )
            Log.debug(response != nil ? "Got response from iOS: \(response!)" : "No response from iOS, sending empty response")
            updateQuestionMessage(response: response ?? "User declined to answer.")
            await bridge.replyToQuestion(requestID: questionID, answers: [[response ?? ""]])
            updateStatusBar()
        }
    }

    /// Forward a native permission to iOS via CloudKit (for remote commands).
    private func sendPermissionToRemote(commandId: String, permissionID: String, question: String, options: [String]) {
        Log.debug("Sending permission to iOS via CloudKit for remote command: \(commandId)")
        Task {
            let response = await cloudKitManager.sendPermissionRequest(
                commandId: commandId,
                question: question,
                options: options
            )
            let reply: OpenCodeAPIClient.PermissionReply
            if let response, response.lowercased().contains("always") {
                reply = .always
            } else if let response, (response.lowercased() == "allow" || response.lowercased() == "allow once") {
                reply = .once
            } else {
                reply = .reject(nil)
            }
            updateQuestionMessage(response: response ?? "Rejected")
            await bridge.replyToPermission(requestID: permissionID, reply: reply)
            updateStatusBar()
        }
    }

    /// Update remote command status in CloudKit
    private func updateRemoteCommandStatus(toolName: String?) {
        guard let commandId = currentRemoteCommandId else { return }
        cloudKitManager.updateProgress(commandId: commandId, toolName: toolName)
    }

    // MARK: - Question/Permission Message Updates

    /// Update the pending question/permission message with the user's response.
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

    // MARK: - Event Content Processing

    private func processEventContent(_ event: OpenCodeEvent) {
        if event.kind == .usage {
            return
        }
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

        // --- Question / Permission result interception ---
        // The call events are intercepted in handle(event:) via _isNativeQuestion/_isNativePermission.
        // The result events (with toolOutput) arrive separately without those flags.
        // Skip them here — the Question/Permission message lifecycle is fully managed
        // by handleNativeQuestion/handleNativePermission and updateQuestionMessage.
        if event.kind == .tool || event.kind == .call,
           let toolName = event.toolName?.lowercased(),
           toolName == "question" || toolName == "permission" {
            logEvent(event)
            return
        }

        // --- TodoWrite interception (live has special UI handling) ---
        // Intercept both .call (running) and .tool (completed) to avoid duplicate bubbles.
        if (event.kind == .tool || event.kind == .call),
           let toolName = event.toolName, toolName.isTodoWriteTool {
            // Only process completed events; skip the running call event entirely
            if event.kind == .tool {
                handleTodoWriteEvent(event)
            }
            logEvent(event)
            return
        }

        // Insert into live messages array
        insertEventMessage(event)
        logEvent(event)
    }

    private func applyUsageUpdate(_ event: OpenCodeEvent) {
        guard let usage = event.usage else {
            Log.debug("[Usage] applyUsageUpdate: no usage data in event")
            return
        }

        Log.debug("[Usage] applyUsageUpdate: model=\(event.model ?? "nil") in=\(usage.input) out=\(usage.output) reason=\(usage.reasoning) msgId=\(event.messageId ?? "nil")")

        if let messageId = event.messageId,
           let sessionId = event.sessionId {
            if !recordUsageMessageId(sessionId: sessionId, messageId: messageId) {
                Log.debug("[Usage] Deduplicated messageId=\(messageId)")
                return
            }
        }

        // Model comes from the SSE event (message.updated has modelID).
        // If model is nil, fall back to the currently selected model from settings
        // so that usage is never silently dropped.
        let model: String
        if let m = event.model, !m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model = m
        } else if let fallback = configManager.getModelString() {
            Log.debug("[Usage] Model nil in event, using settings fallback: \(fallback)")
            model = fallback
        } else {
            Log.debug("[Usage] No model available, skipping usage recording")
            return
        }

        configManager.recordTokenUsage(model: model, usage: usage, cost: event.cost)

        if usage.input > 0 {
            currentContextTokens = usage.input
            currentSession?.contextTokens = usage.input
        }
    }

    // MARK: - Message Insertion

    /// Insert an event into the live messages array.
    /// Handles streaming merge for assistant deltas, tool lifecycle, and finish deduplication.
    private func insertEventMessage(_ event: OpenCodeEvent) {
        // Skip empty/unparseable events
        if event.kind == .unknown && event.text.isEmpty { return }
        guard let message = event.toMessage() else { return }

        // --- System / Finish deduplication ---
        if message.type == .system {
            if event.isSecondaryFinish { return }
            if isCompletionText(message.content) {
                let alreadyHas = messages.contains { $0.type == .system && isCompletionText($0.content) }
                if alreadyHas { return }
            }
        }

        // --- User messages ---
        if message.type == .user {
            messages.append(message)
            return
        }

        // --- Assistant message streaming merge ---
        // Only merge CONSECUTIVE assistant messages (last message in array must be assistant).
        // Preserves correct visual order: text-before-tools → tools → text-after-tools.
        if message.type == .assistant {
            if let lastIndex = messages.lastIndex(where: { $0.type == .assistant }),
               lastIndex == messages.count - 1 {
                messages[lastIndex] = messages[lastIndex].withContent(
                    messages[lastIndex].content + message.content
                )
            } else {
                messages.append(message)
            }
            return
        }

        // Reasoning is transient (handled via currentReasoningText), skip if it arrives here
        if message.type == .reasoning {
            return
        }

        // --- Tool message merge ---
        if message.type == .tool {
            processToolMessage(message)
            return
        }

        // --- Everything else: append ---
        messages.append(message)
    }

    /// Process tool messages with proper lifecycle: running -> completed
    private func processToolMessage(_ message: ConversationMessage) {
        // Strategy 1: Merge by toolCallId (most reliable)
        if let toolCallId = message.toolCallId,
           let idx = messages.lastIndex(where: { $0.type == .tool && $0.toolCallId == toolCallId }) {
            Log.debug("Tool merge [callId]: \(messages[idx].toolName ?? "?") \(messages[idx].status.rawValue) -> \(message.toolOutput != nil ? "completed" : messages[idx].status.rawValue)")
            messages[idx] = messages[idx].mergingToolData(from: message)
        }
        // Strategy 2: Merge consecutive tool messages (fallback for missing toolCallId)
        else if let lastIdx = messages.lastIndex(where: { $0.type == .tool }),
                lastIdx == messages.count - 1,
                messages[lastIdx].toolOutput == nil,
                message.toolOutput != nil,
                (message.toolName == "Result" || message.toolName == messages[lastIdx].toolName) {
            Log.debug("Tool merge [consecutive]: \(messages[lastIdx].toolName ?? "?") -> completed")
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

    private func handleTodoWriteEvent(_ event: OpenCodeEvent) {
        let todoItems = parseTodoItems(from: event)
        guard !todoItems.isEmpty else {
            Log.debug("TodoWrite: no items parsed from event")
            if let message = event.toMessage() {
                processToolMessage(message)
            }
            return
        }

        let merge = parseTodoMerge(from: event)
        Log.debug("TodoWrite: \(todoItems.count) items, merge=\(merge)")
        for item in todoItems {
            Log.debug("  todo[\(item.id)]: status=\(item.status.rawValue), content=\"\(item.content.prefix(40))\"")
        }

        if let existingIndex = messages.lastIndex(where: { $0.type == .todo }) {
            let existing = messages[existingIndex]
            let finalItems: [TodoItem]
            if merge, let existingItems = existing.todoItems {
                var itemMap = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
                for item in todoItems {
                    if let existingItem = itemMap[item.id], item.content.isEmpty {
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

        // Mark any stale .tool messages for TodoWrite as completed so they don't
        // stay stuck in "Processing…" state now that we have the .todo bubble.
        finalizeTodoWriteToolMessages(event: event)
    }

    /// Mark any `.tool` messages belonging to TodoWrite as `.completed`.
    /// These messages are created as `.running` when the first TodoWrite event arrives
    /// but are superseded by the `.todo` bubble once items are parsed.
    private func finalizeTodoWriteToolMessages(event: OpenCodeEvent) {
        for i in messages.indices where messages[i].type == .tool && messages[i].status == .running {
            let matchesByCallId = event.toolCallId != nil
                && messages[i].toolCallId == event.toolCallId
            let matchesByName = messages[i].toolName?.isTodoWriteTool == true
            if matchesByCallId || matchesByName {
                Log.debug("TodoWrite: finalizing stale .tool message at index \(i)")
                messages[i] = messages[i].withStatus(.completed)
            }
        }
    }

    private func parseTodoItems(from event: OpenCodeEvent) -> [TodoItem] {
        if let inputDict = event.toolInputDict {
            return parseTodoItemsFromDict(inputDict)
        }

        guard let data = event.rawJson.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let part = object["part"] as? [String: Any] else {
            return []
        }

        if let input = extractToolInput(from: part) {
            return parseTodoItemsFromDict(input)
        }
        if let state = part["state"] as? [String: Any],
           let input = extractToolInput(from: state) {
            return parseTodoItemsFromDict(input)
        }

        return []
    }

    private func parseTodoMerge(from event: OpenCodeEvent) -> Bool {
        if let inputDict = event.toolInputDict {
            return inputDict["merge"] as? Bool ?? false
        }
        guard let data = event.rawJson.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let part = object["part"] as? [String: Any] else {
            return false
        }
        if let input = extractToolInput(from: part) {
            return input["merge"] as? Bool ?? false
        }
        if let state = part["state"] as? [String: Any],
           let input = extractToolInput(from: state) {
            return input["merge"] as? Bool ?? false
        }
        return false
    }

    /// Extract tool input dictionary from a container (used by TodoWrite parsing).
    private func extractToolInput(from container: [String: Any]) -> [String: Any]? {
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

    private func parseTodoItemsFromDict(_ dict: [String: Any]) -> [TodoItem] {
        guard let todosArray = dict["todos"] as? [[String: Any]] else {
            return []
        }
        return todosArray.compactMap { TodoItem(from: $0) }
    }

    func todoSummary(_ items: [TodoItem]) -> String {
        let completed = items.filter { $0.status == .completed }.count
        let total = items.count
        return "\(completed)/\(total) tasks completed"
    }

    // MARK: - Log Persistence

    func logEvent(_ event: OpenCodeEvent) {
        if let session = currentSession {
            // Use toReplayJSON() to ensure bridge-created events (which have empty rawJson)
            // are serialized into parseable JSON for session replay.
            let json = event.toReplayJSON()
            let entry = LogEntry(rawJson: json, kind: event.kind.rawValue)
            modelContext?.insert(entry)
            session.logs.append(entry)
        }
    }
}
