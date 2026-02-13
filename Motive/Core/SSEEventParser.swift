//
//  SSEEventParser.swift
//  Motive
//
//  SSE event parsing logic extracted from SSEClient.swift.
//  All methods are extensions on SSEClient to maintain access to actor isolation.
//

import Foundation
import os

// MARK: - SSE Parsing

extension SSEClient {

    /// Parse a JSON SSE data payload into a typed event.
    func parseSSEData(_ dataString: String) -> SSEEvent? {
        guard let data = dataString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["type"] as? String else {
            return nil
        }

        let properties = json["properties"] as? [String: Any] ?? [:]

        switch eventType {
        case "server.connected":
            return .connected

        case "server.heartbeat":
            return .heartbeat

        case "message.part.updated":
            return parseMessagePartUpdated(properties)

        case "message.updated":
            return parseMessageUpdated(properties)

        case "message.removed":
            return nil

        case "session.status":
            return parseSessionStatus(properties)

        case "session.error":
            return parseSessionError(properties)

        case "session.idle":
            let sessionID = properties["sessionID"] as? String ?? ""
            return .sessionIdle(sessionID: sessionID)

        case "session.created", "session.updated", "session.deleted", "session.diff":
            return nil

        case "question.asked":
            return parseQuestionAsked(properties)

        case "permission.asked":
            return parsePermissionAsked(properties)

        case "permission.replied":
            return nil

        default:
            logger.debug("Unhandled SSE event type: \(eventType)")
            return nil
        }
    }

    /// Parse payload from `/global/event` stream:
    /// `{ "directory": "...", "payload": { "type": "...", "properties": ... } }`
    func parseGlobalSSEData(_ dataString: String) -> ScopedEvent? {
        guard let data = dataString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              JSONSerialization.isValidJSONObject(payload),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadString = String(data: payloadData, encoding: .utf8),
              let event = parseSSEData(payloadString) else {
            return nil
        }
        let directory = json["directory"] as? String
        return ScopedEvent(directory: directory, event: event)
    }
}

// MARK: - Event Parsers

extension SSEClient {

    func parseMessagePartUpdated(_ properties: [String: Any]) -> SSEEvent? {
        let part = properties["part"] as? [String: Any] ?? properties
        let delta = properties["delta"] as? String

        // sessionID may be in `part` or at the `properties` level — check both.
        // The server puts sessionID in properties; some part types duplicate it inside part.
        let sessionID = part["sessionID"] as? String
            ?? properties["sessionID"] as? String
            ?? ""
        let messageID = part["messageID"] as? String
            ?? properties["messageID"] as? String
            ?? ""
        let partType = part["type"] as? String ?? ""

        logger.debug("parseMessagePartUpdated: partType=\(partType) hasDelta=\(delta != nil) deltaLen=\(delta?.count ?? 0) sessionID=\(sessionID.prefix(8))")

        switch partType {
        case "step-finish":
            if let usage = parseTokenUsage(from: part), usage.total > 0 {
                let model = parseModelName(from: part)
                let cost = parseDouble(from: part["cost"])
                return .usageUpdated(UsageInfo(
                    sessionID: sessionID,
                    messageID: messageID,
                    model: model,
                    usage: usage,
                    cost: cost
                ))
            }
            return nil

        case "text":
            if let delta, !delta.isEmpty {
                return .textDelta(TextDeltaInfo(
                    sessionID: sessionID,
                    messageID: messageID,
                    delta: delta
                ))
            }
            if let time = part["time"] as? [String: Any], time["end"] != nil {
                let text = part["text"] as? String ?? ""
                return .textComplete(TextCompleteInfo(
                    sessionID: sessionID,
                    messageID: messageID,
                    text: text
                ))
            }
            return nil

        case "reasoning":
            if let delta, !delta.isEmpty {
                return .reasoningDelta(ReasoningDeltaInfo(
                    sessionID: sessionID,
                    delta: delta
                ))
            }
            return nil

        case "tool":
            return parseToolPart(part, sessionID: sessionID)

        default:
            return nil
        }
    }

    func parseMessageUpdated(_ properties: [String: Any]) -> SSEEvent? {
        let info = properties["info"] as? [String: Any]
        let fallbackSessionID = properties["sessionID"] as? String ?? ""
        let sessionID = parseString(from: info ?? [:], keys: ["sessionID", "sessionId"]) ?? fallbackSessionID

        // Agent switches (plan <-> build) should stay highest priority.
        let agent = info?["agent"] as? String
        if let agent, !agent.isEmpty {
            return .agentChanged(AgentChangeInfo(sessionID: sessionID, agent: agent))
        }

        // Usage update emitted in message.info (tokens/cost/model).
        if let info,
           let usage = parseTokenUsage(from: info),
           usage.total > 0 {
            let model = parseModelName(from: info) ?? "unknown"
            let cost = parseDouble(from: info["cost"]) ?? 0
            let messageID = parseString(from: info, keys: ["id", "messageID", "messageId"])
            return .usageUpdated(UsageInfo(
                sessionID: sessionID,
                messageID: messageID,
                model: model,
                usage: usage,
                cost: cost
            ))
        }

        return nil
    }

    /// Extract model name from event info.
    func parseModelName(from info: [String: Any]) -> String? {
        if let s = parseString(from: info, keys: ["modelID", "modelId", "model"]) {
            return s
        }
        if let modelDict = info["model"] as? [String: Any] {
            let modelID = modelDict["modelID"] as? String ?? modelDict["modelId"] as? String
            let providerID = modelDict["providerID"] as? String ?? modelDict["providerId"] as? String
            if let mid = modelID {
                if let pid = providerID, !pid.isEmpty {
                    return "\(pid)/\(mid)"
                }
                return mid
            }
        }
        if let metadata = info["metadata"] as? [String: Any] {
            if let s = parseString(from: metadata, keys: ["modelID", "modelId", "model"]) {
                return s
            }
            if let modelDict = metadata["model"] as? [String: Any],
               let mid = modelDict["modelID"] as? String ?? modelDict["modelId"] as? String {
                let pid = modelDict["providerID"] as? String ?? modelDict["providerId"] as? String
                if let pid, !pid.isEmpty {
                    return "\(pid)/\(mid)"
                }
                return mid
            }
        }
        return nil
    }
// PLACEHOLDER_PARSERS_CONTINUE
}

// MARK: - Tool & Session Parsers

extension SSEClient {

    func parseToolPart(_ part: [String: Any], sessionID: String) -> SSEEvent? {
        let state = part["state"] as? [String: Any] ?? [:]
        let toolName = state["tool"] as? String ?? part["tool"] as? String ?? "Tool"
        let status = state["status"] as? String ?? ""
        let toolCallID = state["id"] as? String ?? part["id"] as? String

        let inputDict: [String: Any]?
        if let dict = state["input"] as? [String: Any] {
            inputDict = dict
        } else if let str = state["input"] as? String, !str.isEmpty {
            inputDict = ["_rawInput": str]
        } else if let dict = part["input"] as? [String: Any] {
            inputDict = dict
        } else if let str = part["input"] as? String, !str.isEmpty {
            inputDict = ["_rawInput": str]
        } else {
            inputDict = nil
        }

        switch status {
        case "running", "pending":
            let inputSummary = extractPrimaryInput(from: inputDict)
            return .toolRunning(ToolInfo(
                sessionID: sessionID,
                toolName: toolName,
                toolCallID: toolCallID,
                input: inputDict,
                inputSummary: inputSummary
            ))

        case "completed":
            let output = state["output"] as? String
            let inputSummary = extractPrimaryInput(from: inputDict)
            let metadata = state["metadata"] as? [String: Any]
            let diff = metadata?["diff"] as? String

            // Detect plan_exit completion → agent switches to "build"
            if toolName == "plan_exit" {
                return .agentChanged(AgentChangeInfo(sessionID: sessionID, agent: "build"))
            }

            // Detect plan_enter completion → agent switches to "plan"
            if toolName == "plan_enter" {
                return .agentChanged(AgentChangeInfo(sessionID: sessionID, agent: "plan"))
            }

            return .toolCompleted(ToolCompletedInfo(
                sessionID: sessionID,
                toolName: toolName,
                toolCallID: toolCallID,
                output: output,
                input: inputDict,
                inputSummary: inputSummary,
                diff: diff
            ))

        case "error":
            let error = state["error"] as? String ?? "Unknown tool error"
            return .toolError(ToolErrorInfo(
                sessionID: sessionID,
                toolName: toolName,
                toolCallID: toolCallID,
                error: error
            ))

        default:
            return nil
        }
    }

    func parseSessionStatus(_ properties: [String: Any]) -> SSEEvent? {
        let sessionID = properties["sessionID"] as? String ?? ""
        let status = properties["status"] as? [String: Any] ?? [:]
        let statusType = status["type"] as? String ?? ""

        if statusType == "idle" {
            return .sessionIdle(sessionID: sessionID)
        }

        return .sessionStatus(SessionStatusInfo(
            sessionID: sessionID,
            status: statusType
        ))
    }

    func parseSessionError(_ properties: [String: Any]) -> SSEEvent? {
        let sessionID = properties["sessionID"] as? String ?? ""

        let errorMessage: String
        if let errorStr = properties["error"] as? String {
            errorMessage = errorStr
        } else if let errorObj = properties["error"] as? [String: Any] {
            if let data = errorObj["data"] as? [String: Any],
               let message = data["message"] as? String {
                let name = errorObj["name"] as? String ?? "Error"
                let statusCode = data["statusCode"] as? Int
                if let statusCode {
                    errorMessage = "\(name): \(message) (HTTP \(statusCode))"
                } else {
                    errorMessage = "\(name): \(message)"
                }
            } else if let name = errorObj["name"] as? String {
                errorMessage = name
            } else {
                errorMessage = "Unknown error"
            }
        } else {
            errorMessage = "Unknown error"
        }

        return .sessionError(SessionErrorInfo(
            sessionID: sessionID,
            error: errorMessage
        ))
    }

    func parseQuestionAsked(_ properties: [String: Any]) -> SSEEvent? {
        let id = properties["id"] as? String ?? ""
        let sessionID = properties["sessionID"] as? String ?? ""
        let rawQuestions = properties["questions"] as? [[String: Any]] ?? []

        // Extract tool context when server provides it explicitly.
        let toolDict = properties["tool"] as? [String: Any]
        var toolContext = toolDict?["tool"] as? String

        // OpenCode commonly sends tool metadata as {messageID, callID} without tool name.
        // Detect plan transitions from question content as a robust fallback.
        var planFilePath: String?

        let questions = rawQuestions.map { q -> QuestionRequest.QuestionItem in
            let question = q["question"] as? String ?? ""
            let multiple = q["multiple"] as? Bool ?? false
            let custom = q["custom"] as? Bool ?? true

            var options: [QuestionRequest.QuestionOption] = []
            if let rawOptions = q["options"] as? [[String: Any]] {
                options = rawOptions.map { opt in
                    QuestionRequest.QuestionOption(
                        label: opt["label"] as? String ?? "",
                        description: opt["description"] as? String
                    )
                }
            }

            if toolContext == nil {
                if isPlanExitQuestion(question: question, options: options) {
                    toolContext = "plan_exit"
                } else if isPlanEnterQuestion(question: question, options: options) {
                    toolContext = "plan_enter"
                }
            }

            if planFilePath == nil {
                planFilePath = extractPlanFilePath(from: question)
            }

            return QuestionRequest.QuestionItem(
                question: question,
                options: options,
                multiple: multiple,
                custom: custom
            )
        }

        return .questionAsked(QuestionRequest(
            id: id,
            sessionID: sessionID,
            questions: questions,
            toolContext: toolContext,
            planFilePath: planFilePath
        ))
    }

    func parsePermissionAsked(_ properties: [String: Any]) -> SSEEvent? {
        let id = properties["id"] as? String ?? ""
        let sessionID = properties["sessionID"] as? String ?? ""
        let permission = properties["permission"] as? String ?? ""
        let patterns = properties["patterns"] as? [String] ?? []
        let always = properties["always"] as? [String] ?? []

        var metadata: [String: String] = [:]
        if let rawMeta = properties["metadata"] as? [String: Any] {
            for (key, value) in rawMeta {
                if let str = value as? String {
                    metadata[key] = str
                }
            }
        }

        return .permissionAsked(NativePermissionRequest(
            id: id,
            sessionID: sessionID,
            permission: permission,
            patterns: patterns,
            metadata: metadata,
            always: always
        ))
    }
}

// MARK: - Helpers

extension SSEClient {

    func extractPrimaryInput(from dict: [String: Any]?) -> String? {
        guard let dict else { return nil }
        let keys = ["filePath", "path", "command", "description"]
        return keys.lazy.compactMap { dict[$0] as? String }.first
    }

    func parseTokenUsage(from container: [String: Any]) -> TokenUsage? {
        guard let tokens = container["tokens"] as? [String: Any] else { return nil }
        let input = parseInt(from: tokens["input"]) ?? 0
        let output = parseInt(from: tokens["output"]) ?? 0
        let reasoning = parseInt(from: tokens["reasoning"]) ?? 0
        let cache = tokens["cache"] as? [String: Any] ?? [:]
        let cacheRead = parseInt(from: cache["read"]) ?? 0
        let cacheWrite = parseInt(from: cache["write"]) ?? 0
        return TokenUsage(
            input: input,
            output: output,
            reasoning: reasoning,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite
        )
    }

    func parseInt(from value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let double as Double:
            return Int(double)
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    func parseDouble(from value: Any?) -> Double? {
        switch value {
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    func parseString(from dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func isPlanExitQuestion(
        question: String,
        options: [QuestionRequest.QuestionOption]
    ) -> Bool {
        let normalizedQuestion = question.lowercased()
        let labels = Set(options.map { $0.label.lowercased() })
        let hasYesNo = labels.contains("yes") && labels.contains("no")
        return normalizedQuestion.contains("switch to the build agent")
            || (normalizedQuestion.contains("plan at") && normalizedQuestion.contains("is complete") && hasYesNo)
    }

    func isPlanEnterQuestion(
        question: String,
        options: [QuestionRequest.QuestionOption]
    ) -> Bool {
        let normalizedQuestion = question.lowercased()
        let labels = Set(options.map { $0.label.lowercased() })
        let hasYesNo = labels.contains("yes") && labels.contains("no")
        return normalizedQuestion.contains("switch to the plan agent")
            || (normalizedQuestion.contains("create a plan saved to") && hasYesNo)
    }

    func extractPlanFilePath(from question: String) -> String? {
        let patterns = [
            #"Plan at (.+?) is complete\."#,
            #"create a plan saved to (.+?)\?"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let nsRange = NSRange(question.startIndex..<question.endIndex, in: question)
            guard let match = regex.firstMatch(in: question, options: [], range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: question) else {
                continue
            }
            let path = question[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return path
            }
        }
        return nil
    }
}
