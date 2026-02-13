//
//  CommandBarInput.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension CommandBarView {
    // MARK: - Input Area (Always Visible - No icons, status shown above)

    var inputAreaView: some View {
        HStack(spacing: AuroraSpacing.space3) {
            // Input field with inline autocomplete hint
            ZStack(alignment: .leading) {
                // Autocomplete hint (gray completion text)
                if let completion = autocompleteCompletion {
                    HStack(spacing: 0) {
                        // Invisible spacer for the typed text width
                        Text(inputText)
                            .font(.system(size: 17, weight: .regular))
                            .opacity(0)

                        // Gray completion hint
                        Text(completion)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(Color.Aurora.textMuted)
                    }
                }

                // Actual input field
                CommandBarTextField(
                    text: $inputText,
                    placeholder: placeholderText,
                    isDisabled: mode == .running,
                    onSubmit: handleSubmit,
                    onCmdDelete: {
                        if mode.isHistory {
                            handleCmdDelete()
                        }
                    },
                    onCmdN: handleCmdN,
                    onCmdReturn: nil,
                    onEscape: handleEscape
                )
                .focused($isInputFocused)
                .accessibilityLabel("Command input")
                .accessibilityHint("Type a command or question, then press Return to submit")
            }

            // Tab hint when autocomplete is available
            if autocompleteCompletion != nil {
                Text("Tab")
                    .font(.Aurora.micro.weight(.medium))
                    .foregroundColor(Color.Aurora.textMuted)
                    .padding(.horizontal, AuroraSpacing.space2)
                    .padding(.vertical, AuroraSpacing.space1)
                    .background(
                        RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                            .fill(Color.Aurora.glassOverlay.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                            .strokeBorder(Color.Aurora.glassOverlay.opacity(0.1), lineWidth: 0.5)
                    )
            }

            // Action button
            actionButton
        }
        .frame(height: 54)
        .padding(.horizontal, AuroraSpacing.space6)
    }

    var placeholderText: String {
        switch mode {
        case .command:
            return "Type a command..."
        case .history:
            return "Search sessions..."
        case .running, .completed, .error:
            return "Follow up..."  // Status shown above, not in placeholder
        default:
            return L10n.CommandBar.placeholder
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    var actionButton: some View {
        if !configManager.hasAPIKey {
            Button(action: {
                appState.hideCommandBar()
                SettingsWindowController.shared.show(tab: .model)
            }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.Aurora.warning)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("API key required")
            .accessibilityHint("Opens settings to configure API key")
        } else if case .error = mode {
            Button(action: { mode = .idle }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.Aurora.error)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry")
            .accessibilityHint("Clears the error and allows you to try again")
        } else {
            let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isCommandInput = inputText.hasPrefix("/")
            if canSend && !isCommandInput {
                Button(action: handleSubmit) {
                    Image(systemName: "return")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.Aurora.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Submit")
                .accessibilityHint("Sends your command to the AI assistant")
            } else {
                EmptyView()
            }
        }
    }
}
