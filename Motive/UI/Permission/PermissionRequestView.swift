import SwiftUI

/// Modal view for displaying permission requests
struct PermissionRequestView: View {
    let request: PermissionRequest
    let onRespond: (PermissionResponse) -> Void
    
    @State private var selectedOptions: Set<String> = []
    @State private var customResponse: String = ""
    @State private var showCustomInput: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // Dismiss on backdrop tap (deny)
                    respond(allowed: false)
                }
            
            // Modal Card
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .top, spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(iconBackgroundColor)
                            .frame(width: 40, height: 40)
                        
                        iconImage
                            .font(.system(size: 18))
                            .foregroundColor(iconColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headerTitle)
                            .font(.headline)
                            .foregroundColor(Color.Velvet.textPrimary)
                        
                        // Content based on request type
                        requestContent
                    }
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button(action: { respond(allowed: false) }) {
                        Text(denyButtonText)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { respond(allowed: true) }) {
                        Text(allowButtonText)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.primary.opacity(0.8))
                    .disabled(isAllowDisabled)
                }
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 20)
            .padding(32)
        }
        .onAppear {
            if request.type == .question,
               (request.options?.isEmpty ?? true) {
                showCustomInput = true
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var headerTitle: String {
        if request.isDeleteOperation {
            return "File Deletion Warning"
        }
        
        switch request.type {
        case .file:
            return "File Permission Required"
        case .question:
            return request.header ?? "Question"
        case .tool:
            return "Permission Required"
        }
    }
    
    private var iconBackgroundColor: Color {
        // Monochrome for all types
        return Color.primary.opacity(0.08)
    }
    
    private var iconColor: Color {
        // Monochrome for all types
        return Color.primary.opacity(0.8)
    }
    
    private var iconImage: Image {
        if request.isDeleteOperation {
            return Image(systemName: "exclamationmark.triangle.fill")
        }
        
        switch request.type {
        case .file:
            return Image(systemName: "doc.fill")
        case .question:
            return Image(systemName: "hand.raised.fill")
        case .tool:
            return Image(systemName: "hand.raised.fill")
        }
    }
    
    private var denyButtonText: String {
        request.type == .question ? "Cancel" : "Deny"
    }
    
    private var allowButtonText: String {
        if request.isDeleteOperation {
            return request.displayFilePaths.count > 1 ? "Delete All" : "Delete"
        }
        return request.type == .question ? "Submit" : "Allow"
    }
    
    private var isAllowDisabled: Bool {
        // For questions with options, require at least one selection
        if request.type == .question,
           !showCustomInput,
           let options = request.options,
           !options.isEmpty {
            return selectedOptions.isEmpty
        }
        return false
    }
    
    // MARK: - Request Content
    
    @ViewBuilder
    private var requestContent: some View {
        switch request.type {
        case .file:
            filePermissionContent
        case .question:
            questionContent
        case .tool:
            toolContent
        }
    }
    
    @ViewBuilder
    private var filePermissionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Delete warning banner
            if request.isDeleteOperation {
                HStack {
                    Text(request.displayFilePaths.count > 1
                         ? "\(request.displayFilePaths.count) files will be permanently deleted:"
                         : "This file will be permanently deleted:")
                        .font(.caption)
                        .foregroundColor(Color.Velvet.textPrimary)
                }
                .padding(8)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let operation = request.fileOperation {
                // Operation badge
                Text(operation.rawValue.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(operationBadgeColor(for: operation))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            
            // File paths
            VStack(alignment: .leading, spacing: 4) {
                ForEach(request.displayFilePaths, id: \.self) { path in
                    Text(request.displayFilePaths.count > 1 ? "• \(path)" : path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color.Velvet.textPrimary)
                }
                
                if let targetPath = request.targetPath {
                    Text("→ \(targetPath)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(Color.Velvet.textSecondary)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Delete warning text
            if request.isDeleteOperation {
                Text("This action cannot be undone.")
                    .font(.caption)
                    .foregroundColor(Color.Velvet.textSecondary)
            }
            
            // Content preview
            if let preview = request.contentPreview {
                DisclosureGroup("Preview content") {
                    ScrollView {
                        Text(preview)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(Color.Velvet.textSecondary)
                    }
                    .frame(maxHeight: 100)
                }
                .font(.caption)
                .foregroundColor(Color.Velvet.textSecondary)
            }
        }
    }
    
    @ViewBuilder
    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question text
            if let question = request.question {
                Text(question)
                    .font(.subheadline)
                    .foregroundColor(Color.Velvet.textPrimary)
            }
            
            // Options or custom input
            if showCustomInput {
                // Custom text input
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Type your response...", text: $customResponse)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !customResponse.trimmingCharacters(in: .whitespaces).isEmpty {
                                respond(allowed: true)
                            }
                        }
                    
                    Button("← Back to options") {
                        showCustomInput = false
                        customResponse = ""
                    }
                    .font(.caption)
                    .foregroundColor(Color.Velvet.textSecondary)
                }
            } else if let options = request.options, !options.isEmpty {
                // Options list
                VStack(spacing: 8) {
                    ForEach(options, id: \.label) { option in
                        Button(action: {
                            if option.label.lowercased() == "other" {
                                showCustomInput = true
                                selectedOptions.removeAll()
                            } else if request.multiSelect == true {
                                if selectedOptions.contains(option.label) {
                                    selectedOptions.remove(option.label)
                                } else {
                                    selectedOptions.insert(option.label)
                                }
                            } else {
                                selectedOptions = [option.label]
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .font(.subheadline.weight(.medium))
                                    
                                    if let desc = option.description {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundColor(Color.Velvet.textSecondary)
                                    }
                                }
                                
                                Spacer()
                                
                if selectedOptions.contains(option.label) {
                    Image(systemName: "checkmark")
                        .foregroundColor(Color.primary.opacity(0.8))
                }
                            }
                        .padding(12)
                        .background(selectedOptions.contains(option.label)
                                    ? Color.primary.opacity(0.08)
                                    : Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedOptions.contains(option.label)
                                        ? Color.primary.opacity(0.3)
                                        : Color.Velvet.border, lineWidth: 1)
                        )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var toolContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let toolName = request.toolName {
                Text("Allow \(toolName.simplifiedToolName)?")
                    .font(.subheadline)
                    .foregroundColor(Color.Velvet.textSecondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tool: \(toolName.simplifiedToolName)")
                        .font(.caption)
                        .foregroundColor(Color.Velvet.textSecondary)
                    
                    if let input = request.toolInput {
                        ScrollView {
                            Text(formatToolInput(input))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(Color.Velvet.textPrimary)
                        }
                        .frame(maxHeight: 100)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    // MARK: - Helpers
    
    private func operationBadgeColor(for operation: FileOperation) -> Color {
        // Monochrome for all operations
        return Color.primary.opacity(0.08)
    }
    
    private func formatToolInput(_ input: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: input, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: input)
    }
    
    private func respond(allowed: Bool) {
        var response = PermissionResponse(
            requestId: request.id,
            taskId: request.taskId,
            decision: allowed ? .allow : .deny
        )
        
        // For questions, include selected options or custom text
        if request.type == .question {
            if showCustomInput && !customResponse.trimmingCharacters(in: .whitespaces).isEmpty {
                response.customText = customResponse.trimmingCharacters(in: .whitespaces)
            } else if !selectedOptions.isEmpty {
                response.selectedOptions = Array(selectedOptions)
            }
        }
        
        onRespond(response)
    }
}

// MARK: - Preview

#Preview {
    PermissionRequestView(
        request: PermissionRequest(
            id: "test",
            taskId: "task_1",
            type: .file,
            fileOperation: .delete,
            filePath: "/Users/test/Documents/important.txt"
        ),
        onRespond: { _ in }
    )
    .frame(width: 500, height: 400)
}
