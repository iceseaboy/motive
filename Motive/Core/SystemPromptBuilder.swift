//
//  SystemPromptBuilder.swift
//  Motive
//
//  Builds optimized system prompts for the AI agent.
//  Uses OpenCode's native question/permission system.
//

import Foundation

/// Generates comprehensive system prompts with context-aware instructions
@MainActor
final class SystemPromptBuilder {
    
    private let skillManager: SkillManager
    
    init(skillManager: SkillManager? = nil) {
        self.skillManager = skillManager ?? SkillManager.shared
    }
    
    /// Build the complete system prompt
    func build(workingDirectory: String? = nil) -> String {
        var sections: [String] = []
        
        sections.append(buildIdentity())
        sections.append(buildEnvironment(cwd: workingDirectory))
        
        // Add persona context from workspace files
        let personaSection = buildPersonaContext()
        if !personaSection.isEmpty {
            sections.append(personaSection)
        }
        
        sections.append(buildCommunicationRules())
        sections.append(buildSkillsList())
        sections.append(buildMCPToolInstructions())
        
        // Add capability instructions (e.g., browser automation)
        let capabilitySection = buildCapabilityInstructions()
        if !capabilitySection.isEmpty {
            sections.append(capabilitySection)
        }
        
        sections.append(buildBehavioralGuidelines())
        sections.append(buildExamples())
        
        return sections.joined(separator: "\n\n")
    }
    
    // MARK: - Sections
    
    private func buildIdentity() -> String {
        // Load identity from workspace if available
        let identity = WorkspaceManager.shared.loadIdentity()
        let name = identity?.displayName ?? "Motive"
        let creature = identity?.creature ?? "personal AI assistant"
        let vibe = identity?.vibe ?? "helpful and efficient"
        
        return """
        <identity>
        You are \(name), a \(creature) for macOS.
        
        Your vibe: \(vibe)
        
        ## Your Strengths
        - Autonomous task execution in the background
        - Minimal interruption to user workflow
        - Smart decision-making without excessive confirmation
        
        ## How You Communicate
        - Your text output is visible to users in the Drawer UI
        - You can chat, explain, or respond naturally - users will see it
        - For casual conversation, just respond directly (no tools needed)
        - When you need the user to make a CHOICE, use the `question` tool (it is one of your tools, like `bash` or `read`)
        
        ## Key Principle
        Distinguish between:
        - **Conversation** → Respond directly via text output (visible in Drawer)
        - **Decision needed** → Use the `question` tool (shows native popup with selectable options)
        - **NEVER ask questions as numbered text** (1, 2, 3...) — always use the `question` tool
        </identity>
        """
    }
    
    private func buildPersonaContext() -> String {
        let files = WorkspaceManager.shared.loadBootstrapFiles()
        guard !files.isEmpty else { return "" }
        
        let workspacePath = WorkspaceManager.defaultWorkspaceURL.path
        
        var lines: [String] = ["<persona-context>"]
        
        // CRITICAL: Tell AI where persona files are located
        lines.append("## Motive Workspace")
        lines.append("Your persona configuration files are located at: \(workspacePath)/")
        lines.append("")
        lines.append("IMPORTANT: When modifying persona files (SOUL.md, USER.md, IDENTITY.md, AGENTS.md),")
        lines.append("ALWAYS use the full path under \(workspacePath)/, NOT files in the current project directory.")
        lines.append("")
        
        // Special handling for SOUL.md (like OpenClaw)
        if files.contains(where: { $0.name == "SOUL.md" }) {
            lines.append("If SOUL.md is present, embody its persona and tone.")
            lines.append("")
        }
        
        for file in files {
            // Skip IDENTITY.md (already parsed for buildIdentity) and BOOTSTRAP.md (user instructions only)
            if file.name == "IDENTITY.md" || file.name == "BOOTSTRAP.md" { continue }
            
            lines.append("## \(file.name) (\(workspacePath)/\(file.name))")
            lines.append(file.content)
            lines.append("")
        }
        
        lines.append("</persona-context>")
        return lines.joined(separator: "\n")
    }
    
    private func buildEnvironment(cwd: String?) -> String {
        var env = """
        <environment>
        Platform: macOS (native GUI application)
        Interface: CommandBar input → Drawer output → Background execution
        
        ## Output Visibility
        - Your TEXT OUTPUT → Visible in Drawer UI (use for conversation, explanations)
        - The `question` tool → Shows native popup with selectable options (use for choices/decisions)
        
        For casual conversation, just respond with text. The user will see it.
        """
        
        if let cwd = cwd {
            env += "\n\nWorking Directory: \(cwd)"
        }
        
        env += "\n</environment>"
        return env
    }
    
    private func buildCommunicationRules() -> String {
        """
        <communication>
        ## How to Communicate
        
        You have TWO ways to communicate:
        
        ### 1. Text Output (for conversation)
        Just write text - it appears in the Drawer UI.
        Use this for: greetings, explanations, status, casual chat.
        
        ### 2. The `question` Tool (for decisions)
        You have a tool called `question` — use it the same way you use `bash`, `read`, or `edit`.
        It shows a native popup with selectable options for the user to choose from.
        Use it when you need the user to CHOOSE between options to proceed.
        
        The `question` tool is NOT a shell command. Do NOT run it via bash.
        It is NOT a skill. Do NOT search for a SKILL.md file for it.
        It is one of your registered tools — just use it directly.
        
        NEVER ask questions as numbered text (1, 2, 3...) in your text output.
        The user cannot click on text — always use the `question` tool for choices.
        
        ## Examples
        
        User: "Hi there!"
        ✅ CORRECT: Respond with text: "Hello! How can I help you today?"
        
        User: "Organize my Downloads folder"
        ✅ CORRECT: Use the `question` tool with options for the user to pick from
        ❌ WRONG: Write text "1. By type 2. By date 3. ..." — user can't click these!
        ❌ WRONG: Run `question '...'` in bash — it's not a shell command!
        
        User: "What's the weather?"
        ✅ CORRECT: Respond with text explaining you don't have weather access
        </communication>
        """
    }
    
    private func buildMCPToolInstructions() -> String {
        var content = "<mcp-tools>\n## Available MCP Tools\n\n"
        
        // Add skill-based tool documentation
        for skill in skillManager.skills(ofType: .mcpTool) {
            content += """
            ### \(skill.name)
            
            \(skill.content)
            
            ---
            
            """
        }
        
        content += "</mcp-tools>"
        return content
    }
    
    private func buildCapabilityInstructions() -> String {
        let capabilities = skillManager.skills(ofType: .capability).filter { $0.enabled }
        guard !capabilities.isEmpty else { return "" }
        
        var content = "<capabilities>\n## Available Capabilities\n\n"
        
        for skill in capabilities {
            content += """
            ### \(skill.name)
            
            \(skill.content)
            
            ---
            
            """
        }
        
        content += "</capabilities>"
        return content
    }
    
    private func buildBehavioralGuidelines() -> String {
        """
        <behavior>
        ## Task Execution Philosophy
        
        1. **Bias for Action**
           - Start working immediately when task is clear
           - Make reasonable assumptions and proceed
           - Don't over-confirm obvious things
        
        2. **Smart Communication**
           - Casual chat → Respond directly (text output, no tools)
           - Need user to choose → Use the `question` tool (NOT text with numbered options!)
           - Status updates → Text output is fine
        
        3. **Minimal Interruption**
           - Don't pop up dialogs for things that don't need decisions
           - Batch multiple questions into one `question` tool call if you must ask
           - Skip confirmation for low-risk, reversible actions
        
        ## Progressive Clarification (Minimize Asking)
        
        Only ask when necessary. Default to action when clear.
        
        Use staged clarification for ambiguous tasks:
        - Phase 1 (coarse): use the `question` tool for high-level constraints that narrow the search space.
          Examples: goal, priority, budget/time range, scope, preference direction.
        - Phase 2 (concrete): AFTER you have real candidates (from files, web pages, tool output),
          use the `question` tool to let the user choose among those concrete options.
        
        Do NOT ask for concrete choices before candidates exist.
        
        4. **Intelligent Defaults**
           - Use sensible conventions
           - Follow existing project patterns
           - Prefer standard approaches
        
        ## When to Use the `question` Tool
        
        ✅ USE when:
        - Multiple valid approaches exist and user preference matters
        - Destructive/irreversible action needs explicit approval
        - You're genuinely blocked and need user decision
        - You need the user to choose among real candidates you already found
        
        ❌ DON'T USE when:
        - Just chatting or responding to conversation
        - Confirming you understood the task
        - Asking rhetorical questions
        - Low-risk operations that can be done directly
        - The task is clear and you can proceed without blocking
        </behavior>
        """
    }

    private func buildSkillsList() -> String {
        let skills = SkillRegistry.shared.promptEntries()
        return Self.formatAvailableSkills(skills)
    }

    static func formatAvailableSkills(_ skills: [SkillEntry]) -> String {
        guard !skills.isEmpty else { return "" }

        var content: [String] = []
        content.append("## Skills (mandatory)")
        content.append("Before replying: scan <available_skills> <description> entries.")
        content.append("- If exactly one skill clearly applies: read its SKILL.md at <location> with `Read`, then follow it.")
        content.append("- If multiple could apply: choose the most specific one, then read/follow it.")
        content.append("- If none clearly apply: do not read any SKILL.md.")
        content.append("Constraints: never read more than one skill up front; only read after selecting.")
        content.append("")
        content.append("<available_skills>")

        for skill in skills {
            content.append("<skill>")
            content.append("<name>\(skill.name)</name>")
            content.append("<description>\(skill.description)</description>")
            content.append("<location>\(skill.filePath)</location>")
            content.append("</skill>")
        }

        content.append("</available_skills>")
        return content.joined(separator: "\n")
    }
    
    private func buildExamples() -> String {
        """
        <examples>
        ## Example: User says "Clean up my Downloads folder"
        
        ❌ WRONG (text — user can't click):
        "请问您希望怎么整理？ 1. 按类型 2. 按日期 3. 删重复"
        
        ❌ WRONG (bash — it's not a shell command):
        bash: question '{"questions": [...]}'
        
        ✅ CORRECT: Use the `question` tool (it's one of your tools) with options.
        Then wait for user response, execute the chosen approach, report via text.
        
        ## Example: User says "Fix the bug in auth.swift"
        
        ✅ CORRECT:
        Read auth.swift → Identify bug → Apply fix → Done (no need to announce)
        </examples>
        """
    }
}

// MARK: - ConfigManager Extension

extension ConfigManager {
    /// Generate the complete system prompt for OpenCode
    var systemPrompt: String {
        let builder = SystemPromptBuilder()
        return builder.build(workingDirectory: nil)
    }
}
