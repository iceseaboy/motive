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
        let inputs = OpenCodeConfigGenerator.Inputs(
            providerName: provider.openCodeProviderName,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            workspaceDirectory: workspaceDirectory,
            skillsSystemEnabled: skillsSystemEnabled
        )
        let result = OpenCodeConfigGenerator.generate(
            inputs: inputs,
            permissionPolicy: ToolPermissionPolicy.shared,
            skillRegistry: SkillRegistry.shared,
            skillManager: SkillManager.shared,
            promptBuilder: SystemPromptBuilder()
        )
        openCodeConfigPath = result.configPath
        openCodeConfigDir = result.configDir
    }
}
