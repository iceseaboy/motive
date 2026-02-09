//
//  AppState+Lifecycle.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import Combine
import SwiftData
import SwiftUI

extension AppState {
    func attachModelContext(_ context: ModelContext) {
        modelContext = context
        createCommandBarIfNeeded()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // Ensure workspace exists (creates bootstrap files for fresh install)
        Task { @MainActor in
            do {
                try await WorkspaceManager.shared.ensureWorkspace()
            } catch {
                Log.config("Failed to ensure workspace: \(error)")
            }
        }
        
        // Ensure default project directory exists
        configManager.ensureDefaultProjectDirectory()
        configManager.ensureCurrentProjectInRecents()

        // Preload API keys early to trigger Keychain prompts at startup
        // This avoids scattered prompts during usage
        configManager.preloadAPIKeys()

        // Initialize SkillManager with ConfigManager to enable browser automation skill
        SkillManager.shared.setConfigManager(configManager)
        SkillRegistry.shared.setConfigManager(configManager)

        observeMenuBarState()
        Task {
            await configureBridge()
            await bridge.startIfNeeded()
        }
        ensureStatusBar()
        drawerWindowController = DrawerWindowController(
            rootView: DrawerView()
                .environmentObject(self)
                .environmentObject(configManager)
        )
        // Configure settings window controller
        SettingsWindowController.shared.configure(configManager: configManager, appState: self)
        updateStatusBar()

        // Start CloudKit listener for remote commands from iOS
        startCloudKitListener()
    }

    /// Start listening for remote commands from iOS via CloudKit
    private func startCloudKitListener() {
        cloudKitManager.onCommandReceived = { [weak self] command in
            guard let self else { return }
            self.handleRemoteCommand(command)
        }
        cloudKitManager.startListening(appState: self)
        Log.debug("CloudKit listener started for remote commands")
    }

    /// Handle a remote command received from iOS
    private func handleRemoteCommand(_ command: RemoteCommand) {
        Log.debug("Received remote command: \(command.instruction)")

        // Store the remote command ID for status updates
        currentRemoteCommandId = command.id

        // Use the configured project directory as working directory
        let cwd = configManager.currentProjectURL.path

        // Submit the intent just like local commands
        submitIntent(command.instruction, workingDirectory: cwd)
    }

    func ensureStatusBar() {
        if statusBarController == nil {
            statusBarController = StatusBarController(delegate: self)
            statusBarController?.configure(configManager: configManager)
        }
        updateStatusBar()
    }

    func updateStatusBar() {
        let isWaiting = pendingQuestionMessageId != nil
        let inputType = "Question"
        statusBarController?.update(
            state: menuBarState,
            toolName: currentToolName,
            isWaitingForInput: isWaiting,
            inputType: inputType
        )
    }

    private func observeMenuBarState() {
        // Debounce menu bar state updates to avoid "multiple times per frame" warning
        $menuBarState
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main) // ~1 frame at 60fps
            .sink { [weak self] state in
                guard let self else { return }
                let isWaiting = self.pendingQuestionMessageId != nil
                let inputType = "Question"
                self.statusBarController?.update(
                    state: state,
                    toolName: self.currentToolName,
                    isWaitingForInput: isWaiting,
                    inputType: inputType
                )
            }
            .store(in: &cancellables)
    }

    private func createCommandBarIfNeeded() {
        guard commandBarController == nil, let modelContext else { return }
        let rootView = CommandBarView()
            .environmentObject(self)
            .environmentObject(configManager)
            .environment(\.modelContext, modelContext)
        commandBarController = CommandBarWindowController(rootView: rootView)
        // No pre-warm needed - window uses defer:true and alpha:0
        // First show will be slightly slower but avoids visual glitches
    }
}
