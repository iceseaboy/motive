//
//  DrawerComponents.swift
//  Motive
//
//  Aurora Design System - Drawer Components
//

import SwiftUI
import MarkdownUI

// MARK: - Session List Item

struct SessionListItem: View {
    let session: Session
    var isDark: Bool = true
    let onSelect: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AuroraSpacing.space3) {
                // Status indicator with gradient for active
                Circle()
                    .fill(statusGradient)
                    .frame(width: 6, height: 6)
                
                // Content
                VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                    Text(session.intent)
                        .font(.Aurora.bodySmall.weight(.medium))
                        .foregroundColor(Color.Aurora.textPrimary)
                        .lineLimit(1)
                    
                    Text(timeAgo)
                        .font(.Aurora.micro)
                        .foregroundColor(Color.Aurora.textMuted)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.Aurora.textMuted)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, AuroraSpacing.space3)
            .padding(.vertical, AuroraSpacing.space3)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(isHovering ? Color.Aurora.glassOverlay.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.auroraFast) {
                    isHovering = hovering
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private var statusGradient: AnyShapeStyle {
        switch session.status {
        case "running":
            return AnyShapeStyle(Color.Aurora.primary)
        case "completed":
            return AnyShapeStyle(Color.Aurora.success)
        case "failed":
            return AnyShapeStyle(Color.Aurora.error)
        default:
            return AnyShapeStyle(Color.Aurora.textMuted)
        }
    }
    
    private var timeAgo: String {
        let now = Date()
        let diff = now.timeIntervalSince(session.createdAt)
        
        if diff < 60 { return L10n.Time.justNow }
        if diff < 3600 { return String(format: L10n.Time.minutesAgo, Int(diff / 60)) }
        if diff < 86400 { return String(format: L10n.Time.hoursAgo, Int(diff / 3600)) }
        return String(format: L10n.Time.daysAgo, Int(diff / 86400))
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ConversationMessage
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    /// Unified expand/collapse for tool output, diff details, and error details.
    @State private var isDetailExpanded = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        HStack {
            if message.type == .user {
                Spacer(minLength: 60)
            }
            
        VStack(alignment: message.type == .user ? .trailing : .leading, spacing: 0) {
                ZStack(alignment: message.type == .user ? .topTrailing : .topLeading) {
                    // Message content
                    Group {
                        switch message.type {
                        case .user:
                            userBubble
                        case .assistant:
                            assistantBubble
                        case .tool:
                            toolBubble
                        case .system:
                            systemBubble
                        case .todo:
                            todoBubble
                        case .reasoning:
                            EmptyView() // Reasoning is transient, handled by TransientReasoningBubble
                        }
                    }
                    
                    // Timestamp overlay on hover
                    if isHovering {
                        timestampBadge
                    }
                }
            }
            .animation(.auroraFast, value: isHovering)
            
            if message.type != .user {
                Spacer(minLength: 40)
            }
        }
        .onHover { isHovering = $0 }
    }
    
    // MARK: - User Bubble
    
    private var userBubble: some View {
        Text(message.content)
            .font(.Aurora.body)
            .foregroundColor(Color.Aurora.textPrimary)
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space3)
            .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.10 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                    .strokeBorder(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.08), lineWidth: 0.5)
            )
            .textSelection(.enabled)
    }
    
    // MARK: - Assistant Bubble (Dark with amber accent)
    
    /// Get agent identity for display
    private var agentIdentity: AgentIdentity? {
        WorkspaceManager.shared.loadIdentity()
    }
    
    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space2) {
            HStack(spacing: AuroraSpacing.space2) {
                if let identity = agentIdentity, identity.hasValues(), let emoji = identity.emoji {
                    Text(emoji)
                        .font(.system(size: 12))
                } else {
                    Circle()
                        .fill(Color.Aurora.primary)
                        .frame(width: 6, height: 6)
                }
                
                Text(agentIdentity?.displayName ?? L10n.Drawer.assistant)
                    .font(.Aurora.micro.weight(.semibold))
                    .foregroundColor(Color.Aurora.textSecondary)
            }
            
            Markdown(message.content)
                .markdownTextStyle {
                    FontSize(13)
                    ForegroundColor(Color.Aurora.textPrimary)
                }
                .markdownBlockStyle(\.codeBlock) { configuration in
                    configuration.label
                        .padding(8)
                        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.05))
                        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm))
                }
                .textSelection(.enabled)
        }
        .padding(AuroraSpacing.space3)
        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .strokeBorder(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Reasoning Bubble

    // MARK: - Tool Bubble (with lifecycle status indicator)
    
    private var toolBubble: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
            HStack(spacing: AuroraSpacing.space2) {
                // Status-aware icon
                toolStatusIcon
                
                Text(message.toolName?.simplifiedToolName ?? L10n.Drawer.tool)
                    .font(.Aurora.caption.weight(.medium))
                    .foregroundColor(Color.Aurora.textSecondary)
                
                Spacer()
                
                if message.toolOutput != nil {
                    Button(action: { withAnimation(.auroraFast) { isDetailExpanded.toggle() } }) {
                        Text(isDetailExpanded ? L10n.hide : L10n.show)
                            .font(.Aurora.micro.weight(.medium))
                            .foregroundColor(Color.Aurora.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isDetailExpanded ? L10n.Drawer.hideOutput : L10n.Drawer.showOutput)
                }
            }
            
            // Tool input label (path, command, description — never raw output)
            if let toolInput = message.toolInput, !toolInput.isEmpty {
                Text(toolInput)
                    .font(.Aurora.monoSmall)
                    .foregroundColor(Color.Aurora.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            // Inline diff preview for file-editing tools (always visible, no click needed)
            if let diff = message.diffContent, !diff.isEmpty {
                diffPreview(diff)
            }
            
            // Uniform output summary: always "Output · N lines", click Show for details
            if let outputSummary = message.toolOutputSummary {
                Text(outputSummary)
                    .font(.Aurora.micro)
                    .foregroundColor(Color.Aurora.textMuted)
            } else if message.status == .running {
                // Tool is still executing — show processing hint
                Text(L10n.Drawer.processing)
                    .font(.Aurora.micro)
                    .foregroundColor(Color.Aurora.textMuted)
            }
            
            if isDetailExpanded, let output = message.toolOutput, !output.isEmpty {
                ScrollView {
                    formattedOutput(output)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 300)
                .padding(.top, AuroraSpacing.space2)
            }
        }
        .padding(.horizontal, AuroraSpacing.space3)
        .padding(.vertical, AuroraSpacing.space2)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .strokeBorder(toolBorderColor.opacity(0.3), lineWidth: 0.5)
        )
    }
    
    /// Status-aware icon for tool bubble: spinner when running, checkmark when done
    @ViewBuilder
    private var toolStatusIcon: some View {
        switch message.status {
        case .running:
            ToolRunningIndicator()
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.Aurora.success)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.Aurora.error)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.Aurora.textMuted)
        }
    }
    
    /// Border color that reflects tool status
    private var toolBorderColor: Color {
        switch message.status {
        case .running: return Color.Aurora.primary
        case .completed: return Color.Aurora.border
        case .failed: return Color.Aurora.error
        case .pending: return Color.Aurora.border
        }
    }
    
    // MARK: - Diff Preview
    
    /// Inline diff preview with syntax-colored +/- lines
    private func diffPreview(_ diff: String) -> some View {
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
        // Show at most 12 lines inline; truncate longer diffs
        let maxPreviewLines = 12
        let displayLines = isDetailExpanded ? Array(lines) : Array(lines.prefix(maxPreviewLines))
        let isTruncated = lines.count > maxPreviewLines
        
        return VStack(alignment: .leading, spacing: 0) {
            diffTitle(diff)
            
            ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                let lineStr = String(line)
                Text(lineStr)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(diffLineForeground(lineStr))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 1)
                    .padding(.horizontal, 6)
                    .background(diffLineBackground(lineStr))
            }
            if isTruncated {
                Button(action: { withAnimation(.auroraFast) { isDetailExpanded.toggle() } }) {
                    Text(isDetailExpanded ? L10n.showLess : String(format: L10n.showMoreLines, lines.count - maxPreviewLines))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.Aurora.textMuted)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AuroraSpacing.space2)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.05))
        )
        .padding(.top, AuroraSpacing.space1)
    }
    
    private func diffTitle(_ diff: String) -> some View {
        let title = extractDiffTitle(diff)
        return HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.Aurora.textMuted)
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.Aurora.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous))
        .padding(.bottom, 4)
    }
    
    private func extractDiffTitle(_ diff: String) -> String {
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            if line.hasPrefix("diff --git ") {
                let parts = line.split(separator: " ")
                if parts.count >= 4 {
                    let raw = parts[3]
                    return String(raw.replacingOccurrences(of: "b/", with: ""))
                }
            }
            if line.hasPrefix("+++ ") {
                let raw = line.dropFirst(4)
                return String(raw.replacingOccurrences(of: "b/", with: ""))
            }
        }
        return L10n.Drawer.changes
    }
    
    /// Foreground color for a single diff line based on +/- prefix
    private func diffLineForeground(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return Color.Aurora.textMuted
        } else if line.hasPrefix("+") {
            return Color.Aurora.textPrimary
        } else if line.hasPrefix("-") {
            return Color.Aurora.textPrimary
        } else if line.hasPrefix("@@") {
            return Color.Aurora.primary.opacity(0.7)
        }
        return Color.Aurora.textSecondary
    }
    
    /// Background color for a single diff line based on +/- prefix
    private func diffLineBackground(_ line: String) -> Color {
        if line.hasPrefix("+++ ") || line.hasPrefix("--- ") || line.hasPrefix("diff --git") {
            return Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.10)
        }
        if line.hasPrefix("+") {
            return Color.Aurora.success.opacity(isDark ? 0.18 : 0.12)
        }
        if line.hasPrefix("-") {
            return Color.Aurora.error.opacity(isDark ? 0.18 : 0.12)
        }
        return Color.clear
    }
    
    // MARK: - System Bubble
    
    private var systemBubble: some View {
        Group {
            if message.status == .failed {
                errorBubble
            } else {
                completionBubble
            }
        }
    }
    
    /// Compact completion / interruption indicator
    private var completionBubble: some View {
        HStack(spacing: AuroraSpacing.space2) {
            Image(systemName: completionIcon)
                .font(.system(size: 11))
                .foregroundColor(completionIconColor)
            
            Text(message.content)
                .font(.Aurora.bodySmall)
                .foregroundColor(Color.Aurora.textMuted)
        }
        .padding(.horizontal, AuroraSpacing.space3)
        .padding(.vertical, AuroraSpacing.space2)
    }
    
    /// Error bubble — shows a concise title with expandable details
    @ViewBuilder
    private var errorBubble: some View {
        let (title, detail) = Self.parseErrorMessage(message.content)
        
        VStack(alignment: .leading, spacing: 0) {
            // Header row: icon + title + Show button
            HStack(spacing: AuroraSpacing.space2) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color.Aurora.error)
                
                Text(title)
                    .font(.Aurora.bodySmall.weight(.medium))
                    .foregroundColor(Color.Aurora.error)
                    .lineLimit(1)
                
                Spacer()
                
                if detail != nil {
                    Button {
                        withAnimation(.auroraFast) { isDetailExpanded.toggle() }
                    } label: {
                        Text(isDetailExpanded ? L10n.hide : L10n.show)
                            .font(.Aurora.micro.weight(.semibold))
                            .foregroundColor(Color.Aurora.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AuroraSpacing.space3)
            .padding(.vertical, AuroraSpacing.space2)
            
            // Expandable detail
            if isDetailExpanded, let detail {
                Divider()
                    .background(Color.Aurora.error.opacity(0.15))
                
                Text(detail)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(Color.Aurora.textSecondary)
                    .textSelection(.enabled)
                    .padding(AuroraSpacing.space2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                .fill(Color.Aurora.error.opacity(isDark ? 0.08 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                        .strokeBorder(Color.Aurora.error.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
    
    /// Parse a raw error string into a concise title and optional detail body.
    /// Handles formats like "APIError: Bad Request: {...json...} (HTTP 400)"
    static func parseErrorMessage(_ raw: String) -> (title: String, detail: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to extract a human-readable message from JSON body
        if let jsonStart = trimmed.range(of: "{"),
           let data = String(trimmed[jsonStart.lowerBound...]).data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            // Extract just the first sentence / meaningful part
            let shortMessage = message.components(separatedBy: "..").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? message
            return (shortMessage, trimmed)
        }
        
        // Try to extract "Name: short description" before any JSON
        if let jsonStart = trimmed.range(of: "{") {
            let prefix = String(trimmed[trimmed.startIndex..<jsonStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                return (prefix, trimmed)
            }
        }
        
        // Short enough to show inline — no expansion needed
        if trimmed.count <= 100 {
            return (trimmed, nil)
        }
        
        // Truncate for title, full text as detail
        let titleEnd = trimmed.index(trimmed.startIndex, offsetBy: min(80, trimmed.count))
        return (String(trimmed[trimmed.startIndex..<titleEnd]) + "…", trimmed)
    }
    
    private var completionIcon: String {
        let lower = message.content.lowercased()
        if lower.contains("interrupt") || lower.contains("中断") || lower.contains("停止") {
            return "stop.circle.fill"
        }
        return "checkmark.circle.fill"
    }
    
    private var completionIconColor: Color {
        let lower = message.content.lowercased()
        if lower.contains("interrupt") || lower.contains("中断") || lower.contains("停止") {
            return Color.Aurora.textMuted
        }
        return Color.Aurora.success
    }
    
    // MARK: - Todo Bubble
    
    private var todoBubble: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space2) {
            // Header
            HStack(spacing: AuroraSpacing.space2) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.Aurora.primary)
                
                Text(L10n.Drawer.tasks)
                    .font(.Aurora.caption.weight(.semibold))
                    .foregroundColor(Color.Aurora.textSecondary)
                
                Spacer()
                
                // Progress summary
                if let items = message.todoItems {
                    let completed = items.filter { $0.status == .completed }.count
                    Text("\(completed)/\(items.count)")
                        .font(.Aurora.micro.weight(.medium))
                        .foregroundColor(Color.Aurora.textMuted)
                }
            }
            
            // Todo items list
            if let items = message.todoItems {
                // Progress bar
                todoProgressBar(items: items)
                
                VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
                    ForEach(items) { item in
                        todoItemRow(item)
                    }
                }
            }
        }
        .padding(AuroraSpacing.space3)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .strokeBorder(Color.Aurora.primary.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    /// Progress bar showing overall todo completion
    private func todoProgressBar(items: [TodoItem]) -> some View {
        let completed = Double(items.filter { $0.status == .completed }.count)
        let total = Double(items.count)
        let progress = total > 0 ? completed / total : 0
        
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.08))
                    .frame(height: 3)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(progress >= 1.0 ? Color.Aurora.success : Color.Aurora.primary)
                    .frame(width: geometry.size.width * progress, height: 3)
                    .animation(.auroraSpring, value: progress)
            }
        }
        .frame(height: 3)
    }
    
    /// Single todo item row with status icon
    private func todoItemRow(_ item: TodoItem) -> some View {
        HStack(spacing: AuroraSpacing.space2) {
            todoStatusIcon(item.status)
            
            Text(item.content)
                .font(.Aurora.caption)
                .foregroundColor(todoTextColor(item.status))
                .strikethrough(item.status == .completed || item.status == .cancelled,
                               color: Color.Aurora.textMuted.opacity(0.5))
                .lineLimit(2)
        }
        .padding(.vertical, 1)
    }
    
    /// Icon for todo item status
    @ViewBuilder
    private func todoStatusIcon(_ status: TodoItem.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.Aurora.textMuted)
        case .inProgress:
            Image(systemName: "arrow.trianglehead.clockwise.rotate.90")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.Aurora.primary)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.Aurora.success)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.Aurora.textMuted)
        }
    }
    
    /// Text color based on todo status
    private func todoTextColor(_ status: TodoItem.Status) -> Color {
        switch status {
        case .pending: return Color.Aurora.textSecondary
        case .inProgress: return Color.Aurora.textPrimary
        case .completed: return Color.Aurora.textMuted
        case .cancelled: return Color.Aurora.textMuted
        }
    }
    
    // MARK: - Timestamp Badge
    
    private var timestampBadge: some View {
        Text(message.timestamp, style: .time)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(Color.Aurora.textSecondary)
            .padding(.horizontal, AuroraSpacing.space2)
            .padding(.vertical, AuroraSpacing.space1)
            .background(
                Capsule()
                    .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.10 : 0.12))
            )
            .offset(
                x: message.type == .user ? -8 : 8,
                y: -8
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    // MARK: - Formatted Tool Output
    
    /// Detect content type and render with syntax highlighting via Markdown code blocks
    @ViewBuilder
    private func formattedOutput(_ output: String) -> some View {
        let lang = detectOutputLanguage(output)
        if let lang {
            // Pretty-print JSON for readability; other languages use raw output
            let displayText = (lang == "json") ? Self.prettyPrintJSON(output) : output
            let markdown = "```\(lang)\n\(displayText)\n```"
            Markdown(markdown)
                .markdownTextStyle {
                    FontSize(11)
                    ForegroundColor(Color.Aurora.textPrimary)
                }
                .markdownBlockStyle(\.codeBlock) { configuration in
                    configuration.label
                        .padding(6)
                        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.05 : 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xs))
                }
        } else {
            // Plain text fallback
            Text(output)
                .font(.Aurora.monoSmall)
                .foregroundColor(Color.Aurora.textPrimary)
        }
    }
    
    /// Pretty-print a JSON string with indentation. Returns original on failure.
    private static func prettyPrintJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return result
    }

    /// Detect the language/format of tool output for syntax highlighting
    private func detectOutputLanguage(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // JSON: starts with { or [
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            // Validate it's actual JSON (not just text in braces)
            if trimmed.data(using: .utf8).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) != nil {
                return "json"
            }
        }
        
        // Diff/patch: contains diff markers
        if trimmed.hasPrefix("---") || trimmed.hasPrefix("diff ") || trimmed.hasPrefix("@@") {
            return "diff"
        }
        // Also detect inline diff markers in multiline output
        let lines = trimmed.split(separator: "\n", maxSplits: 10)
        let diffMarkers = lines.filter { $0.hasPrefix("+") || $0.hasPrefix("-") || $0.hasPrefix("@@") }
        if diffMarkers.count > 2 && Double(diffMarkers.count) / Double(lines.count) > 0.3 {
            return "diff"
        }
        
        // Shell output: if the tool is Shell/Bash, hint as shell
        if let toolName = message.toolName?.lowercased(),
           toolName == "shell" || toolName == "bash" || toolName == "command" {
            return "bash"
        }
        
        // XML/HTML: starts with < and contains >
        if trimmed.hasPrefix("<") && trimmed.contains(">") {
            return "html"
        }
        
        return nil  // Plain text — no syntax highlighting
    }
    
    // MARK: - Tool Icon (legacy fallback)
    
    private var toolIcon: String {
        guard let toolName = message.toolName?.lowercased() else { return "terminal" }
        
        switch toolName {
        case "read", "read_file": return "doc.text"
        case "write", "write_file": return "square.and.pencil"
        case "edit", "edit_file": return "pencil"
        case "bash", "shell", "command": return "terminal"
        case "glob", "find", "search": return "magnifyingglass"
        case "grep": return "text.magnifyingglass"
        case "task", "agent": return "brain"
        default: return "wrench"
        }
    }
}

// MARK: - Tool Running Indicator (small spinner for tool bubble)

struct ToolRunningIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        Image(systemName: "arrow.trianglehead.2.counterclockwise")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color.Aurora.primary)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        // Metallic shimmer text — matches menu bar animation style.
        ShimmerText(
            text: L10n.Drawer.thinking,
            font: .Aurora.caption.weight(.medium)
        )
        .padding(.horizontal, AuroraSpacing.space3)
        .padding(.vertical, AuroraSpacing.space2)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.08))
        )
    }
}

// MARK: - Aurora Loading Dots

struct AuroraLoadingDots: View {
    @State private var animationPhase: Int = 0
    @State private var animationTask: Task<Void, Never>?
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.Aurora.primary)
                    .frame(width: 4, height: 4)
                    .scaleEffect(animationPhase == index ? 1.3 : 0.8)
                    .opacity(animationPhase == index ? 1.0 : 0.4)
            }
        }
        .onAppear {
            animationTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        animationPhase = (animationPhase + 1) % 3
                    }
                }
            }
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }
}

// MARK: - Session Status Badge

struct SessionStatusBadge: View {
    let status: AppState.SessionStatus
    let currentTool: String?
    let isThinking: Bool
    
    var body: some View {
        HStack(spacing: AuroraSpacing.space1) {
            statusIcon
                .font(.system(size: 10, weight: .bold))

            if status == .running && isThinking {
                ShimmerText(text: statusText)
            } else {
                Text(statusText)
                    .font(.Aurora.micro.weight(.semibold))
            }
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, AuroraSpacing.space2)
        .padding(.vertical, AuroraSpacing.space1)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(backgroundColor)
        )
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .idle:
            Image(systemName: "circle")
        case .running:
            Image(systemName: "circle.fill")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "xmark.circle.fill")
        case .interrupted:
            Image(systemName: "pause.circle.fill")
        }
    }
    
    private var statusText: String {
        switch status {
        case .idle:
            return L10n.StatusBar.idle
        case .running:
            return currentTool?.simplifiedToolName ?? L10n.Drawer.running
        case .completed:
            return L10n.Drawer.completed
        case .failed:
            return L10n.Drawer.failed
        case .interrupted:
            return L10n.Drawer.interrupted
        }
    }
    
    private var foregroundColor: Color {
        switch status {
        case .idle: return Color.Aurora.textMuted
        case .running: return Color.Aurora.primary
        case .completed: return Color.Aurora.success
        case .failed: return Color.Aurora.error
        case .interrupted: return Color.Aurora.warning
        }
    }
    
    private var backgroundColor: Color {
        foregroundColor.opacity(0.12)
    }
}

// MARK: - Context Size Badge

struct ContextSizeBadge: View {
    let tokens: Int

    var body: some View {
        HStack(spacing: AuroraSpacing.space1) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 10, weight: .bold))

            Text("CTX \(TokenUsageFormatter.formatTokens(tokens))")
                .font(.Aurora.micro.weight(.semibold))
        }
        .foregroundColor(Color.Aurora.textSecondary)
        .padding(.horizontal, AuroraSpacing.space2)
        .padding(.vertical, AuroraSpacing.space1)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(0.08))
        )
    }
}

// MARK: - Shimmer Text (thin wrapper over AuroraShimmer)

struct ShimmerText: View {
    let text: String
    var font: Font = .Aurora.micro.weight(.semibold)
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(font)
            .auroraShimmer(isDark: colorScheme == .dark)
    }
}

// MARK: - Transient Reasoning Bubble

/// A standalone bubble that shows live reasoning text during the thinking phase.
/// This is NOT a message — it appears transiently and disappears when thinking ends.
struct TransientReasoningBubble: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let maxLines = 5
        let isTruncated = lines.count > maxLines
        let displayLines = isExpanded ? lines : Array(lines.suffix(maxLines))
        let displayText = displayLines.joined(separator: "\n")

        HStack {
            VStack(alignment: .leading, spacing: AuroraSpacing.space2) {
                HStack(spacing: AuroraSpacing.space2) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.Aurora.textSecondary)
                    Text(L10n.Drawer.thinking)
                        .font(.Aurora.micro.weight(.semibold))
                        .foregroundColor(Color.Aurora.textSecondary)
                        .auroraShimmer(isDark: isDark)
                    Spacer()
                    if isTruncated {
                        Button(action: { withAnimation(.auroraFast) { isExpanded.toggle() } }) {
                            Text(isExpanded ? L10n.collapse : L10n.expand)
                                .font(.Aurora.micro.weight(.medium))
                                .foregroundColor(Color.Aurora.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !trimmed.isEmpty {
                    Markdown(displayText)
                        .markdownTextStyle {
                            FontSize(12)
                            ForegroundColor(Color.Aurora.textPrimary)
                        }
                        .markdownBlockStyle(\.codeBlock) { configuration in
                            configuration.label
                                .padding(6)
                                .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.05 : 0.04))
                                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xs))
                        }
                        .textSelection(.enabled)
                }
            }
            .padding(AuroraSpacing.space3)
            .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                    .strokeBorder(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.06), lineWidth: 0.5)
            )

            Spacer(minLength: 40)
        }
    }
}
