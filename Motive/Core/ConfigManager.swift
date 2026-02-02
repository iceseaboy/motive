//
//  ConfigManager.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class ConfigManager: ObservableObject {
    enum Provider: String, CaseIterable, Identifiable {
        case claude
        case openai
        case gemini
        case ollama

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .claude: return "Claude"
            case .openai: return "OpenAI"
            case .gemini: return "Gemini"
            case .ollama: return "Ollama"
            }
        }
    }

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
        
        var localizedName: String {
            switch self {
            case .system: return L10n.Settings.themeSystem
            case .light: return L10n.Settings.themeLight
            case .dark: return L10n.Settings.themeDark
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }
    
    @AppStorage("provider") var providerRawValue: String = Provider.claude.rawValue
    
    // Per-provider configurations
    @AppStorage("claude.baseURL") var claudeBaseURL: String = ""
    @AppStorage("claude.modelName") var claudeModelName: String = ""
    @AppStorage("openai.baseURL") var openaiBaseURL: String = ""
    @AppStorage("openai.modelName") var openaiModelName: String = ""
    @AppStorage("gemini.baseURL") var geminiBaseURL: String = ""
    @AppStorage("gemini.modelName") var geminiModelName: String = ""
    @AppStorage("ollama.baseURL") var ollamaBaseURL: String = "http://localhost:11434"
    @AppStorage("ollama.modelName") var ollamaModelName: String = ""
    
    @AppStorage("openCodeBinarySourcePath") var openCodeBinarySourcePath: String = ""
    @AppStorage("debugMode") var debugMode: Bool = false
    @AppStorage("launchAtLoginStorage") private var launchAtLoginStorage: Bool = false
    @AppStorage("languageRawValue") var languageRawValue: String = Language.system.rawValue
    
    // Browser automation settings (browser-use-sidecar)
    @AppStorage("browserUseEnabled") var browserUseEnabled: Bool = false
    @AppStorage("browserUseHeadedMode") var browserUseHeadedMode: Bool = true  // Show browser window by default
    @AppStorage("browserAgentProvider") var browserAgentProviderRaw: String = "anthropic"
    var cachedBrowserAgentAPIKey: String?
    @AppStorage("browserAgentBaseUrl_anthropic") var browserAgentBaseUrlAnthropic: String = ""
    @AppStorage("browserAgentBaseUrl_openai") var browserAgentBaseUrlOpenAI: String = ""

    // Skills system (OpenClaw-style)
    @AppStorage("skillsSystemEnabled") var skillsSystemEnabled: Bool = true
    @AppStorage("skillsConfigJSON") var skillsConfigJSON: String = ""
    

    @AppStorage("hotkey") var hotkey: String = "⌥Space"
    @AppStorage("appearanceMode") var appearanceModeRawValue: String = AppearanceMode.system.rawValue
    
    // Onboarding
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    // Project directory
    @AppStorage("currentProjectPath") var currentProjectPath: String = ""
    @AppStorage("recentProjectsJSON") var recentProjectsJSON: String = "[]"
    
    /// Launch at Login with actual ServiceManagement implementation
    var launchAtLogin: Bool {
        get { launchAtLoginStorage }
        set {
            launchAtLoginStorage = newValue
            updateLaunchAtLogin(newValue)
        }
    }
    
    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                Log.config(" Registered for launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                Log.config(" Unregistered from launch at login")
            }
        } catch {
            Log.config(" Failed to update launch at login: \(error)")
        }
    }

    let keychainService = "com.velvet.motive"
    
    // Cache API keys per provider
    var cachedAPIKeys: [Provider: String] = [:]
    
    /// Migrate legacy per-account keychain items to unified storage
    /// This ensures only ONE authorization prompt for all API keys
    private func migrateKeychainIfNeeded() {
        // Build list of all possible legacy account names
        var legacyAccounts: [String] = []
        
        // AI provider accounts
        for provider in Provider.allCases {
            legacyAccounts.append("opencode.api.key.\(provider.rawValue)")
        }
        
        // Browser agent accounts
        for provider in Provider.allCases {
            legacyAccounts.append("browser.agent.api.key.\(provider.rawValue)")
        }
        
        KeychainStore.migrateToUnifiedStorage(service: keychainService, accounts: legacyAccounts)
    }
    
    /// Preload current provider's API key into cache
    /// Call this once at startup to trigger Keychain prompt early
    /// Now triggers only ONE prompt thanks to unified storage
    func preloadAPIKeys() {
        // First, migrate any legacy keychain items (one-time)
        migrateKeychainIfNeeded()
        
        // Read current provider's key (single unified Keychain read)
        let account = "opencode.api.key.\(provider.rawValue)"
        let value = KeychainStore.read(service: keychainService, account: account) ?? ""
        cachedAPIKeys[provider] = value
        
        // Read browser agent key from the same unified storage (no additional prompt)
        if browserUseEnabled {
            let browserAccount = "browser.agent.api.key.\(browserAgentProvider.rawValue)"
            let browserValue = KeychainStore.read(service: keychainService, account: browserAccount) ?? ""
            cachedBrowserAgentAPIKey = browserValue
        }
    }
    
    // Published status for UI
    @Published var binaryStatus: BinaryStatus = .notConfigured
    
    enum BinaryStatus: Equatable {
        case notConfigured
        case ready(String) // path
        case error(String)
    }

    var provider: Provider {
        get { Provider(rawValue: providerRawValue) ?? .claude }
        set { 
            providerRawValue = newValue.rawValue
            objectWillChange.send()
        }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRawValue) ?? .system }
        set { 
            appearanceModeRawValue = newValue.rawValue
            applyAppearance(newValue)
        }
    }
    
    /// Apply the appearance mode to the application
    func applyAppearance(_ mode: AppearanceMode? = nil) {
        let targetMode = mode ?? appearanceMode
        DispatchQueue.main.async {
            switch targetMode {
            case .system:
                NSApp.appearance = nil  // Follow system
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
    
    /// Path to generated opencode.json config
    @AppStorage("openCodeConfigPath") var openCodeConfigPath: String = ""
    @AppStorage("openCodeConfigDir") var openCodeConfigDir: String = ""

    // MARK: - Errors
    
    enum BinaryError: LocalizedError {
        case noAppSupport
        case sourceNotFound(String)
        case signingFailed(String)
        case directoryCreationFailed(String, String)
        case copyFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .noAppSupport:
                return "Cannot access storage directory"
            case .sourceNotFound(let path):
                return "Binary not found at: \(path)"
            case .signingFailed(let message):
                return "Failed to sign binary: \(message)"
            case .directoryCreationFailed(let path, let reason):
                return "Cannot create directory at \(path): \(reason)"
            case .copyFailed(let reason):
                return "Failed to copy binary: \(reason)"
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let languageDidChange = Notification.Name("languageDidChange")
}
