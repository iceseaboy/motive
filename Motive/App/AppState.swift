//
//  AppState.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import Combine
import SwiftData
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum MenuBarState: String, Sendable {
        case idle
        case reasoning
        case executing
        case responding   // Model is outputting response text (not thinking)
    }

    enum SessionStatus: String, Sendable {
        case idle
        case running
        case completed
        case failed
        case interrupted
    }

    @Published var menuBarState: MenuBarState = .idle
    @Published var messages: [ConversationMessage] = []
    @Published var sessionStatus: SessionStatus = .idle
    @Published var lastErrorMessage: String?
    @Published var currentToolName: String?
    @Published var currentToolInput: String?  // Current tool's input (e.g., command, file path)
    @Published var currentContextTokens: Int?
    /// Transient reasoning text — shown live during thinking, cleared when thinking ends.
    /// Not stored in the messages array.
    @Published var currentReasoningText: String?
    /// Task to dismiss reasoning after a short delay
    var reasoningDismissTask: Task<Void, Never>?
    @Published var commandBarResetTrigger: Int = 0  // Increment to trigger reset
    @Published var sessionListRefreshTrigger: Int = 0  // Increment to refresh session list

    let configManager: ConfigManager
    lazy var bridge: OpenCodeBridge = {
        OpenCodeBridge { [weak self] event in
            await MainActor.run { self?.handle(event: event) }
        }
    }()
    var modelContext: ModelContext?
    var currentSession: Session?
    var commandBarController: CommandBarWindowController?
    var statusBarController: StatusBarController?
    var drawerWindowController: DrawerWindowController?
    var quickConfirmController: QuickConfirmWindowController?
    var hasStarted = false
    private var seenUsageMessageIds = Set<String>()

    // CloudKit for remote commands from iOS
    lazy var cloudKitManager: CloudKitManager = CloudKitManager()
    var currentRemoteCommandId: String?
    
    /// UI-level session activity timeout
    /// If sessionStatus stays .running with no events for this duration, show a warning
    var sessionTimeoutTask: Task<Void, Never>?
    static let sessionTimeoutSeconds: TimeInterval = 120  // 2 minutes
    
    /// Tracks the message ID for the current question/permission so we can update it with the user's response
    var pendingQuestionMessageId: UUID?
    
    var cancellables = Set<AnyCancellable>()
    
    /// When true, the agent will auto-restart as soon as the current task finishes.
    @Published var pendingAgentRestart = false
    private var restartObserver: AnyCancellable?

    var configManagerRef: ConfigManager { configManager }
    var commandBarWindowRef: NSWindow? { commandBarController?.getWindow() }
    var currentSessionRef: Session? { currentSession }

    init(configManager: ConfigManager) {
        self.configManager = configManager
    }
    
    /// Schedule an agent restart that respects running tasks.
    /// - If no task is running (`menuBarState == .idle`), restarts immediately.
    /// - If a task is running, defers the restart until it finishes.
    func scheduleAgentRestart() {
        guard menuBarState == .idle else {
            // Task is running — defer restart
            pendingAgentRestart = true
            installRestartObserver()
            return
        }
        // Idle — restart immediately
        pendingAgentRestart = false
        restartAgent()
    }
    
    /// Observe menuBarState transitions to .idle and auto-restart when pending.
    private func installRestartObserver() {
        // Avoid duplicate observers
        guard restartObserver == nil else { return }
        restartObserver = $menuBarState
            .removeDuplicates()
            .filter { $0 == .idle }
            .sink { [weak self] _ in
                guard let self, self.pendingAgentRestart else { return }
                self.pendingAgentRestart = false
                self.restartObserver = nil
                self.restartAgent()
            }
    }

    func resetUsageDeduplication() {
        seenUsageMessageIds.removeAll()
    }

    func recordUsageMessageId(sessionId: String, messageId: String) -> Bool {
        let key = "\(sessionId)::\(messageId)"
        if seenUsageMessageIds.contains(key) {
            return false
        }
        seenUsageMessageIds.insert(key)
        return true
    }
}
