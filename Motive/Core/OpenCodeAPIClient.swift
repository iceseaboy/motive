//
//  OpenCodeAPIClient.swift
//  Motive
//
//  REST API client for OpenCode's HTTP server.
//  Handles session management, prompt submission, and native question/permission replies.
//

import Foundation
import os

/// REST API client for all interactions with the OpenCode HTTP server.
///
/// All prompt execution is fire-and-forget via `prompt_async` — results
/// stream back through the SSE connection managed by `SSEClient`.
actor OpenCodeAPIClient {

    // MARK: - Types

    /// Reply types for native permission requests.
    enum PermissionReply: Sendable {
        case once           // Allow this single request
        case always         // Allow and remember for future matching
        case reject(String?) // Deny with optional message

        var wireValue: String {
            switch self {
            case .once: return "once"
            case .always: return "always"
            case .reject: return "reject"
            }
        }
    }

    /// Session info returned from the server.
    struct SessionInfo: Sendable {
        let id: String
        let title: String?
    }

    enum APIError: Error, LocalizedError {
        case noBaseURL
        case httpError(statusCode: Int, body: String?)
        case decodingError(String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .noBaseURL:
                return "API client has no base URL configured"
            case .httpError(let code, let body):
                let detail = body.map { " — \($0)" } ?? ""
                return "HTTP \(code)\(detail)"
            case .decodingError(let msg):
                return "Response decoding failed: \(msg)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Properties

    private var baseURL: URL?
    private var directory: String = ""
    private let session: URLSession
    private let logger = Logger(subsystem: "com.velvet.motive", category: "OpenCodeAPI")

    // MARK: - Init

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Configuration

    func updateBaseURL(_ url: URL) {
        self.baseURL = url
        logger.info("API base URL updated to \(url.absoluteString)")
    }

    func updateDirectory(_ path: String) {
        self.directory = path
    }

    // MARK: - Session Management

    /// Create a new session.
    func createSession(title: String? = nil) async throws -> SessionInfo {
        var body: [String: Any] = [:]
        if let title {
            body["title"] = title
        }

        let responseData = try await post(path: "/session", body: body)

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let id = json["id"] as? String else {
            throw APIError.decodingError("Missing session ID in response")
        }

        let sessionTitle = json["title"] as? String
        logger.info("Created session: \(id)")
        return SessionInfo(id: id, title: sessionTitle)
    }

    /// Abort an active session.
    func abortSession(id: String) async throws {
        _ = try await post(path: "/session/\(id)/abort", body: [:])
        logger.info("Aborted session: \(id)")
    }

    // MARK: - Prompt

    /// Send a prompt asynchronously. Returns immediately (204).
    /// Results stream via SSE.
    ///
    /// - Parameters:
    ///   - sessionID: The target session.
    ///   - text: The user's prompt text.
    ///   - model: Provider/model string (e.g. `"anthropic/claude-sonnet-4-5-20250929"`).
    ///     Split into `{ providerID, modelID }` for the server.
    func sendPromptAsync(
        sessionID: String,
        text: String,
        model: String? = nil
    ) async throws {
        var body: [String: Any] = [
            "parts": [
                ["type": "text", "text": text]
            ]
        ]

        // Server expects model as { providerID, modelID }, not a flat string
        if let model {
            let components = model.split(separator: "/", maxSplits: 1)
            if components.count == 2 {
                body["model"] = [
                    "providerID": String(components[0]),
                    "modelID": String(components[1]),
                ]
            }
        }

        _ = try await post(
            path: "/session/\(sessionID)/prompt_async",
            body: body,
            expectedStatus: 204
        )
        logger.info("Sent prompt to session \(sessionID)")
    }

    // MARK: - Native Question Reply

    /// Reply to a question asked by OpenCode's native question tool.
    ///
    /// - Parameters:
    ///   - requestID: The question request ID from the SSE event.
    ///   - answers: Array of answer arrays (one per question). Each inner array
    ///     contains the selected option labels or custom text.
    func replyToQuestion(requestID: String, answers: [[String]]) async throws {
        let body: [String: Any] = [
            "answers": answers
        ]

        _ = try await post(path: "/question/\(requestID)/reply", body: body)
        logger.info("Replied to question \(requestID)")
    }

    /// Reject a question (user cancelled).
    func rejectQuestion(requestID: String) async throws {
        let body: [String: Any] = [
            "answers": [] as [[String]]
        ]

        _ = try await post(path: "/question/\(requestID)/reply", body: body)
        logger.info("Rejected question \(requestID)")
    }

    // MARK: - Native Permission Reply

    /// Reply to a permission request from OpenCode's native permission system.
    ///
    /// - Parameters:
    ///   - requestID: The permission request ID from the SSE event.
    ///   - reply: `.once`, `.always`, or `.reject(message:)`.
    func replyToPermission(requestID: String, reply: PermissionReply) async throws {
        var body: [String: Any] = [
            "reply": reply.wireValue
        ]

        if case .reject(let message) = reply, let message {
            body["message"] = message
        }

        _ = try await post(path: "/permission/\(requestID)/reply", body: body)
        logger.info("Replied to permission \(requestID) with \(reply.wireValue)")
    }

    // MARK: - HTTP Helpers

    private func post(
        path: String,
        body: [String: Any],
        expectedStatus: Int? = nil
    ) async throws -> Data {
        guard let baseURL else {
            throw APIError.noBaseURL
        }

        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Set the working directory header
        if !directory.isEmpty {
            request.setValue(directory, forHTTPHeaderField: "x-opencode-directory")
        }

        // Always send a JSON body — even `{}` — because the server's JSON
        // validator will reject a request with Content-Type: application/json
        // but no body ("Malformed JSON in request body").
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.httpError(statusCode: -1, body: nil)
        }

        let status = httpResponse.statusCode
        if let expected = expectedStatus {
            // Accept exact match or close range
            guard status == expected || (expected == 204 && status >= 200 && status < 300) else {
                let bodyStr = String(data: data, encoding: .utf8)
                throw APIError.httpError(statusCode: status, body: bodyStr)
            }
        } else {
            guard (200...299).contains(status) else {
                let bodyStr = String(data: data, encoding: .utf8)
                throw APIError.httpError(statusCode: status, body: bodyStr)
            }
        }

        return data
    }
}
