//
//  QuickConfirmView.swift
//  Motive
//
//  Aurora Design System - Quick Confirm Popup
//

import SwiftUI

struct QuickConfirmView: View {
    let request: PermissionRequest
    let onResponse: (String) -> Void
    let onCancel: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedOptions: Set<String> = []
    @State private var textInput: String = ""
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerView
            Rectangle()
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.12))
                .frame(height: 0.5)
            contentView
            Rectangle()
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.12))
                .frame(height: 0.5)
            actionButtons
        }
        .padding(20)
        .frame(width: 360)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .strokeBorder(Color.Aurora.glassOverlay.opacity(isDark ? 0.1 : 0.15), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(isDark ? 0.25 : 0.12), radius: 18, y: 10)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.Aurora.primary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.Aurora.textPrimary)
                
                if let subtitle = headerSubtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.textSecondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Close button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.Aurora.textMuted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.cancel)
        }
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentView: some View {
        switch request.type {
        case .question:
            questionContent
        case .permission:
            permissionContent
        }
    }
    
    private var questionContent: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space3) {
            // Question text
            if let question = request.question {
                Text(question)
                    .font(.system(size: 13))
                    .foregroundColor(Color.Aurora.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Options or text input
            if let options = request.options, !options.isEmpty {
                optionsView(options: options)
            } else {
                // Free text input
                AuroraStyledTextField(
                    placeholder: L10n.Permission.typeAnswer,
                    text: $textInput
                )
            }
        }
    }
    
    private func optionsView(options: [PermissionRequest.QuestionOption]) -> some View {
        VStack(spacing: AuroraSpacing.space2) {
            ForEach(options, id: \.effectiveValue) { option in
                optionButton(option: option)
            }
        }
    }
    
    private func optionButton(option: PermissionRequest.QuestionOption) -> some View {
        let optionValue = option.effectiveValue
        let isSelected = selectedOptions.contains(optionValue)
        let isMultiSelect = request.multiSelect == true
        
        return Button {
            if isMultiSelect {
                if isSelected {
                    selectedOptions.remove(optionValue)
                } else {
                    selectedOptions.insert(optionValue)
                }
            } else {
                onResponse(optionValue)
            }
        } label: {
            HStack(spacing: AuroraSpacing.space3) {
                if isMultiSelect {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? Color.Aurora.primary : Color.Aurora.textSecondary)
                }
                
                Text(option.label)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(Color.Aurora.textPrimary)
                
                Spacer()
                
                if !isMultiSelect {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.Aurora.textMuted)
                }
            }
            .padding(.horizontal, AuroraSpacing.space3)
            .padding(.vertical, AuroraSpacing.space3)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(isSelected ? Color.Aurora.primary.opacity(0.1) : Color.Aurora.glassOverlay.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .stroke(isSelected ? Color.Aurora.primary.opacity(0.3) : Color.Aurora.glassOverlay.opacity(0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var permissionContent: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space2) {
            // Permission type (e.g., "edit", "bash")
            if let permType = request.permissionType {
                HStack(spacing: AuroraSpacing.space2) {
                    Text(L10n.Permission.permissionLabel)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.textSecondary)

                    Text(permType.capitalized)
                        .font(.Aurora.mono.weight(.medium))
                        .foregroundColor(Color.Aurora.textPrimary)
                }
            }

            // File paths / patterns
            if let patterns = request.patterns, !patterns.isEmpty {
                HStack(spacing: AuroraSpacing.space2) {
                    Text(patterns.count == 1 ? L10n.Permission.pathLabel : L10n.Permission.pathsLabel)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.textSecondary)

                    Text(patterns.map { shortenPath($0) }.joined(separator: ", "))
                        .font(.Aurora.monoSmall)
                        .foregroundColor(Color.Aurora.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            // Diff preview if available
            if let diff = request.diff, !diff.isEmpty {
                DiffView(diff: diff)
                    .frame(maxHeight: 160)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    @ViewBuilder
    private var actionButtons: some View {
        switch request.type {
        case .question:
            if request.multiSelect == true || request.options == nil {
                HStack(spacing: AuroraSpacing.space2) {
                    Spacer()
                    
                    Button(L10n.cancel) {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(L10n.submit) {
                        if request.options != nil {
                            onResponse(selectedOptions.joined(separator: ","))
                        } else {
                            onResponse(textInput)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.Aurora.primary)
                    .controlSize(.small)
                    .disabled(request.options != nil ? selectedOptions.isEmpty : textInput.isEmpty)
                }
            }
            
        case .permission:
            HStack(spacing: AuroraSpacing.space2) {
                Spacer()
                
                Button(L10n.reject) {
                    onResponse("Reject")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(L10n.allowOnce) {
                    onResponse("Allow Once")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.Aurora.primary)
                .controlSize(.small)
                
                Button(L10n.alwaysAllow) {
                    onResponse("Always Allow")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.Aurora.success)
                .controlSize(.small)
            }
        }
    }
    
    // MARK: - Background
    
    private var backgroundView: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)
            Color.Aurora.background.opacity(isDark ? 0.6 : 0.7)
        }
    }
    
    // MARK: - Helpers
    
    private var iconName: String {
        switch request.type {
        case .question: return "hand.raised"
        case .permission: return "lock.shield"
        }
    }
    
    private var headerTitle: String {
        switch request.type {
        case .question:
            return request.header ?? L10n.Permission.question
        case .permission:
            return L10n.Permission.permissionRequired
        }
    }
    
    private var headerSubtitle: String? {
        switch request.type {
        case .question:
            return nil
        case .permission:
            return request.permissionType?.capitalized
        }
    }
    
    private func shortenPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count > 3 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return path
    }
}

// MARK: - Aurora Quick Confirm Button Style

private struct AuroraQuickConfirmButtonStyle: ButtonStyle {
    enum Style {
        case primary, secondary
    }
    
    let style: Style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.Aurora.bodySmall.weight(.medium))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space2)
            .background(background(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
            .overlay(overlay)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.auroraSpringStiff, value: configuration.isPressed)
    }
    
    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        switch style {
        case .primary:
            LinearGradient(
                colors: Color.Aurora.auroraGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(isPressed ? 0.8 : 1.0)
        case .secondary:
            Color.Aurora.surface
                .opacity(isPressed ? 0.8 : 1.0)
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return Color.Aurora.textPrimary
        }
    }
    
    @ViewBuilder
    private var overlay: some View {
        if style == .secondary {
            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                .stroke(Color.Aurora.border, lineWidth: 1)
        }
    }
}

// MARK: - Diff View

/// Renders a unified diff with red/green colored lines like GitHub/Cursor.
struct DiffView: View {
    let diff: String
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    private var parsedLines: [DiffLine] {
        DiffParser.parse(diff)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(parsedLines.enumerated()), id: \.offset) { _, line in
                    diffLineView(line)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(isDark ? Color(white: 0.08) : Color(white: 0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .stroke(Color.Aurora.border.opacity(0.5), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous))
    }

    private func diffLineView(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            // Line number gutter
            HStack(spacing: 2) {
                Text(line.oldLineNumber ?? "")
                    .frame(width: 28, alignment: .trailing)
                Text(line.newLineNumber ?? "")
                    .frame(width: 28, alignment: .trailing)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(Color.Aurora.textMuted.opacity(0.6))
            .padding(.trailing, 4)

            // Prefix character (+, -, space)
            Text(line.prefix)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(line.prefixColor(isDark: isDark))
                .frame(width: 12)

            // Content
            Text(line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(line.textColor(isDark: isDark))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(line.backgroundColor(isDark: isDark))
    }
}

// MARK: - Diff Parser

enum DiffLineType: Sendable {
    case addition
    case deletion
    case context
    case header     // @@ ... @@ or diff --git lines
    case meta       // --- or +++ lines
}

struct DiffLine: Sendable {
    let type: DiffLineType
    let content: String
    let prefix: String
    let oldLineNumber: String?
    let newLineNumber: String?

    func backgroundColor(isDark: Bool) -> Color {
        switch type {
        case .addition:
            return isDark
                ? Color(red: 0.1, green: 0.3, blue: 0.1).opacity(0.5)
                : Color(red: 0.85, green: 1.0, blue: 0.85)
        case .deletion:
            return isDark
                ? Color(red: 0.35, green: 0.1, blue: 0.1).opacity(0.5)
                : Color(red: 1.0, green: 0.9, blue: 0.9)
        case .header, .meta:
            return isDark
                ? Color(red: 0.15, green: 0.2, blue: 0.35).opacity(0.4)
                : Color(red: 0.92, green: 0.95, blue: 1.0)
        case .context:
            return .clear
        }
    }

    func textColor(isDark: Bool) -> Color {
        switch type {
        case .addition:
            return isDark ? Color(red: 0.5, green: 0.9, blue: 0.5) : Color(red: 0.1, green: 0.5, blue: 0.1)
        case .deletion:
            return isDark ? Color(red: 0.95, green: 0.5, blue: 0.5) : Color(red: 0.6, green: 0.1, blue: 0.1)
        case .header, .meta:
            return isDark ? Color(red: 0.5, green: 0.7, blue: 1.0) : Color(red: 0.2, green: 0.3, blue: 0.6)
        case .context:
            return isDark ? Color(white: 0.7) : Color(white: 0.3)
        }
    }

    func prefixColor(isDark: Bool) -> Color {
        switch type {
        case .addition:
            return isDark ? Color(red: 0.3, green: 0.9, blue: 0.3) : Color(red: 0.1, green: 0.6, blue: 0.1)
        case .deletion:
            return isDark ? Color(red: 0.95, green: 0.35, blue: 0.35) : Color(red: 0.7, green: 0.1, blue: 0.1)
        default:
            return .clear
        }
    }
}

enum DiffParser {
    /// Parse a unified diff string into typed lines with line numbers.
    static func parse(_ diff: String) -> [DiffLine] {
        let rawLines = diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [DiffLine] = []
        var oldLine = 0
        var newLine = 0

        for raw in rawLines {
            if raw.hasPrefix("@@") {
                // Parse hunk header: @@ -oldStart,oldCount +newStart,newCount @@
                let numbers = parseHunkHeader(raw)
                oldLine = numbers.oldStart
                newLine = numbers.newStart
                result.append(DiffLine(type: .header, content: raw, prefix: "", oldLineNumber: nil, newLineNumber: nil))
            } else if raw.hasPrefix("diff ") || raw.hasPrefix("index ") {
                result.append(DiffLine(type: .header, content: raw, prefix: "", oldLineNumber: nil, newLineNumber: nil))
            } else if raw.hasPrefix("---") || raw.hasPrefix("+++") {
                result.append(DiffLine(type: .meta, content: raw, prefix: "", oldLineNumber: nil, newLineNumber: nil))
            } else if raw.hasPrefix("+") {
                let content = String(raw.dropFirst())
                result.append(DiffLine(type: .addition, content: content, prefix: "+", oldLineNumber: nil, newLineNumber: "\(newLine)"))
                newLine += 1
            } else if raw.hasPrefix("-") {
                let content = String(raw.dropFirst())
                result.append(DiffLine(type: .deletion, content: content, prefix: "-", oldLineNumber: "\(oldLine)", newLineNumber: nil))
                oldLine += 1
            } else {
                // Context line (starts with space or is empty)
                let content = raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw
                result.append(DiffLine(type: .context, content: content, prefix: " ", oldLineNumber: "\(oldLine)", newLineNumber: "\(newLine)"))
                oldLine += 1
                newLine += 1
            }
        }

        return result
    }

    /// Parse @@ -start,count +start,count @@ into start values.
    private static func parseHunkHeader(_ header: String) -> (oldStart: Int, newStart: Int) {
        // Matches: @@ -10,5 +10,8 @@
        let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)) else {
            return (1, 1)
        }
        let oldStart = Int(header[Range(match.range(at: 1), in: header)!]) ?? 1
        let newStart = Int(header[Range(match.range(at: 2), in: header)!]) ?? 1
        return (oldStart, newStart)
    }
}
