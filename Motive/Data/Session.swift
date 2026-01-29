//
//  Session.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Foundation
import SwiftData

@Model
final class Session {
    var id: UUID
    var intent: String
    var createdAt: Date
    var openCodeSessionId: String?  // OpenCode CLI session ID for resuming
    var status: String = "completed"  // running, completed, failed, interrupted (default for migration)
    /// Project directory used when the session was created (resolved path)
    var projectPath: String = ""
    @Relationship(deleteRule: .cascade) var logs: [LogEntry]

    init(id: UUID = UUID(), intent: String, createdAt: Date = Date(), openCodeSessionId: String? = nil, status: String = "running", projectPath: String = "", logs: [LogEntry] = []) {
        self.id = id
        self.intent = intent
        self.createdAt = createdAt
        self.openCodeSessionId = openCodeSessionId
        self.status = status
        self.projectPath = projectPath
        self.logs = logs
    }
}
