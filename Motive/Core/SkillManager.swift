//
//  SkillManager.swift
//  Motive
//
//  Skill system architecture for extensible AI capabilities.
//
//  Skills are modular units that extend OpenCode's abilities:
//  - MCP Tools: Provide callable MCP server functionality
//  - Capabilities: External tools like browser automation (bundled binaries)
//  - Instructions: Behavioral guidelines
//  - Rules: Mandatory constraints
//

import Foundation

/// Represents a loaded skill with its metadata and content
struct Skill: Identifiable {
    let id: String
    let name: String
    let description: String
    let content: String
    let type: SkillType
    let enabled: Bool
    
    enum SkillType: String {
        case mcpTool = "mcp"              // Provides MCP tool functionality
        case capability = "capability"     // External tool (bundled binary)
        case instruction = "instruction"   // Provides behavioral instructions
        case rule = "rule"                 // Enforces rules/constraints
    }
    
    init(id: String, name: String, description: String, content: String, type: SkillType, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.description = description
        self.content = content
        self.type = type
        self.enabled = enabled
    }
}

/// Manages loading and organizing skills from the skills directory
@MainActor
final class SkillManager {
    static let shared = SkillManager()
    
    private(set) var skills: [Skill] = []
    
    /// Reference to ConfigManager for checking feature toggles
    private var configManager: ConfigManager?
    
    /// Filename for user-editable rules within a skill directory
    static let userRulesFilename = "RULES.md"
    
    /// System skill IDs that must be enabled by default.
    static let systemSkillIds: Set<String> = [
        "safe-file-deletion",
    ]
    
    private init() {
        loadBuiltInSkills()
    }
    
    /// Set config manager reference (called from AppDelegate/ConfigManager)
    func setConfigManager(_ manager: ConfigManager) {
        self.configManager = manager
        // Reload skills to pick up enabled state
        loadBuiltInSkills()
    }
    
    /// Load all built-in skills
    private func loadBuiltInSkills() {
        let browserUseEnabled = configManager?.browserUseEnabled ?? false
        
        skills = [
            createSafeFileDeletionSkill(),
            createBrowserAutomationSkill(enabled: browserUseEnabled)
        ]
        Log.debug("Loaded \(skills.count) built-in skills (browser automation: \(browserUseEnabled ? "enabled" : "disabled"))")
    }
    
    /// Reload skills (useful when settings change)
    func reloadSkills() {
        loadBuiltInSkills()
    }
    
    /// Get all skills of a specific type
    func skills(ofType type: Skill.SkillType) -> [Skill] {
        skills.filter { $0.type == type }
    }
    
    // MARK: - SKILL.md File Generation
    
    /// Deprecated skill IDs that should be removed from disk if present.
    /// These were written by older Motive versions and are no longer used.
    private static let deprecatedSkillIds: [String] = [
        "ask-user-question",
        "file-permission",
    ]

    /// Write SKILL.md files to the skills directory for OpenCode to discover.
    /// OpenCode looks for skills at $OPENCODE_CONFIG_DIR/skills/<name>/SKILL.md
    ///
    /// For capability skills (like browser-automation), the final SKILL.md is composed of:
    ///   1. Hardcoded technical instructions (command syntax, polling loop) — always overwritten
    ///   2. User-editable rules from RULES.md — write-if-missing, never overwritten
    func writeSkillFiles(to baseDirectory: URL) {
        let skillsDir = baseDirectory.appendingPathComponent("skills")

        // Clean up deprecated skill directories from older versions
        removeDeprecatedSkills(in: skillsDir)

        // Write MCP tool skills and capability skills (like browser automation) as SKILL.md files
        let skillsToWrite = skills(ofType: .mcpTool) + skills(ofType: .capability).filter { $0.enabled }
        for skill in skillsToWrite {
            let skillDir = skillsDir.appendingPathComponent(skill.id)
            let skillMdPath = skillDir.appendingPathComponent("SKILL.md")
            
            do {
                try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
                
                // For capability skills, merge hardcoded content with user-editable rules
                let skillMdContent: String
                if skill.type == .capability {
                    // Ensure user RULES.md exists (write-if-missing)
                    ensureUserRulesFile(for: skill, in: skillDir)
                    // Merge: hardcoded technical content + user rules
                    let userRules = loadUserRules(from: skillDir)
                    skillMdContent = generateCapabilitySkillMd(for: skill, userRules: userRules)
                } else {
                    skillMdContent = generateSkillMd(for: skill)
                }
                
                try skillMdContent.write(to: skillMdPath, atomically: true, encoding: .utf8)
                Log.debug("Written SKILL.md for '\(skill.id)' at: \(skillMdPath.path)")
            } catch {
                Log.debug("Failed to write SKILL.md for '\(skill.id)': \(error)")
            }
        }
    }
    
    /// Remove deprecated skill directories that were created by older Motive versions.
    /// OpenCode auto-discovers any SKILL.md files, so stale directories cause phantom tools.
    private func removeDeprecatedSkills(in skillsDir: URL) {
        let fm = FileManager.default
        for skillId in Self.deprecatedSkillIds {
            let skillDir = skillsDir.appendingPathComponent(skillId)
            guard fm.fileExists(atPath: skillDir.path) else { continue }
            do {
                try fm.removeItem(at: skillDir)
                Log.debug("Removed deprecated skill directory: \(skillId)")
            } catch {
                Log.debug("Failed to remove deprecated skill '\(skillId)': \(error)")
            }
        }
    }

    /// Ensure user-editable RULES.md exists for a capability skill (write-if-missing pattern)
    private func ensureUserRulesFile(for skill: Skill, in skillDir: URL) {
        let rulesPath = skillDir.appendingPathComponent(Self.userRulesFilename)
        guard !FileManager.default.fileExists(atPath: rulesPath.path) else { return }
        
        // Write default rules template based on skill ID
        let defaultContent = defaultUserRules(for: skill.id)
        do {
            try defaultContent.write(to: rulesPath, atomically: true, encoding: .utf8)
            Log.debug("Created default RULES.md for '\(skill.id)'")
        } catch {
            Log.debug("Failed to create RULES.md for '\(skill.id)': \(error)")
        }
    }
    
    /// Load user-editable rules from RULES.md
    private func loadUserRules(from skillDir: URL) -> String? {
        let rulesPath = skillDir.appendingPathComponent(Self.userRulesFilename)
        guard let content = try? String(contentsOf: rulesPath, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return content
    }
    
    /// Generate SKILL.md frontmatter header.
    private func skillMdHeader(for skill: Skill) -> String {
        let metadataLine = Self.systemSkillIds.contains(skill.id)
            ? "\nmetadata: { \"defaultEnabled\": true }"
            : ""
        return """
---
name: \(skill.id)
description: \(skill.description)\(metadataLine)
---

# \(skill.name)

\(skill.content)
"""
    }

    /// Generate SKILL.md content following official AgentSkills spec.
    private func generateSkillMd(for skill: Skill) -> String {
        skillMdHeader(for: skill)
    }

    /// Generate SKILL.md for capability skills: hardcoded technical content + user rules section.
    private func generateCapabilitySkillMd(for skill: Skill, userRules: String?) -> String {
        var md = skillMdHeader(for: skill)

        if let userRules, !userRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            md += """
            
            
            ## Custom Rules
            
            The following rules are user-defined (edit RULES.md in ~/.motive/skills/\(skill.id)/ to customize):
            
            \(userRules)
            """
        }

        return md
    }
    
    /// Default user rules template for each capability skill
    private func defaultUserRules(for skillId: String) -> String {
        switch skillId {
        case "browser-automation":
            return Self.defaultBrowserAutomationRules
        default:
            return """
            # Custom Rules
            
            Add your custom rules and preferences for this skill here.
            This file is yours to edit — it will not be overwritten by Motive.
            """
        }
    }
    
    /// Generate combined system prompt from all skills
    func generateSystemPrompt() -> String {
        var sections: [String] = [
            """
            <identity>
            You are Motive, a personal AI assistant that executes tasks autonomously in the background.
            You help users accomplish tasks while minimizing interruptions - only asking for input when truly necessary.
            </identity>
            """,
            """
            <environment>
            - Running in a native macOS GUI application (not a terminal)
            - Your text output is visible to users in the Drawer UI
            - When you need the user to make a CHOICE, call the built-in `question` tool (NOT text with numbered options)
            - Permissions are handled by OpenCode's native permission system
            </environment>
            """,
        ]

        // MCP Tool skills
        sections += skills(ofType: .mcpTool).map {
            "<tool name=\"\($0.name)\">\n\($0.content)\n</tool>"
        }

        // Capability skills (external tools like browser automation)
        sections += skills(ofType: .capability).filter(\.enabled).map {
            "<capability name=\"\($0.name)\">\n\($0.content)\n</capability>"
        }

        // Instruction skills
        sections += skills(ofType: .instruction).map {
            "<skill name=\"\($0.name)\">\n\($0.content)\n</skill>"
        }

        // Rule skills (grouped in a single <important> block)
        let ruleContent = skills(ofType: .rule).map(\.content)
        if !ruleContent.isEmpty {
            sections.append("""
            <important name="mandatory-rules">
            \(ruleContent.joined(separator: "\n\n"))
            </important>
            """)
        }

        return sections.joined(separator: "\n\n")
    }
    
    // MARK: - Built-in Skills
    
    private func createSafeFileDeletionSkill() -> Skill {
        Skill(
            id: "safe-file-deletion",
            name: "Safe File Deletion",
            description: "Enforces explicit user permission before any file deletion.",
            content: """
            ## Safe File Deletion Rule
            
            Before deleting ANY file, you MUST:
            
            1. Use the built-in `question` tool to ask the user for explicit permission
            2. For multiple files, batch into one `question` tool call (not multiple calls)
            3. Wait for the user's response
            4. Only proceed if the user approves
            5. If denied, acknowledge and do NOT delete
            
            ## Applies To
            
            - `rm` commands (single or multiple files)
            - `rm -rf` (directories)
            - `unlink`, `fs.rm`, `fs.rmdir`
            - Any script or tool that deletes files
            - Trash/recycle operations
            
            ## No Workarounds
            
            Never bypass deletion by:
            - Emptying files instead of deleting
            - Moving to hidden/temp locations
            - Using obscure commands
            - Claiming it's "just cleanup"
            """,
            type: .rule
        )
    }
    
    private func createBrowserAutomationSkill(enabled: Bool) -> Skill {
        let headedMode = configManager?.browserUseHeadedMode ?? true
        let headedFlag = headedMode ? "--headed " : ""
        
        return Skill(
            id: "browser-automation",
            name: "Browser Automation",
            description: "Autonomous browser agent for interactive web workflows requiring multi-step navigation, clicking, typing, or user decisions.",
            content: """
            # Browser Automation (browser-use-sidecar)
            
            ## When to Use Which Tool
            
            You have TWO web tools. Choose based on the nature of the task:
            
            **Use the built-in `webfetch` tool when:**
            The task only requires **reading** web content — no clicking, typing, logging in, or navigating between pages. Webfetch is faster, lighter, and sufficient for any read-only web access.
            
            **Use `browser-use-sidecar` when:**
            The task requires **interaction** with a web page — clicking buttons, filling forms, navigating multi-step flows, making selections, logging in, or any workflow where a real browser session is needed.
            
            **Rule of thumb:** If you only need the content of a URL, use `webfetch`. If you need to *do something* on a website, use `browser-use-sidecar`.
            
            ---
            
            ## browser-use-sidecar Usage
            
            ### Command: agent_task
            
            ```bash
            browser-use-sidecar \(headedFlag)agent_task "your task description"
            ```
            
            The agent autonomously opens a browser, navigates, clicks, types, and requests user input when decisions are needed.
            
            ### Response Handling — CRITICAL POLLING LOOP
            
            After calling `agent_task`, you **MUST** poll `agent_status` until the task completes.
            
            **Status types:**
            - `"running"` — Task in progress. Wait 3–5 seconds, then call `agent_status` again.
            - `"need_input"` — Agent needs a user decision. Use the built-in `question` tool, then `agent_continue`.
            - `"completed"` — Task finished successfully.
            - `"error"` — Task failed.
            
            ### Workflow
            
            ```bash
            # 1. Start task
            browser-use-sidecar \(headedFlag)agent_task "your task"
            
            # 2. Poll status (repeat until NOT "running")
            sleep 5
            browser-use-sidecar agent_status
            # "running"  → repeat step 2
            # "need_input" → step 3
            # "completed" / "error" → done
            
            # 3. Handle need_input
            # Use the built-in `question` tool to present options to user
            # After user responds:
            browser-use-sidecar agent_continue "user's choice"
            # → go back to step 2
            
            # 4. When done
            browser-use-sidecar close
            ```
            
            ### Commands Reference
            
            - `agent_task "description"` — Start an autonomous browser task
            - `agent_status` — Check task progress (poll repeatedly while running)
            - `agent_continue "choice"` — Provide user's decision and resume
            - `close` — Close the browser session
            
            ### Progressive Clarification
            
            Minimize questions to the user. Only ask when genuinely necessary.
            
            - **Before browsing:** Ask only for high-level constraints (goal, budget range, preferences).
            - **After real candidates exist:** Present concrete options for the user to choose from via the `question` tool.
            - Never ask the user to choose between options that don't exist yet.
            
            ### Safety (Non-negotiable)
            
            - Never complete a payment, enter passwords, or confirm transactions without explicit user approval.
            - If login expires, CAPTCHA appears, or anything unexpected happens — notify the user immediately.
            """,
            type: .capability,
            enabled: enabled
        )
    }
    
    // MARK: - Default User Rules Templates
    
    /// Default user-editable rules for browser-automation skill.
    /// Written to ~/.motive/skills/browser-automation/RULES.md on first run (write-if-missing).
    /// Users can freely edit this file — it will never be overwritten by Motive.
    static let defaultBrowserAutomationRules = """
    # Browser Automation - Custom Rules
    
    # This file contains your personal rules and preferences for browser automation.
    # Edit freely — Motive will never overwrite this file.
    # These rules are merged into the browser automation skill prompt automatically.
    
    ## Shopping Workflow
    
    When handling purchase or shopping tasks:
    
    ### 1. Clarify Intent
    - If the request is ambiguous, ask once for: category, budget range, brand preference.
    - If intent is already specific (e.g. "buy AirPods Pro"), skip straight to search.
    
    ### 2. Search
    - Launch browser agent to search. Let it browse autonomously — don't interrupt the user.
    
    ### 3. Confirm Selection
    - When candidates are found, present full details for user confirmation:
      brand, price, specs/SKU options, ratings if available.
    - Never choose a product on the user's behalf, even if preferences are known.
    
    ### 4. Add to Cart
    - After user confirms, add to cart. This is the default action.
    - Never proceed to checkout or payment automatically.
    
    ### 5. Notify
    - Once all items are in cart, summarize: item names, quantities, prices.
    - Offer options: "Checkout now" / "Continue shopping" / "Done for now".
    - Only navigate to checkout if user explicitly chooses to.
    """
}
