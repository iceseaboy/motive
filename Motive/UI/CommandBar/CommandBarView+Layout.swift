//
//  CommandBarView+Layout.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension CommandBarView {
    var isDark: Bool { colorScheme == .dark }

    // Filtered commands based on input
    var filteredCommands: [CommandDefinition] {
        let query = inputText.hasPrefix("/") ? String(inputText.dropFirst()) : ""
        return CommandDefinition.matching(query)
    }

    var mainContent: some View {
        VStack(spacing: 0) {
            if showsAboveContent {
                aboveInputContent
                Rectangle()
                    .fill(Color.Aurora.glassOverlay.opacity(0.06))
                    .frame(height: 0.5)
            }
            inputAreaView
            if showsBelowContent {
                Rectangle()
                    .fill(Color.Aurora.glassOverlay.opacity(0.06))
                    .frame(height: 0.5)
                belowInputContent
            } else {
                // Only use spacer when no list content
                Spacer(minLength: 0)
            }
            footerView
        }
        .frame(width: 680, height: currentHeight)
        .background(commandBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous))
        .overlay(borderOverlay)
        // Note: Window-level fade animation is handled by CommandBarWindowController
        // Removed SwiftUI-level entrance animation to prevent double animation
    }

    // Content ABOVE input (session status)
    var showsAboveContent: Bool {
        switch mode {
        case .running, .completed, .error:
            return true
        case .command(let fromSession), .history(let fromSession), .modes(let fromSession):
            // Keep status visible when command/history/modes triggered from session
            return fromSession
        default:
            return false
        }
    }

    // Content BELOW input (lists)
    var showsBelowContent: Bool {
        mode.isCommand || mode.isHistory || mode.isProjects || mode.isModes
            || isFileCompletionActive
    }

    /// Height to use when file completion is showing (matches command list)
    var fileCompletionHeight: CGFloat {
        showsAboveContent ? 450 : 400
    }

    /// Whether file completion should actively affect height.
    /// Guards against stale `showFileCompletion` state by cross-checking the input.
    var isFileCompletionActive: Bool {
        showFileCompletion
            && !fileCompletion.items.isEmpty
            && currentAtToken(in: inputText) != nil
    }

    /// Current command bar height
    var currentHeight: CGFloat {
        isFileCompletionActive ? fileCompletionHeight : mode.dynamicHeight
    }

    // MARK: - Above Input Content (Session Status)

    @ViewBuilder
    var aboveInputContent: some View {
        Group {
            switch mode {
            case .running:
                runningStatusView
            case .completed:
                completedSummaryView
            case .error(let message):
                errorStatusView(message: message)
            case .command(let fromSession) where fromSession:
                // Show completed status when command triggered from session
                completedSummaryView
            case .history(let fromSession) where fromSession:
                // Show completed status when history triggered from session
                completedSummaryView
            case .modes(let fromSession) where fromSession:
                completedSummaryView
            default:
                EmptyView()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Below Input Content (Lists)

    @ViewBuilder
    var belowInputContent: some View {
        Group {
            if isFileCompletionActive {
                // File completion takes priority
                fileCompletionListView
            } else if mode.isCommand {
                commandListView
            } else if mode.isHistory {
                historiesListView
            } else if mode.isProjects {
                projectsListView
            } else if mode.isModes {
                modesListView
            } else {
                EmptyView()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - File Completion List (below input)

    var fileCompletionListView: some View {
        FileCompletionView(
            items: fileCompletion.items,
            selectedIndex: selectedFileIndex,
            currentPath: fileCompletion.currentPath,
            onSelect: selectFileCompletion
        )
        .id("fileCompletion-\(fileCompletion.currentPath)-\(fileCompletion.items.count)")
    }

    /// Autocomplete hint for command input (Raycast style)
    var autocompleteHint: String? {
        // Only show hint when input starts with "/" and we have matching commands
        guard inputText.hasPrefix("/"), !filteredCommands.isEmpty else { return nil }

        let query = String(inputText.dropFirst()) // Remove "/"
        let firstMatch = filteredCommands[selectedCommandIndex]

        // Return the full command name for hint
        return "/\(firstMatch.name)"
    }

    /// The portion of hint that should be shown as completion (gray text after input)
    var autocompleteCompletion: String? {
        guard let hint = autocompleteHint else { return nil }

        // If input is shorter than hint, return the remaining part
        if inputText.count < hint.count && hint.lowercased().hasPrefix(inputText.lowercased()) {
            return String(hint.dropFirst(inputText.count))
        }
        return nil
    }
}
