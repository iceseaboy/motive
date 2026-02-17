//
//  ScheduledTasksSettingsView.swift
//  Motive
//
//  Created by Codex on 2026/2/16.
//

import SwiftData
import SwiftUI

struct ScheduledTasksSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var configManager: ConfigManager

    @State private var tasks: [ScheduledTask] = []
    @State private var latestRunsByTaskID: [UUID: ScheduledTaskRun] = [:]
    @State private var editorState: ScheduledTaskEditorState?
    @State private var inlineError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingSection("Runtime Scheduler") {
                SettingRow(
                    "Scope",
                    description: "Scheduled tasks run only while Motive is running.",
                    showDivider: false
                ) {
                    Text("In-app only")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.Aurora.textSecondary)
                }
            }

            SettingSection("Scheduled Tasks") {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    scheduledTaskRow(task: task, showDivider: index < tasks.count - 1)
                }
                if tasks.isEmpty {
                    SettingRow("No tasks yet", description: "Create your first scheduled task.", showDivider: false) {
                        EmptyView()
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    editorState = .create
                } label: {
                    Label("New Task", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)

                Button {
                    reloadData()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            if let inlineError, !inlineError.isEmpty {
                Text(inlineError)
                    .font(.system(size: 12))
                    .foregroundColor(Color.Aurora.warning)
            }

            Spacer()
        }
        .onAppear {
            reloadData()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    reloadData()
                }
            }
        }
        .sheet(item: $editorState) { state in
            ScheduledTaskEditorSheet(
                existingTask: state.existingTask,
                defaultProjectPath: configManager.currentProjectURL.path
            ) { draft in
                saveDraft(draft, editingTask: state.existingTask)
            }
        }
    }

    private func scheduledTaskRow(task: ScheduledTask, showDivider: Bool) -> some View {
        SettingRow(
            task.name,
            description: scheduleDescription(for: task),
            showDivider: showDivider
        ) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { task.isEnabled },
                    set: { value in
                        task.isEnabled = value
                        task.updatedAt = Date()
                        task.lastError = nil
                        recalculate(task: task)
                        persistAndRefresh()
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Color.Aurora.primary)

                Button("Run Now") {
                    runNow(task)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    editorState = .edit(task)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    delete(task)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func scheduleDescription(for task: ScheduledTask) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let nextText: String = if let nextRunAt = task.nextRunAt {
            formatter.localizedString(for: nextRunAt, relativeTo: Date())
        } else {
            "not scheduled"
        }
        let runText: String = if let run = latestRunsByTaskID[task.id] {
            run.status
        } else {
            "never run"
        }
        return "Next: \(nextText) · Last: \(runText)"
    }

    private func saveDraft(_ draft: ScheduledTaskDraft, editingTask: ScheduledTask?) {
        guard let modelContext = appState.modelContext else { return }
        inlineError = nil

        do {
            let payload = try draft.payloadString()
            let now = Date()
            let task = editingTask ?? ScheduledTask(
                name: draft.name,
                prompt: draft.prompt,
                scheduleType: draft.scheduleType,
                schedulePayload: payload,
                timezoneIdentifier: draft.timezoneIdentifier,
                isEnabled: draft.isEnabled,
                projectPath: draft.projectPath,
                agent: draft.agent,
                createdAt: now,
                updatedAt: now
            )

            task.name = draft.name
            task.prompt = draft.prompt
            task.scheduleKind = draft.scheduleType
            task.schedulePayload = payload
            task.timezoneIdentifier = draft.timezoneIdentifier
            task.isEnabled = draft.isEnabled
            task.projectPath = draft.projectPath.nilIfBlank
            task.agent = draft.agent.nilIfBlank
            task.updatedAt = now
            task.lastError = nil
            task.nextRunAt = try NextRunCalculator.nextRun(for: task, from: now)

            if editingTask == nil {
                modelContext.insert(task)
            }
            try modelContext.save()
            appState.refreshScheduledTaskSystem()
            reloadData()
        } catch {
            inlineError = error.localizedDescription
        }
    }

    private func runNow(_ task: ScheduledTask) {
        inlineError = nil
        appState.runScheduledTaskNow(task.id)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            reloadData()
        }
    }

    private func delete(_ task: ScheduledTask) {
        guard let modelContext = appState.modelContext else { return }
        modelContext.delete(task)
        do {
            try modelContext.save()
            appState.refreshScheduledTaskSystem()
            reloadData()
        } catch {
            inlineError = error.localizedDescription
        }
    }

    private func recalculate(task: ScheduledTask) {
        do {
            task.nextRunAt = try NextRunCalculator.nextRun(for: task, from: Date())
            task.lastError = nil
        } catch {
            task.lastError = error.localizedDescription
            task.nextRunAt = nil
            inlineError = error.localizedDescription
        }
    }

    private func persistAndRefresh() {
        guard let modelContext = appState.modelContext else { return }
        do {
            try modelContext.save()
            appState.refreshScheduledTaskSystem()
            reloadData()
        } catch {
            inlineError = error.localizedDescription
        }
    }

    private func reloadData() {
        guard let modelContext = appState.modelContext else { return }
        let taskDescriptor = FetchDescriptor<ScheduledTask>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        tasks = (try? modelContext.fetch(taskDescriptor)) ?? []

        let runDescriptor = FetchDescriptor<ScheduledTaskRun>(sortBy: [SortDescriptor(\.triggeredAt, order: .reverse)])
        let runs = (try? modelContext.fetch(runDescriptor)) ?? []
        var latest: [UUID: ScheduledTaskRun] = [:]
        for run in runs where latest[run.taskID] == nil {
            latest[run.taskID] = run
        }
        latestRunsByTaskID = latest
    }
}

private enum ScheduledTaskEditorState: Identifiable {
    case create
    case edit(ScheduledTask)

    var id: String {
        switch self {
        case .create:
            "create"
        case let .edit(task):
            "edit-\(task.id.uuidString)"
        }
    }

    var existingTask: ScheduledTask? {
        switch self {
        case .create:
            nil
        case let .edit(task):
            task
        }
    }
}

private struct ScheduledTaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingTask: ScheduledTask?
    let defaultProjectPath: String
    let onSave: (ScheduledTaskDraft) -> Void

    @State private var draft: ScheduledTaskDraft
    @State private var errorMessage: String?

    init(existingTask: ScheduledTask?, defaultProjectPath: String, onSave: @escaping (ScheduledTaskDraft) -> Void) {
        self.existingTask = existingTask
        self.defaultProjectPath = defaultProjectPath
        self.onSave = onSave
        if let existingTask {
            _draft = State(initialValue: ScheduledTaskDraft(task: existingTask))
        } else {
            _draft = State(initialValue: ScheduledTaskDraft(defaultProjectPath: defaultProjectPath))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existingTask == nil ? "New Scheduled Task" : "Edit Scheduled Task")
                .font(.system(size: 16, weight: .semibold))

            TextField("Task name", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            TextField("Prompt", text: $draft.prompt, axis: .vertical)
                .lineLimit(3 ... 8)
                .textFieldStyle(.roundedBorder)

            TextField("Working directory (optional)", text: $draft.projectPath)
                .textFieldStyle(.roundedBorder)

            TextField("Agent (optional)", text: $draft.agent)
                .textFieldStyle(.roundedBorder)

            Picker("Schedule type", selection: $draft.scheduleType) {
                Text("Once").tag(ScheduledTaskScheduleType.once)
                Text("Interval").tag(ScheduledTaskScheduleType.interval)
                Text("Daily").tag(ScheduledTaskScheduleType.daily)
                Text("Weekly").tag(ScheduledTaskScheduleType.weekly)
                Text("Cron").tag(ScheduledTaskScheduleType.cron)
            }
            .pickerStyle(.segmented)

            scheduleEditor

            Toggle("Enabled", isOn: $draft.isEnabled)

            Text(previewText)
                .font(.system(size: 12))
                .foregroundColor(Color.Aurora.textSecondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Color.Aurora.warning)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    @ViewBuilder
    private var scheduleEditor: some View {
        switch draft.scheduleType {
        case .once:
            DatePicker("Run at", selection: $draft.onceAt)
        case .interval:
            TextField("Interval seconds (>=60)", value: $draft.intervalSeconds, format: .number)
                .textFieldStyle(.roundedBorder)
        case .daily:
            DatePicker("Time", selection: $draft.dailyTime, displayedComponents: .hourAndMinute)
        case .weekly:
            HStack {
                Picker("Weekday", selection: $draft.weeklyWeekday) {
                    ForEach(1 ... 7, id: \.self) { day in
                        Text(weekdayName(day)).tag(day)
                    }
                }
                .frame(width: 180)
                DatePicker("Time", selection: $draft.weeklyTime, displayedComponents: .hourAndMinute)
            }
        case .cron:
            TextField("Cron (m h dom mon dow)", text: $draft.cronExpression)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var previewText: String {
        do {
            let payload = try draft.payloadString()
            let temporaryTask = ScheduledTask(
                name: draft.name.ifBlank("Preview"),
                prompt: draft.prompt.ifBlank("Preview"),
                scheduleType: draft.scheduleType,
                schedulePayload: payload,
                timezoneIdentifier: draft.timezoneIdentifier,
                isEnabled: draft.isEnabled,
                projectPath: draft.projectPath.nilIfBlank,
                agent: draft.agent.nilIfBlank,
                createdAt: Date(),
                updatedAt: Date(),
                lastRunAt: draft.lastRunAt
            )
            if let next = try NextRunCalculator.nextRun(for: temporaryTask, from: Date()) {
                return "Next run: \(next.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Next run: not available"
        } catch {
            return "Next run: \(error.localizedDescription)"
        }
    }

    private func save() {
        errorMessage = nil
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Task name is required."
            return
        }
        guard !draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Prompt is required."
            return
        }
        if draft.scheduleType == .interval, draft.intervalSeconds < 60 {
            errorMessage = "Interval must be at least 60 seconds."
            return
        }
        do {
            _ = try draft.payloadString()
            onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func weekdayName(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        let names = formatter.weekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return names[max(0, min(weekday - 1, names.count - 1))]
    }
}

private struct ScheduledTaskDraft {
    var name: String
    var prompt: String
    var scheduleType: ScheduledTaskScheduleType
    var timezoneIdentifier: String
    var isEnabled: Bool
    var projectPath: String
    var agent: String
    var lastRunAt: Date?

    var onceAt: Date
    var intervalSeconds: Int
    var dailyTime: Date
    var weeklyWeekday: Int
    var weeklyTime: Date
    var cronExpression: String

    init(defaultProjectPath: String) {
        let now = Date()
        name = ""
        prompt = ""
        scheduleType = .once
        timezoneIdentifier = TimeZone.current.identifier
        isEnabled = true
        projectPath = defaultProjectPath
        agent = ""
        lastRunAt = nil
        onceAt = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        intervalSeconds = 3600
        dailyTime = now
        weeklyWeekday = Calendar.current.component(.weekday, from: now)
        weeklyTime = now
        cronExpression = "0 9 * * 1-5"
    }

    init(task: ScheduledTask) {
        name = task.name
        prompt = task.prompt
        scheduleType = task.scheduleKind
        timezoneIdentifier = task.timezoneIdentifier
        isEnabled = task.isEnabled
        projectPath = task.projectPath ?? ""
        agent = task.agent ?? ""
        lastRunAt = task.lastRunAt

        let now = Date()
        onceAt = task.nextRunAt ?? now
        intervalSeconds = 3600
        dailyTime = now
        weeklyWeekday = Calendar.current.component(.weekday, from: now)
        weeklyTime = now
        cronExpression = "0 9 * * 1-5"

        switch task.scheduleKind {
        case .once:
            if let payload = try? ScheduleRuleParser.decode(task.schedulePayload, as: OnceSchedulePayload.self) {
                onceAt = payload.runAt
            }
        case .interval:
            if let payload = try? ScheduleRuleParser.decode(task.schedulePayload, as: IntervalSchedulePayload.self) {
                intervalSeconds = payload.intervalSeconds
            }
        case .daily:
            if let payload = try? ScheduleRuleParser.decode(task.schedulePayload, as: DailySchedulePayload.self) {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
                components.hour = payload.hour
                components.minute = payload.minute
                dailyTime = Calendar.current.date(from: components) ?? now
            }
        case .weekly:
            if let payload = try? ScheduleRuleParser.decode(task.schedulePayload, as: WeeklySchedulePayload.self) {
                weeklyWeekday = payload.weekday
                var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
                components.hour = payload.hour
                components.minute = payload.minute
                weeklyTime = Calendar.current.date(from: components) ?? now
            }
        case .cron:
            if let payload = try? ScheduleRuleParser.decode(task.schedulePayload, as: CronSchedulePayload.self) {
                cronExpression = payload.expression
            }
        }
    }

    func payloadString() throws -> String {
        switch scheduleType {
        case .once:
            return try ScheduleRuleParser.encode(OnceSchedulePayload(runAt: onceAt))
        case .interval:
            return try ScheduleRuleParser.encode(IntervalSchedulePayload(intervalSeconds: intervalSeconds))
        case .daily:
            let c = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
            return try ScheduleRuleParser.encode(DailySchedulePayload(hour: c.hour ?? 0, minute: c.minute ?? 0))
        case .weekly:
            let c = Calendar.current.dateComponents([.hour, .minute], from: weeklyTime)
            return try ScheduleRuleParser.encode(
                WeeklySchedulePayload(
                    weekday: weeklyWeekday,
                    hour: c.hour ?? 0,
                    minute: c.minute ?? 0
                )
            )
        case .cron:
            return try ScheduleRuleParser.encode(CronSchedulePayload(expression: cronExpression))
        }
    }
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }

    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
