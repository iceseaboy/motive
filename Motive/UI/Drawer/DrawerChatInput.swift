//
//  DrawerChatInput.swift
//  Motive
//
//  Aurora Design System - Drawer chat input area
//

import SwiftUI

struct DrawerChatInput: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var configManager: ConfigManager
    @Binding var inputText: String
    var isInputFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onTextChange: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        let isRunning = appState.sessionStatus == .running

        VStack(spacing: 0) {
            // Project directory + agent mode (compact top meta row)
            HStack(spacing: AuroraSpacing.space2) {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.Aurora.textMuted)

                Text(configManager.currentProjectShortPath)
                    .font(.Aurora.micro)
                    .foregroundColor(Color.Aurora.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let contextTokens = appState.currentContextTokens {
                    ContextSizeBadge(tokens: contextTokens)
                        .fixedSize(horizontal: true, vertical: true)
                }

                // Agent mode toggle
                AgentModeToggle(
                    currentAgent: configManager.currentAgent,
                    isRunning: isRunning,
                    onChange: { newAgent in
                        configManager.currentAgent = newAgent
                        appState.currentSessionAgent = newAgent
                        configManager.generateOpenCodeConfig()
                        appState.reconfigureBridge()
                    }
                )
                .fixedSize(horizontal: true, vertical: true)
            }
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space2)

            Rectangle()
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.12))
                .frame(height: 0.5)

            HStack(spacing: AuroraSpacing.space3) {
                HStack(spacing: AuroraSpacing.space2) {
                    TextField("", text: $inputText, prompt: Text(L10n.Drawer.messagePlaceholder)
                        .foregroundColor(Color.Aurora.textMuted))
                        .textFieldStyle(.plain)
                        .font(.Aurora.body)
                        .foregroundColor(Color.Aurora.textPrimary)
                        .focused(isInputFocused)
                        .onSubmit(onSubmit)
                        .disabled(isRunning)
                        .onChange(of: inputText) { _, newValue in
                            onTextChange(newValue)
                        }

                    if isRunning {
                        // Stop button when running
                        Button(action: { appState.interruptSession() }) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.Aurora.error)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.Drawer.stop)
                    } else {
                        // Send button when not running
                        Button(action: onSubmit) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(inputText.isEmpty ? Color.Aurora.textMuted : Color.Aurora.primary)
                        }
                        .buttonStyle(.plain)
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel(L10n.CommandBar.submit)
                    }
                }
                .padding(.horizontal, AuroraSpacing.space3)
                .padding(.vertical, AuroraSpacing.space2)
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .fill(isDark ? Color.Aurora.glassOverlay.opacity(0.06) : Color.white.opacity(0.55))
                )
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(
                            isInputFocused.wrappedValue && !isRunning
                                ? Color.Aurora.borderFocus.opacity(0.8)
                                : Color.Aurora.glassOverlay.opacity(isDark ? 0.1 : 0.15),
                            lineWidth: isInputFocused.wrappedValue && !isRunning ? 1 : 0.5
                        )
                )
                .animation(.auroraFast, value: isInputFocused.wrappedValue)
            }
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space3)
            .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.08))
        }
    }
}
