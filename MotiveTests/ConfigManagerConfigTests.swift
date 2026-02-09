import Testing
import Foundation
@testable import Motive

/// Tests that the generated OpenCode configuration is clean of legacy
/// MCP and question-deny references, and contains correct permission rules.
@Suite("OpenCode Config Generation")
struct ConfigManagerConfigTests {

    // MARK: - Provider Name Mapping

    @Test func providerNameMappings() {
        #expect(ConfigManager.Provider.claude.openCodeProviderName == "anthropic")
        #expect(ConfigManager.Provider.openai.openCodeProviderName == "openai")
        #expect(ConfigManager.Provider.gemini.openCodeProviderName == "google")
        #expect(ConfigManager.Provider.ollama.openCodeProviderName == "ollama")
        #expect(ConfigManager.Provider.openrouter.openCodeProviderName == "openrouter")
        #expect(ConfigManager.Provider.azure.openCodeProviderName == "azure")
        #expect(ConfigManager.Provider.bedrock.openCodeProviderName == "amazon-bedrock")
        #expect(ConfigManager.Provider.googleVertex.openCodeProviderName == "google-vertex")
    }

    @Test func providerRequiresAPIKey() {
        #expect(ConfigManager.Provider.claude.requiresAPIKey == true)
        #expect(ConfigManager.Provider.openai.requiresAPIKey == true)
        #expect(ConfigManager.Provider.ollama.requiresAPIKey == false)
    }

    // MARK: - ToolPermissionPolicy Output for Config

    @Test @MainActor func permissionRulesContainAllTools() {
        let policy = ToolPermissionPolicy.shared
        let rules = policy.toOpenCodePermissionRules()

        // All tool categories should be present
        for tool in ToolPermission.allCases {
            #expect(rules[tool.rawValue] != nil,
                    "Missing permission rule for \(tool.rawValue)")
        }
    }

    @Test @MainActor func permissionRulesDoNotContainQuestionDeny() {
        let policy = ToolPermissionPolicy.shared
        let rules = policy.toOpenCodePermissionRules()

        // There should be no "question: deny" entry
        #expect(rules["question"] == nil,
                "Permission rules should not contain 'question' key (native, not MCP)")
    }

    @Test @MainActor func permissionRulesDoNotContainMCPEntries() {
        let policy = ToolPermissionPolicy.shared
        let rules = policy.toOpenCodePermissionRules()

        // No legacy MCP tool references
        #expect(rules["ask-user-question"] == nil)
        #expect(rules["file-permission"] == nil)
        #expect(rules["AskUserQuestion"] == nil)
        #expect(rules["request_file_permission"] == nil)
    }

    @Test @MainActor func permissionRulesFormatIsCorrect() {
        let policy = ToolPermissionPolicy.shared
        let rules = policy.toOpenCodePermissionRules()

        // Each value should be either a String (simple) or [String: String] (pattern-based)
        for (key, value) in rules {
            if let stringValue = value as? String {
                let validActions = ["allow", "ask", "deny"]
                #expect(validActions.contains(stringValue),
                        "Invalid action '\(stringValue)' for tool '\(key)'")
            } else if let dictValue = value as? [String: String] {
                // Pattern-based format must have a wildcard default
                #expect(dictValue["*"] != nil,
                        "Pattern-based rules for '\(key)' must have a '*' default")
            } else {
                Issue.record("Unexpected type for permission rule '\(key)': \(type(of: value))")
            }
        }
    }

    // MARK: - Protected Path Rules

    @Test @MainActor func editProtectedPathsAreEnforced() {
        let policy = ToolPermissionPolicy.shared
        let rules = policy.toOpenCodePermissionRules()

        // Edit rules should include system protection
        if let editRules = rules["edit"] as? [String: String] {
            #expect(editRules["/System/**"] == "deny",
                    "Edit rules should deny /System/**")
            #expect(editRules["/usr/**"] == "deny",
                    "Edit rules should deny /usr/**")
            #expect(editRules["~/.ssh/**"] == "deny",
                    "Edit rules should deny ~/.ssh/**")
        }
        // If edit has no user rules, it might be a simple string, and protected
        // rules would upgrade it to a dict. Check that protection exists.
    }

    @Test @MainActor func bashProtectedPathsAreEnforced() {
        let policy = ToolPermissionPolicy.shared
        let rules = policy.toOpenCodePermissionRules()

        // Bash rules should include destructive command protection
        if let bashRules = rules["bash"] as? [String: String] {
            #expect(bashRules["rm -rf /"] == "deny",
                    "Bash rules should deny 'rm -rf /'")
            #expect(bashRules["rm -rf /*"] == "deny",
                    "Bash rules should deny 'rm -rf /*'")
        }
    }

    // MARK: - Serialization to JSON

    @Test @MainActor func permissionRulesSerializeToValidJSON() throws {
        let policy = ToolPermissionPolicy.shared
        let rules = policy.toOpenCodePermissionRules()

        // Should be serializable to JSON
        let data = try JSONSerialization.data(withJSONObject: rules, options: .prettyPrinted)
        let jsonString = String(data: data, encoding: .utf8)
        #expect(jsonString != nil, "Permission rules should be serializable to JSON")

        // JSON should not contain legacy references
        if let json = jsonString {
            #expect(!json.contains("AskUserQuestion"))
            #expect(!json.contains("request_file_permission"))
            #expect(!json.contains("file-permission"))
            #expect(!json.contains("ask-user-question"))
        }
    }
}
