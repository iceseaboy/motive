//
//  ConfigManager+Provider.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Foundation

extension ConfigManager {
    // MARK: - Per-Provider Configuration Accessors
    
    /// Base URL for current provider
    var baseURL: String {
        get { providerConfigStore.baseURL(for: provider) }
        set { providerConfigStore.setBaseURL(newValue, for: provider) }
    }

    /// Model name for current provider
    var modelName: String {
        get { providerConfigStore.modelName(for: provider) }
        set { providerConfigStore.setModelName(newValue, for: provider) }
    }
    
    /// API Key for current provider (stored in Keychain per-provider)
    var apiKey: String {
        get {
            if let cached = cachedAPIKeys[provider] {
                return cached
            }
            let account = "opencode.api.key.\(provider.rawValue)"
            let value = KeychainStore.read(service: keychainService, account: account) ?? ""
            cachedAPIKeys[provider] = value
            return value
        }
        set {
            cachedAPIKeys[provider] = newValue
            let account = "opencode.api.key.\(provider.rawValue)"
            if newValue.isEmpty {
                KeychainStore.delete(service: keychainService, account: account)
            } else {
                KeychainStore.write(service: keychainService, account: account, value: newValue)
            }
        }
    }

    var hasAPIKey: Bool {
        // Check if provider requires API key
        if !provider.requiresAPIKey { return true }
        // Check cache first to avoid Keychain prompt
        if let cached = cachedAPIKeys[provider] {
            return !cached.isEmpty
        }
        // Fall back to full check (will trigger Keychain if needed)
        return !apiKey.isEmpty
    }
    
    /// Check if current provider is properly configured
    var isProviderConfigured: Bool {
        switch provider {
        case .ollama:
            return !baseURL.isEmpty
        case .openaiCompatible:
            // OpenAI-compatible requires both base URL and API key
            return hasAPIKey && !baseURL.isEmpty
        default:
            return hasAPIKey
        }
    }
    
    /// Get configuration error message for current provider
    var providerConfigurationError: String? {
        switch provider {
        case .ollama:
            if baseURL.isEmpty { return "Ollama Base URL not configured" }
        case .openaiCompatible:
            if baseURL.isEmpty { return "Base URL not configured" }
            if apiKey.isEmpty { return "API Key not configured" }
        default:
            if provider.requiresAPIKey && apiKey.isEmpty {
                return "\(provider.displayName) API Key not configured"
            }
        }
        return nil
    }
    
    /// Get the model string in format "provider/model" for OpenCode CLI
    func getModelString() -> String? {
        let modelValue = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerPrefix = provider.openCodeProviderName
        let defaultModel = provider.defaultModel
        
        // If model name is provided, use it
        if !modelValue.isEmpty {
            // If model already has provider prefix, use as-is
            if modelValue.contains("/") {
                return modelValue
            }
            // Otherwise add provider prefix
            return "\(providerPrefix)/\(modelValue)"
        }
        
        // Use default model for provider
        return "\(providerPrefix)/\(defaultModel)"
    }
}
