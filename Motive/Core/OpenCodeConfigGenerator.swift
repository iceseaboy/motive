//
//  OpenCodeConfigGenerator.swift
//  Motive
//

import Foundation

/// Generates the opencode.json configuration file with explicit dependency injection.
@MainActor
struct OpenCodeConfigGenerator {

    struct Inputs {
        let providerName: String
        let baseURL: String
        let workspaceDirectory: URL
        let skillsSystemEnabled: Bool
    }

    /// Generate opencode.json configuration and write skill files.
    /// Returns the (configPath, configDir) tuple.
    @discardableResult
    static func generate(
        inputs: Inputs,
        permissionPolicy: ToolPermissionPolicy,
        skillRegistry: SkillRegistry,
        skillManager: SkillManager,
        promptBuilder: SystemPromptBuilder
    ) -> (configPath: String, configDir: String) {
        // Config now goes to workspace directory (~/.motive/config/)
        let configDir = inputs.workspaceDirectory.appendingPathComponent("config")
        let configPath = configDir.appendingPathComponent("opencode.json")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Determine provider name for OpenCode
        let providerName = inputs.providerName
        let baseURLValue = inputs.baseURL

        // System prompt - build using SystemPromptBuilder
        let systemPrompt = promptBuilder.build()

        // Build skill permissions using WHITELIST approach:
        // deny all, then explicitly allow enabled skills.
        // Skills are synced to $OPENCODE_CONFIG_DIR/skills/<name>/SKILL.md so
        // OpenCode's native `skill` tool discovers them; permissions gate access.
        var skillPermissions: [String: String] = ["*": "deny"]
        for entry in skillRegistry.entries where skillRegistry.isSkillEnabled(entry) {
            skillPermissions[entry.name] = "allow"
            Log.config(" Skill '\(entry.name)' is enabled -> allow")
        }

        var permissionRules = permissionPolicy.toOpenCodePermissionRules()
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
        if inputs.skillsSystemEnabled {
            let skillMcp = skillRegistry.buildMcpConfigEntries()
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

            // Write capability/MCP SKILL.md files (browser-automation etc.)
            skillManager.writeSkillFiles(to: inputs.workspaceDirectory)

            // Sync all enabled bundled/user skills so OpenCode's native `skill` tool discovers them.
            // This is the SINGLE mechanism for skill discovery — no system prompt listing needed.
            let skillsDir = inputs.workspaceDirectory.appendingPathComponent("skills")
            skillRegistry.syncSkillsToDirectory(skillsDir)
        } catch {
            Log.config(" ERROR - Failed to write OpenCode config: \(error)")
        }

        return (configPath: configPath.path, configDir: inputs.workspaceDirectory.path)
    }
}
