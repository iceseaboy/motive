import Foundation

@MainActor
extension ConfigManager {
    /// Sync ALL provider API keys to OpenCode's auth.json
    /// Path: ~/.local/share/opencode/auth.json
    func syncToOpenCodeAuth() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let authDir = homeDir.appendingPathComponent(".local/share/opencode")
        let authPath = authDir.appendingPathComponent("auth.json")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: authDir, withIntermediateDirectories: true)
        
        // Read existing auth.json or create new
        var auth: [String: [String: String]] = [:]
        if let data = try? Data(contentsOf: authPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] {
            auth = existing
        }
        
        // Only sync current provider's API key (to avoid multiple keychain prompts)
        let providerName = provider.openCodeProviderName
        
        // Use the cached apiKey property instead of direct keychain read
        let apiKeyValue = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKeyValue.isEmpty && provider.requiresAPIKey {
            auth[providerName] = [
                "type": "api",
                "key": apiKeyValue
            ]
            Log.config(" Synced \(providerName) API key to auth.json")
        }
        
        // Write back
        if let jsonData = try? JSONSerialization.data(withJSONObject: auth, options: .prettyPrinted) {
            try? jsonData.write(to: authPath)
            Log.config(" Synced auth.json to \(authPath.path)")
        }
    }
    
    /// Generate opencode.json config file
    /// Path: ~/.motive/config/opencode.json
    ///
    /// Uses ToolPermissionPolicy for permission rules and OpenCode's
    /// native question/permission system (no MCP sidecar needed).
    func generateOpenCodeConfig() {
        // Config now goes to workspace directory (~/.motive/config/)
        let configDir = workspaceDirectory.appendingPathComponent("config")
        let configPath = configDir.appendingPathComponent("opencode.json")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Determine provider name for OpenCode
        let providerName = provider.openCodeProviderName
        let baseURLValue = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // System prompt - build using SystemPromptBuilder
        let builder = SystemPromptBuilder()
        let systemPrompt = builder.build()
        
        // Build skill permissions using WHITELIST approach
        // Default: deny all, then explicitly allow enabled skills
        var skillPermissions: [String: String] = ["*": "deny"]
        
        // Get enabled skills and add them to allow list
        let skillsConfig = self.skillsConfig
        for entry in SkillRegistry.shared.entries {
            let skillKey = entry.metadata?.skillKey ?? entry.name
            let entryConfig = skillsConfig.entries[skillKey] ?? skillsConfig.entries[entry.name]
            
            // Check if skill is enabled using priority:
            // 1. User explicit config > 2. metadata.defaultEnabled (defaults to false)
            let isEnabled: Bool
            if let explicitEnabled = entryConfig?.enabled {
                isEnabled = explicitEnabled
            } else {
                // Use metadata.defaultEnabled, defaulting to false if not specified
                isEnabled = entry.metadata?.defaultEnabled ?? false
            }
            
            if isEnabled {
                skillPermissions[entry.name] = "allow"
                Log.config(" Skill '\(entry.name)' is enabled -> allow")
            }
        }
        
        // Build permission rules from ToolPermissionPolicy (native system)
        var permissionRules = ToolPermissionPolicy.shared.toOpenCodePermissionRules()
        // Add skill permissions
        permissionRules["skill"] = skillPermissions
        
        var config: [String: Any] = [
            "$schema": "https://opencode.ai/config.json",
            "default_agent": "motive",
            "enabled_providers": [providerName],
            // Permission rules from ToolPermissionPolicy (native enforcement)
            "permission": permissionRules,
            "agent": [
                "motive": [
                    "description": "Motive default agent",
                    "prompt": systemPrompt,
                    "mode": "primary",
                    "permission": permissionRules
                ]
            ]
        ]
        
        // Add provider options (baseURL) if configured
        // Per OpenCode docs: set options.baseURL on the provider directly
        if !baseURLValue.isEmpty {
            config["provider"] = [
                providerName: [
                    "options": [
                        "baseURL": baseURLValue
                    ]
                ]
            ]
            Log.config(" Provider '\(providerName)' configured with baseURL: \(baseURLValue)")
        }

        // Merge MCP tools from skills (if enabled) — only skill-provided MCP tools, not built-in
        if skillsSystemEnabled {
            let skillMcp = SkillRegistry.shared.buildMcpConfigEntries()
            if !skillMcp.isEmpty {
                var existing = config["mcp"] as? [String: Any] ?? [:]
                for (key, value) in skillMcp where existing[key] == nil {
                    existing[key] = value
                }
                config["mcp"] = existing
            }
        }
        
        // Write config
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: configPath)
            Log.config(" Generated OpenCode config at \(configPath.path)")
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                Log.config(" Config content: \(jsonString.prefix(500))")
            }
            
            // Store config path for environment variable
            openCodeConfigPath = configPath.path
            openCodeConfigDir = workspaceDirectory.path
            
            // Write SKILL.md files for OpenCode to discover MCP tools
            // OpenCode looks for skills at $OPENCODE_CONFIG_DIR/skills/<name>/SKILL.md
            SkillManager.shared.writeSkillFiles(to: workspaceDirectory)
        } catch {
            Log.config(" ERROR - Failed to write OpenCode config: \(error)")
        }
    }
}
