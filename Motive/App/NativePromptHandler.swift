//
//  NativePromptHandler.swift
//  Motive
//

import Foundation
import AppKit

@MainActor
final class NativePromptHandler {
    weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Native Question Handling

    /// Handle a native question from OpenCode's question tool (via SSE).
    func handleNativeQuestion(inputDict: [String: Any], event: OpenCodeEvent) {
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
        appState?.pendingQuestionMessageId = questionMessageId
        let optionsSummary = " [\(optionLabels.joined(separator: " / "))]"
        appState?.messageStore.messages.append(ConversationMessage(
            id: questionMessageId,
            type: .tool,
            content: questionText,
            toolName: "Question",
            toolInput: questionText + optionsSummary,
            toolCallId: event.toolCallId,
            status: .running
        ))

        // If this is a remote command, send question to iOS via CloudKit
        if let commandId = appState?.currentRemoteCommandId {
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
    func showNativeQuestionPrompt(
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

        if appState?.quickConfirmController == nil {
            appState?.quickConfirmController = QuickConfirmWindowController()
        }

        appState?.quickConfirmController?.show(
            request: request,
            anchorFrame: appState?.statusBarController?.buttonFrame,
            onResponse: { [weak self] (response: String) in
                Log.debug("Native question response: \(response)")
                self?.appState?.messageStore.updateQuestionMessage(messageId: self?.appState?.pendingQuestionMessageId, response: response)
                self?.appState?.pendingQuestionMessageId = nil
                Task { [weak self] in
                    await self?.appState?.bridge.replyToQuestion(
                        requestID: questionID,
                        answers: [[response]]
                    )
                }
                self?.appState?.updateStatusBar()
            },
            onCancel: { [weak self] in
                Log.debug("Native question cancelled")
                self?.appState?.messageStore.updateQuestionMessage(messageId: self?.appState?.pendingQuestionMessageId, response: "User declined to answer.")
                self?.appState?.pendingQuestionMessageId = nil
                Task { [weak self] in
                    await self?.appState?.bridge.rejectQuestion(requestID: questionID)
                }
                self?.appState?.updateStatusBar()
            }
        )
    }

    // MARK: - Native Permission Handling

    /// Handle a native permission request from OpenCode (via SSE).
    func handleNativePermission(inputDict: [String: Any], event: OpenCodeEvent) {
        let permissionID = inputDict["_nativePermissionID"] as? String ?? UUID().uuidString
        let permission = inputDict["permission"] as? String ?? "unknown"
        let patterns = inputDict["patterns"] as? [String] ?? []
        let metadata = inputDict["metadata"] as? [String: String] ?? [:]
        let diff = metadata["diff"]

        Log.debug("Native permission: \(permission) patterns=\(patterns)")

        // Add permission to conversation
        let permMessageId = UUID()
        appState?.pendingQuestionMessageId = permMessageId
        let patternsStr = patterns.joined(separator: ", ")
        appState?.messageStore.messages.append(ConversationMessage(
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
        if let commandId = appState?.currentRemoteCommandId {
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

        if appState?.quickConfirmController == nil {
            appState?.quickConfirmController = QuickConfirmWindowController()
        }

        appState?.quickConfirmController?.show(
            request: request,
            anchorFrame: appState?.statusBarController?.buttonFrame,
            onResponse: { [weak self] (response: String) in
                Log.debug("Native permission response: \(response)")
                self?.appState?.messageStore.updateQuestionMessage(messageId: self?.appState?.pendingQuestionMessageId, response: response)
                self?.appState?.pendingQuestionMessageId = nil

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
                    await self?.appState?.bridge.replyToPermission(requestID: permissionID, reply: reply)
                }
                self?.appState?.updateStatusBar()
            },
            onCancel: { [weak self] in
                Log.debug("Native permission rejected")
                self?.appState?.messageStore.updateQuestionMessage(messageId: self?.appState?.pendingQuestionMessageId, response: "Rejected")
                self?.appState?.pendingQuestionMessageId = nil
                Task { [weak self] in
                    await self?.appState?.bridge.replyToPermission(requestID: permissionID, reply: .reject("User rejected"))
                }
                self?.appState?.updateStatusBar()
            }
        )
    }

    // MARK: - Remote (CloudKit) Helpers

    /// Forward a native question to iOS via CloudKit (for remote commands).
    func sendQuestionToRemote(commandId: String, questionID: String, question: String, options: [String]) {
        Log.debug("Sending question to iOS via CloudKit for remote command: \(commandId)")
        Task { [weak self] in
            let response = await self?.appState?.cloudKitManager.sendPermissionRequest(
                commandId: commandId,
                question: question,
                options: options
            )
            Log.debug(response != nil ? "Got response from iOS: \(response!)" : "No response from iOS, sending empty response")
            self?.appState?.messageStore.updateQuestionMessage(messageId: self?.appState?.pendingQuestionMessageId, response: response ?? "User declined to answer.")
            self?.appState?.pendingQuestionMessageId = nil
            await self?.appState?.bridge.replyToQuestion(requestID: questionID, answers: [[response ?? ""]])
            self?.appState?.updateStatusBar()
        }
    }

    /// Forward a native permission to iOS via CloudKit (for remote commands).
    func sendPermissionToRemote(commandId: String, permissionID: String, question: String, options: [String]) {
        Log.debug("Sending permission to iOS via CloudKit for remote command: \(commandId)")
        Task { [weak self] in
            let response = await self?.appState?.cloudKitManager.sendPermissionRequest(
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
            self?.appState?.messageStore.updateQuestionMessage(messageId: self?.appState?.pendingQuestionMessageId, response: response ?? "Rejected")
            self?.appState?.pendingQuestionMessageId = nil
            await self?.appState?.bridge.replyToPermission(requestID: permissionID, reply: reply)
            self?.appState?.updateStatusBar()
        }
    }

    /// Update remote command status in CloudKit
    func updateRemoteCommandStatus(toolName: String?) {
        guard let commandId = appState?.currentRemoteCommandId else { return }
        appState?.cloudKitManager.updateProgress(commandId: commandId, toolName: toolName)
    }
}
