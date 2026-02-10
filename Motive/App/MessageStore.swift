//
//  MessageStore.swift
//  Motive
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class MessageStore: ObservableObject {
    @Published var messages: [ConversationMessage] = []

    // MARK: - Message Insertion

    /// Insert an event into the live messages array.
    /// Handles streaming merge for assistant deltas, tool lifecycle, and finish deduplication.
    func insertEventMessage(_ event: OpenCodeEvent) {
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
        // Preserves correct visual order: text-before-tools -> tools -> text-after-tools.
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
    func processToolMessage(_ message: ConversationMessage) {
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

    func handleTodoWriteEvent(_ event: OpenCodeEvent) {
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
        // stay stuck in "Processing..." state now that we have the .todo bubble.
        finalizeTodoWriteToolMessages(event: event)
    }

    /// Mark any `.tool` messages belonging to TodoWrite as `.completed`.
    /// These messages are created as `.running` when the first TodoWrite event arrives
    /// but are superseded by the `.todo` bubble once items are parsed.
    func finalizeTodoWriteToolMessages(event: OpenCodeEvent) {
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

    func parseTodoItems(from event: OpenCodeEvent) -> [TodoItem] {
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

    func parseTodoMerge(from event: OpenCodeEvent) -> Bool {
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
    func extractToolInput(from container: [String: Any]) -> [String: Any]? {
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

    func parseTodoItemsFromDict(_ dict: [String: Any]) -> [TodoItem] {
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

    // MARK: - Question/Permission Message Updates

    /// Update the pending question/permission message with the user's response.
    func updateQuestionMessage(messageId: UUID?, response: String) {
        guard let messageId,
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
    }

    // MARK: - Tool Lifecycle Helpers

    /// When a step/task finishes, mark any still-running tool messages as completed.
    func finalizeRunningMessages() {
        for i in messages.indices where messages[i].type == .tool && messages[i].status == .running {
            messages[i] = messages[i].withStatus(.completed)
        }
    }
}
