# Skill System Architecture

Motive's Skill System provides extensible AI capabilities through modular, composable units called **Skills**.

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        SystemPromptBuilder                        │
│  Combines all components into a coherent system prompt           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────┬──────────────────┬──────────────────┐
│   SkillManager   │ FileOperationPolicy │  Context Info   │
│  (Built-in Skills) │  (Permission Rules) │  (CWD, etc.)   │
└──────────────────┴──────────────────┴──────────────────┘
```

## 1. Skill Types

### MCP Tools (`mcpTool`)
Provide MCP server functionality that AI can invoke.

| Skill | Purpose |
|-------|---------|
| `AskUserQuestion` | UI-based user communication |
| `request_file_permission` | File operation authorization |

### Instructions (`instruction`)
Behavioral guidelines for the AI.

### Rules (`rule`)
Mandatory constraints that the AI must follow.

| Skill | Purpose |
|-------|---------|
| `Safe File Deletion` | Requires explicit permission before any deletion |

## 2. File Operation Policy

Fine-grained control over file operations with configurable policies.

### Operations

| Operation | Risk Level | Default Policy |
|-----------|------------|----------------|
| `create` | Low | Ask |
| `modify` | Low | Ask |
| `rename` | Medium | Ask |
| `move` | Medium | Ask |
| `overwrite` | High | Ask |
| `execute` | High | Ask |
| `delete` | Critical | Ask |

### Policies

| Policy | Behavior |
|--------|----------|
| `alwaysAllow` | Auto-approve without asking |
| `alwaysAsk` | Always prompt user |
| `askOnce` | Ask once per session, remember |
| `alwaysDeny` | Auto-deny without asking |

### Path Rules

Rules can be defined for specific paths or glob patterns:

```swift
PathRule(
    pattern: "/System/**",
    operations: Set(FileOperation.allCases),
    policy: .alwaysDeny,
    description: "System files are protected"
)
```

## 3. System Prompt Structure

The `SystemPromptBuilder` generates structured XML prompts:

```xml
<identity>
  Core persona and philosophy
</identity>

<environment>
  Runtime constraints and context
</environment>

<communication>
  How to interact with users (via MCP only)
</communication>

<file-operations>
  Permission system and rules
</file-operations>

<mcp-tools>
  Available MCP tool documentation
</mcp-tools>

<behavior>
  Task execution guidelines
</behavior>

<examples>
  Concrete usage examples
</examples>
```

## 4. Integration Flow

```
User Input
    │
    ▼
┌─────────────────┐
│  CommandBar     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────────┐
│ OpenCodeBridge  │────▶│ SystemPromptBuilder │
└────────┬────────┘     └─────────────────────┘
         │                        │
         │                        ▼
         │              ┌─────────────────┐
         │              │  SkillManager   │
         │              └─────────────────┘
         │
         ▼
┌─────────────────┐
│   OpenCode CLI  │
└────────┬────────┘
         │
         ▼ (MCP request)
┌─────────────────┐     ┌─────────────────────┐
│PermissionManager│────▶│ FileOperationPolicy │
└────────┬────────┘     └─────────────────────┘
         │
         ▼
┌─────────────────┐
│  User Decision  │
│  (Drawer/Panel) │
└─────────────────┘
```

## 5. Adding Custom Skills

Skills can be extended by modifying `SkillManager.swift`:

```swift
private func createMyCustomSkill() -> Skill {
    Skill(
        id: "my-custom-skill",
        name: "MySkill",
        description: "Description for management UI",
        content: """
        Full documentation shown to AI...
        """,
        type: .mcpTool  // or .instruction, .rule
    )
}
```

Then add to `loadBuiltInSkills()`:

```swift
skills = [
    createAskUserQuestionSkill(),
    createFilePermissionSkill(),
    createSafeFileDeletionSkill(),
    createMyCustomSkill()  // Add here
]
```

## 6. Future Extensions

- [ ] External skill loading from `~/.motive/skills/` directory
- [ ] YAML-based skill definition files
- [ ] User-configurable path rules in Settings
- [ ] Per-project skill overrides
- [ ] Skill enable/disable toggles in UI
