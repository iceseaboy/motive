//
//  AdvancedSettingsView.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @EnvironmentObject private var configManager: ConfigManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var importError: String?
    
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Binary Section
            SettingsCard(title: L10n.Settings.openCodeBinary, icon: "terminal") {
                VStack(spacing: 0) {
                    // Status Row
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.Settings.binaryStatus)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.Velvet.textPrimary)
                            
                            binaryStatusText
                        }
                        
                        Spacer()
                        
                        binaryStatusIcon
                    }
                    .padding(16)
                    
                    Divider()
                        .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                        .padding(.leading, 16)
                    
                    // Source Path (if set)
                    if !configManager.openCodeBinarySourcePath.isEmpty {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.Settings.sourcePath)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color.Velvet.textPrimary)
                                
                                Text(configManager.openCodeBinarySourcePath)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Color.Velvet.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            Spacer()
                        }
                        .padding(16)
                        
                        Divider()
                            .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                            .padding(.leading, 16)
                    }
                    
                    // Actions
                    HStack(spacing: 12) {
                        Button {
                            showFileImporter = true
                        } label: {
                            HStack(spacing: 6) {
                                if isImporting {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11))
                                }
                                Text(isImporting ? L10n.Settings.importing : L10n.Settings.selectBinary)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(Color.Velvet.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting)
                        
                        Button {
                            autoDetectAndImport()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 11))
                                Text(L10n.Settings.autoDetect)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(Color.Velvet.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting)
                        
                        Spacer()
                    }
                    .padding(16)
                }
            }
            
            // Import Error
            if let error = importError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.Velvet.error)
                    
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Velvet.error)
                    
                    Spacer()
                    
                    Button {
                        importError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.Velvet.error.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.Velvet.error.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.Velvet.error.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Browser Automation Section
            SettingsCard(title: "Browser Automation", icon: "globe") {
                VStack(spacing: 0) {
                    // Enable toggle
                    SettingsRow(label: "Enable Browser Control", description: "AI-powered browser automation using bundled sidecar") {
                        Toggle("", isOn: $configManager.browserUseEnabled)
                            .toggleStyle(.switch)
                            .tint(Color.Velvet.primary)
                            .onChange(of: configManager.browserUseEnabled) { _, newValue in
                                // Reload skills when toggled
                                SkillManager.shared.reloadSkills()
                                appState.restartAgent()
                            }
                    }
                    
                    if configManager.browserUseEnabled {
                        // Headed mode toggle
                        SettingsRow(label: "Show Browser Window", description: "Display browser during automation (headed mode)") {
                            Toggle("", isOn: $configManager.browserUseHeadedMode)
                                .toggleStyle(.switch)
                                .tint(Color.Velvet.primary)
                                .onChange(of: configManager.browserUseHeadedMode) { _, _ in
                                    SkillManager.shared.reloadSkills()
                                    appState.restartAgent()
                                }
                        }
                        
                        // Status row
                        browserUseStatusRow
                    }
                }
            }
            
            // Debug Section
            SettingsCard(title: L10n.Settings.diagnostics, icon: "ant") {
                SettingsRow(label: L10n.Settings.debugMode, description: L10n.Settings.debugModeDesc, showDivider: false) {
                    Toggle("", isOn: $configManager.debugMode)
                        .toggleStyle(.switch)
                        .tint(Color.Velvet.primary)
                }
            }
            
            // About Section
            SettingsCard(title: L10n.Settings.about, icon: "info.circle") {
                VStack(spacing: 0) {
                    aboutRow(L10n.Settings.version, value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                    aboutRow(L10n.Settings.build, value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1", showDivider: false)
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.unixExecutable, .item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importBinary(from: url)
            }
        }
        .onAppear {
            _ = configManager.resolveBinary()
        }
    }
    
    // MARK: - Binary Status
    
    private var binaryStatusText: some View {
        Group {
            switch configManager.binaryStatus {
            case .notConfigured:
                Text(L10n.Settings.notConfigured)
                    .font(.system(size: 11))
                    .foregroundColor(Color.Velvet.warning)
            case .ready(let path):
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.Velvet.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            case .error(let error):
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Color.Velvet.error)
            }
        }
    }
    
    private var binaryStatusIcon: some View {
        Group {
            switch configManager.binaryStatus {
            case .notConfigured:
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.Velvet.warning)
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.Velvet.success)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.Velvet.error)
            }
        }
    }
    
    // MARK: - About Row
    
    private func aboutRow(_ label: String, value: String, showDivider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.Velvet.textSecondary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color.Velvet.textMuted)
            }
            .padding(16)
            
            if showDivider {
                Divider()
                    .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                    .padding(.leading, 16)
            }
        }
    }
    
    // MARK: - Browser Automation Status
    
    @ViewBuilder
    private var browserUseStatusRow: some View {
        let status = configManager.browserUseStatus
        
        SettingsRow(label: "Status", description: browserUseStatusDescription(status), showDivider: false) {
            browserUseStatusIcon(status)
        }
    }
    
    private func browserUseStatusDescription(_ status: ConfigManager.BrowserUseStatus) -> String {
        switch status {
        case .ready:
            return "Ready - sidecar binary available"
        case .binaryNotFound:
            return "Build required - run Scripts/browser-use-sidecar/build.sh"
        case .disabled:
            return "Browser automation is disabled"
        }
    }
    
    @ViewBuilder
    private func browserUseStatusIcon(_ status: ConfigManager.BrowserUseStatus) -> some View {
        switch status {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(Color.Velvet.success)
        case .binaryNotFound:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(Color.Velvet.warning)
        case .disabled:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(Color.Velvet.textMuted)
        }
    }
    
    // MARK: - Actions
    
    private func importBinary(from url: URL) {
        isImporting = true
        importError = nil
        
        Task {
            do {
                try await configManager.importBinary(from: url)
                appState.restartAgent()
            } catch {
                importError = error.localizedDescription
            }
            isImporting = false
        }
    }
    
    private func autoDetectAndImport() {
        isImporting = true
        importError = nil
        
        Task {
            let result = await configManager.getSignedBinaryURL()
            if let error = result.error {
                importError = error
            } else {
                appState.restartAgent()
            }
            isImporting = false
        }
    }
}
