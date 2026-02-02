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
        get {
            switch provider {
            // Primary providers
            case .claude: return claudeBaseURL
            case .openai: return openaiBaseURL
            case .gemini: return geminiBaseURL
            case .ollama: return ollamaBaseURL
            // Cloud providers
            case .openrouter: return openrouterBaseURL
            case .mistral: return mistralBaseURL
            case .groq: return groqBaseURL
            case .xai: return xaiBaseURL
            case .cohere: return cohereBaseURL
            case .deepinfra: return deepinfraBaseURL
            case .togetherai: return togetheraiBaseURL
            case .perplexity: return perplexityBaseURL
            case .cerebras: return cerebrasBaseURL
            // Enterprise / Cloud
            case .azure: return azureBaseURL
            case .bedrock: return bedrockBaseURL
            case .googleVertex: return googleVertexBaseURL
            // OpenAI-compatible
            case .openaiCompatible: return openaiCompatibleBaseURL
            }
        }
        set {
            switch provider {
            // Primary providers
            case .claude: claudeBaseURL = newValue
            case .openai: openaiBaseURL = newValue
            case .gemini: geminiBaseURL = newValue
            case .ollama: ollamaBaseURL = newValue
            // Cloud providers
            case .openrouter: openrouterBaseURL = newValue
            case .mistral: mistralBaseURL = newValue
            case .groq: groqBaseURL = newValue
            case .xai: xaiBaseURL = newValue
            case .cohere: cohereBaseURL = newValue
            case .deepinfra: deepinfraBaseURL = newValue
            case .togetherai: togetheraiBaseURL = newValue
            case .perplexity: perplexityBaseURL = newValue
            case .cerebras: cerebrasBaseURL = newValue
            // Enterprise / Cloud
            case .azure: azureBaseURL = newValue
            case .bedrock: bedrockBaseURL = newValue
            case .googleVertex: googleVertexBaseURL = newValue
            // OpenAI-compatible
            case .openaiCompatible: openaiCompatibleBaseURL = newValue
            }
        }
    }
    
    /// Model name for current provider
    var modelName: String {
        get {
            switch provider {
            // Primary providers
            case .claude: return claudeModelName
            case .openai: return openaiModelName
            case .gemini: return geminiModelName
            case .ollama: return ollamaModelName
            // Cloud providers
            case .openrouter: return openrouterModelName
            case .mistral: return mistralModelName
            case .groq: return groqModelName
            case .xai: return xaiModelName
            case .cohere: return cohereModelName
            case .deepinfra: return deepinfraModelName
            case .togetherai: return togetheraiModelName
            case .perplexity: return perplexityModelName
            case .cerebras: return cerebrasModelName
            // Enterprise / Cloud
            case .azure: return azureModelName
            case .bedrock: return bedrockModelName
            case .googleVertex: return googleVertexModelName
            // OpenAI-compatible
            case .openaiCompatible: return openaiCompatibleModelName
            }
        }
        set {
            switch provider {
            // Primary providers
            case .claude: claudeModelName = newValue
            case .openai: openaiModelName = newValue
            case .gemini: geminiModelName = newValue
            case .ollama: ollamaModelName = newValue
            // Cloud providers
            case .openrouter: openrouterModelName = newValue
            case .mistral: mistralModelName = newValue
            case .groq: groqModelName = newValue
            case .xai: xaiModelName = newValue
            case .cohere: cohereModelName = newValue
            case .deepinfra: deepinfraModelName = newValue
            case .togetherai: togetheraiModelName = newValue
            case .perplexity: perplexityModelName = newValue
            case .cerebras: cerebrasModelName = newValue
            // Enterprise / Cloud
            case .azure: azureModelName = newValue
            case .bedrock: bedrockModelName = newValue
            case .googleVertex: googleVertexModelName = newValue
            // OpenAI-compatible
            case .openaiCompatible: openaiCompatibleModelName = newValue
            }
        }
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
