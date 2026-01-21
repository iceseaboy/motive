//
//  QuickConfirmView.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

struct QuickConfirmView: View {
    let request: PermissionRequest
    let onResponse: (String) -> Void
    let onCancel: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedOptions: Set<String> = []
    @State private var textInput: String = ""
    @State private var isHovering: Bool = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            headerView
            
            // Content based on request type
            contentView
            
            // Actions
            actionButtons
        }
        .padding(16)
        .frame(width: 320)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(isDark ? 0.3 : 0.12), radius: 20, x: 0, y: 10)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 10) {
            // Icon based on type
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                if let subtitle = headerSubtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Close button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentView: some View {
        switch request.type {
        case .question:
            questionContent
        case .file:
            filePermissionContent
        case .tool:
            toolPermissionContent
        }
    }
    
    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Question text
            if let question = request.question {
                Text(question)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Options or text input
            if let options = request.options, !options.isEmpty {
                optionsView(options: options)
            } else {
                // Free text input
                TextField("Type your answer...", text: $textInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(10)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    private func optionsView(options: [PermissionRequest.QuestionOption]) -> some View {
        VStack(spacing: 6) {
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
                // Single select - submit immediately
                onResponse(optionValue)
            }
        } label: {
            HStack(spacing: 10) {
                if isMultiSelect {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? .blue : .secondary)
                }
                
                Text(option.label)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if !isMultiSelect {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var filePermissionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Operation description
            HStack(spacing: 8) {
                Text(operationVerb)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                
                if let path = request.filePath {
                    Text(shortenPath(path))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            // Preview if available
            if let preview = request.contentPreview, !preview.isEmpty {
                ScrollView {
                    Text(preview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
    
    private var toolPermissionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let toolName = request.toolName {
                HStack(spacing: 8) {
                    Text("Tool:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    Text(toolName)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
    
    // MARK: - Action Buttons
    
    @ViewBuilder
    private var actionButtons: some View {
        switch request.type {
        case .question:
            if request.multiSelect == true || request.options == nil {
                // Multi-select or text input needs confirm button
                HStack(spacing: 8) {
                    Spacer()
                    
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(QuickConfirmButtonStyle(isPrimary: false))
                    
                    Button("Confirm") {
                        if request.options != nil {
                            onResponse(selectedOptions.joined(separator: ","))
                        } else {
                            onResponse(textInput)
                        }
                    }
                    .buttonStyle(QuickConfirmButtonStyle(isPrimary: true))
                    .disabled(request.options != nil ? selectedOptions.isEmpty : textInput.isEmpty)
                }
            }
            // Single-select options don't need buttons - they submit on click
            
        case .file, .tool:
            HStack(spacing: 8) {
                Spacer()
                
                Button(L10n.deny) {
                    onResponse("denied")
                }
                .buttonStyle(QuickConfirmButtonStyle(isPrimary: false))
                
                Button(L10n.allow) {
                    onResponse("approved")
                }
                .buttonStyle(QuickConfirmButtonStyle(isPrimary: true))
            }
        }
    }
    
    // MARK: - Background
    
    private var backgroundView: some View {
        ZStack {
            // Blur effect
            VisualEffectBlur(material: .popover, blendingMode: .behindWindow)
            
            // Base overlay for consistency
            if isDark {
                Color(hex: "1C1C1E").opacity(0.85)
            } else {
                Color.white.opacity(0.85)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var iconName: String {
        switch request.type {
        case .question: return "questionmark.circle"
        case .file: return "doc.badge.gearshape"
        case .tool: return "wrench.and.screwdriver"
        }
    }
    
    private var iconColor: Color {
        switch request.type {
        case .question: return .blue
        case .file: return .orange
        case .tool: return .purple
        }
    }
    
    private var headerTitle: String {
        switch request.type {
        case .question:
            return request.header ?? "Question"
        case .file:
            return "File Permission"
        case .tool:
            return "Tool Permission"
        }
    }
    
    private var headerSubtitle: String? {
        switch request.type {
        case .question:
            return nil
        case .file:
            return request.fileOperation?.rawValue.capitalized
        case .tool:
            return request.toolName
        }
    }
    
    private var operationVerb: String {
        guard let op = request.fileOperation else { return "Access" }
        switch op {
        case .create: return "Create"
        case .delete: return "Delete"
        case .rename: return "Rename"
        case .move: return "Move"
        case .modify: return "Modify"
        case .overwrite: return "Overwrite"
        case .readBinary: return "Read"
        case .execute: return "Execute"
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

// MARK: - Button Style

struct QuickConfirmButtonStyle: ButtonStyle {
    let isPrimary: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isPrimary ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isPrimary ? Color.Velvet.primary : Color.primary.opacity(0.08))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Visual Effect

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
