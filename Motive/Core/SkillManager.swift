//
//  SkillManager.swift
//  Motive
//
//  Skill system architecture for extensible AI capabilities.
//

import Foundation

/// Represents a loaded skill with its metadata and content
struct Skill: Identifiable {
    let id: String
    let name: String
    let description: String
    let content: String
    let type: SkillType
    
    enum SkillType: String {
        case mcpTool = "mcp"        // Provides MCP tool functionality
        case instruction = "instruction"  // Provides behavioral instructions
        case rule = "rule"          // Enforces rules/constraints
    }
}

/// Manages loading and organizing skills from the skills directory
@MainActor
final class SkillManager {
    static let shared = SkillManager()
    
    private(set) var skills: [Skill] = []
    
    private init() {
        loadBuiltInSkills()
    }
    
    /// Load all built-in skills
    private func loadBuiltInSkills() {
        skills = [
            createAskUserQuestionSkill(),
            createFilePermissionSkill(),
            createSafeFileDeletionSkill()
        ]
        Log.debug("Loaded \(skills.count) built-in skills")
    }
    
    /// Get all skills of a specific type
    func skills(ofType type: Skill.SkillType) -> [Skill] {
        skills.filter { $0.type == type }
    }
    
    /// Generate combined system prompt from all skills
    func generateSystemPrompt() -> String {
        var sections: [String] = []
        
        // Identity
        sections.append("""
        <identity>
        You are Motive, a personal AI assistant that executes tasks autonomously in the background.
        You help users accomplish tasks while minimizing interruptions - only asking for input when truly necessary.
        </identity>
        """)
        
        // Environment
        sections.append("""
        <environment>
        - Running in a native macOS GUI application (not a terminal)
        - User CANNOT see your text output or CLI prompts
        - All user communication MUST go through MCP tools
        - File operations require explicit permission via MCP tools
        </environment>
        """)
        
        // MCP Tool skills
        let mcpSkills = skills(ofType: .mcpTool)
        if !mcpSkills.isEmpty {
            for skill in mcpSkills {
                sections.append("""
                <tool name="\(skill.name)">
                \(skill.content)
                </tool>
                """)
            }
        }
        
        // Instruction skills
        let instructionSkills = skills(ofType: .instruction)
        for skill in instructionSkills {
            sections.append("""
            <skill name="\(skill.name)">
            \(skill.content)
            </skill>
            """)
        }
        
        // Rule skills (wrapped in <important>)
        let ruleSkills = skills(ofType: .rule)
        if !ruleSkills.isEmpty {
            var ruleContent: [String] = []
            for skill in ruleSkills {
                ruleContent.append(skill.content)
            }
            sections.append("""
            <important name="mandatory-rules">
            \(ruleContent.joined(separator: "\n\n"))
            </important>
            """)
        }
        
        return sections.joined(separator: "\n\n")
    }
    
    // MARK: - Built-in Skills
    
    private func createAskUserQuestionSkill() -> Skill {
        Skill(
            id: "ask-user-question",
            name: "AskUserQuestion",
            description: "Present choices to users when you need them to make a decision.",
            content: """
            Shows a modal dialog for users to select from options.
            
            ## ⛔ MANDATORY: "options" ARRAY IS REQUIRED
            
            Every call MUST include an "options" array with 2-4 choices.
            Calls WITHOUT options will FAIL and break the UI.
            
            ## ⚠️ DO NOT USE FOR CONVERSATION
            
            If user is chatting → Just respond with text (visible in Drawer)
            If user needs to CHOOSE → Use this tool WITH options
            
            ## Required Format
            
            ```json
            {
              "questions": [{
                "question": "Your question",
                "options": [
                  { "label": "Choice 1", "description": "What this does" },
                  { "label": "Choice 2", "description": "What this does" },
                  { "label": "Other", "description": "Custom input" }
                ]
              }]
            }
            ```
            
            ## Parameters
            
            - `question` (required): The question text
            - `options` (⛔ REQUIRED): Array of 2-4 choices. NEVER omit this!
            - `header` (optional): Short title (max 12 chars)
            - `multiSelect` (optional): Allow multiple selections
            
            ## When to Use
            
            ✅ User gave a task with multiple valid approaches → Ask with options
            ✅ Destructive action needs confirmation → Ask with Yes/No options
            
            ## When NOT to Use
            
            ❌ Casual conversation → Just reply in text
            ❌ Asking "how can I help" → Don't ask, wait for task
            ❌ Open-ended questions without options → Don't call this tool
            
            ## Response Format
            
            - `User selected: Option Name` - Single selection
            - `User selected: Option A, Option B` - Multiple selections (if multiSelect: true)
            - `User responded: [custom text]` - If user typed a custom response via "Other"
            - `User declined to answer the question.` - If user dismissed the modal
            
            ## Example
            
            ```
            AskUserQuestion({
              "questions": [{
                "question": "How would you like to organize your Downloads folder?",
                "header": "Organize",
                "options": [
                  { "label": "By file type", "description": "Group into Documents, Images, Videos, etc." },
                  { "label": "By date", "description": "Group by month/year" },
                  { "label": "Other", "description": "Tell me your preference" }
                ]
              }]
            })
            ```
            """,
            type: .mcpTool
        )
    }
    
    private func createFilePermissionSkill() -> Skill {
        Skill(
            id: "file-permission",
            name: "request_file_permission",
            description: "Request user permission before performing file operations.",
            content: """
            Use this MCP tool to request user permission before performing ANY file operation.
            
            ## When to Use
            
            BEFORE using Write, Edit, Bash (with file ops), or ANY tool that touches files:
            1. FIRST: Call request_file_permission and wait for response
            2. ONLY IF response is "allowed": Proceed with the file operation
            3. IF "denied": Stop and inform the user via AskUserQuestion
            
            ## Parameters
            
            ```json
            {
              "operation": "create|delete|rename|move|modify|overwrite",
              "filePath": "/path/to/file",
              "filePaths": ["/path/to/file1", "/path/to/file2"]  // For batch operations
            }
            ```
            
            ## Operations
            
            | Operation | Use When |
            |-----------|----------|
            | `create` | Creating a new file that doesn't exist |
            | `delete` | Removing a file or directory |
            | `rename` | Changing a file's name (same directory) |
            | `move` | Moving a file to a different directory |
            | `modify` | Editing content within an existing file |
            | `overwrite` | Replacing entire file content |
            
            ## Examples
            
            Single file:
            ```
            request_file_permission({
              "operation": "create",
              "filePath": "/Users/john/Desktop/report.txt"
            })
            ```
            
            Batch deletion:
            ```
            request_file_permission({
              "operation": "delete",
              "filePaths": ["/tmp/file1.txt", "/tmp/file2.txt", "/tmp/file3.txt"]
            })
            ```
            
            ## Response
            
            Returns: `"allowed"` or `"denied"` - proceed only if allowed
            """,
            type: .mcpTool
        )
    }
    
    private func createSafeFileDeletionSkill() -> Skill {
        Skill(
            id: "safe-file-deletion",
            name: "Safe File Deletion",
            description: "Enforces explicit user permission before any file deletion.",
            content: """
            ## Safe File Deletion Rule
            
            Before deleting ANY file, you MUST:
            
            1. Call `request_file_permission` with `operation: "delete"`
            2. For multiple files, use `filePaths` array (batch into one prompt, not multiple calls)
            3. Wait for response
            4. Only proceed if "allowed"
            5. If "denied", acknowledge and do NOT delete
            
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
            
            ## WRONG vs CORRECT
            
            WRONG (never do this):
            ```bash
            rm /path/to/file.txt
            ```
            
            CORRECT (always do this):
            ```
            request_file_permission({ operation: "delete", filePath: "/path/to/file.txt" })
            → Wait for "allowed"
            rm /path/to/file.txt  ← Only after permission granted
            ```
            """,
            type: .rule
        )
    }
}
