//
//  SkillRegistry.swift
//  Motive
//
//  Central registry for OpenClaw-style skills.
//

import Combine
import Foundation

@MainActor
final class SkillRegistry: ObservableObject {
    static let shared = SkillRegistry()

    @Published private(set) var entries: [SkillEntry] = []
    @Published private(set) var snapshotVersion: Int = 0

    private weak var configManager: ConfigManager?
    private var watcher: SkillWatcher?

    private init() {}

    func setConfigManager(_ manager: ConfigManager) {
        configManager = manager
        refresh()
        configureWatcher()
    }

    func refresh() {
        guard let configManager else { return }
        if !configManager.skillsSystemEnabled {
            entries = []
            return
        }

        let config = configManager.skillsConfig
        let extraDirs = config.load.extraDirs.map { SkillRegistry.resolveUserPath($0) }
        let managedDir = configManager.skillsManagedDirectoryURL
        let workspaceDir = configManager.currentProjectURL.appendingPathComponent("skills")
        let builtIns = buildBuiltInEntries(managedDir: managedDir)

        let extraEntries = extraDirs.flatMap { SkillLoader.loadEntries(from: $0, source: .extra) }
        let managedEntriesAll = managedDir.map { SkillLoader.loadEntries(from: $0, source: .managed) } ?? []
        let builtInNames = Set(builtIns.map { $0.name })
        let managedEntries = managedEntriesAll.filter { !builtInNames.contains($0.name) }
        let workspaceEntries = SkillLoader.loadEntries(from: workspaceDir, source: .workspace)

        let merged = SkillLoader.mergeByPrecedence(
            extra: extraEntries,
            bundled: builtIns,
            managed: managedEntries,
            workspace: workspaceEntries
        )

        let evaluated = merged.map { entry in
            var updated = entry
            updated.eligibility = SkillGating.evaluate(entry: entry, config: config)
            return updated
        }

        entries = evaluated
        bumpSnapshot(reason: "refresh")
        configureWatcher()
    }

    #if DEBUG
    func setEntriesForTesting(_ entries: [SkillEntry]) {
        self.entries = entries
    }
    #endif

    func eligibleEntries() -> [SkillEntry] {
        entries.filter { $0.eligibility.isEligible }
    }

    func promptEntries() -> [SkillEntry] {
        eligibleEntries().filter { entry in
            isSkillEnabled(entry) && !shouldExcludeFromPrompt(entry) && !isSystemToolEntry(entry)
        }
    }

    /// Check if a skill is enabled using the same logic as the permission whitelist:
    /// 1. User explicit config > 2. metadata.defaultEnabled > 3. false
    func isSkillEnabled(_ entry: SkillEntry) -> Bool {
        guard let configManager else { return entry.metadata?.defaultEnabled ?? false }
        let config = configManager.skillsConfig
        let skillKey = entry.metadata?.skillKey ?? entry.name
        let entryConfig = config.entries[skillKey] ?? config.entries[entry.name]
        if let explicitEnabled = entryConfig?.enabled {
            return explicitEnabled
        }
        return entry.metadata?.defaultEnabled ?? false
    }
    
    /// Internal configuration: which skills should NOT appear in the prompt
    private func shouldExcludeFromPrompt(_ entry: SkillEntry) -> Bool {
        let excludedSkills: Set<String> = [
            "browser-automation",   // Capability (external binary)
        ]
        return excludedSkills.contains(entry.name)
    }

    func mcpEntries() -> [SkillEntry] {
        eligibleEntries().filter {
            if case .mcp(let spec) = $0.wiring {
                return spec.enabled ?? true
            }
            return false
        }
    }

    func environmentOverrides() -> [String: String] {
        guard let configManager else { return [:] }
        let config = configManager.skillsConfig
        var overrides: [String: String] = [:]
        for entry in eligibleEntries() {
            let key = SkillGating.resolveSkillKey(entry)
            let entryConfig = config.entries[key] ?? config.entries[entry.name]
            if let entryConfig {
                for (envKey, value) in entryConfig.env where !value.isEmpty {
                    overrides[envKey] = value
                }
                if let apiKey = entryConfig.apiKey,
                   !apiKey.isEmpty,
                   let primaryEnv = entry.metadata?.primaryEnv,
                   overrides[primaryEnv]?.isEmpty ?? true {
                    overrides[primaryEnv] = apiKey
                }
            }
        }
        return overrides
    }

    func buildMcpConfigEntries() -> [String: Any] {
        var mcp: [String: Any] = [:]
        for entry in mcpEntries() {
            guard case .mcp(let spec) = entry.wiring else { continue }
            let key = entry.name
            mcp[key] = [
                "type": spec.type ?? "local",
                "command": spec.command,
                "enabled": spec.enabled ?? true,
                "environment": spec.environment,
                "timeout": spec.timeoutMs ?? 10000
            ]
        }
        return mcp
    }

    // MARK: - Private

    private func buildBuiltInEntries(managedDir: URL?) -> [SkillEntry] {
        var entries: [SkillEntry] = []
        if let bundleURL = bundledSkillsURL() {
            entries.append(contentsOf: SkillLoader.loadEntries(from: bundleURL, source: .bundled))
        }
        let bundledNames = Set(entries.map { $0.name })

        let builtIns = SkillManager.shared.skills.filter { !bundledNames.contains($0.id) }
        let skillEntries = builtIns.map { skill in
            let skillPath: String
            if let managedDir {
                skillPath = managedDir
                    .appendingPathComponent(skill.id)
                    .appendingPathComponent("SKILL.md")
                    .path
            } else {
                skillPath = skill.id
            }
            let frontmatter = SkillFrontmatter(
                name: skill.id,
                description: skill.description,
                metadataRaw: nil
            )
            // System skills are enabled by default
            var metadata = SkillMetadata()
            metadata.defaultEnabled = true
            
            return SkillEntry(
                name: skill.id,
                description: skill.description,
                filePath: skillPath,
                source: .bundled,
                frontmatter: frontmatter,
                metadata: metadata,
                wiring: .none,
                eligibility: SkillEligibility(isEligible: true, reasons: [])
            )
        }
        entries.append(contentsOf: skillEntries)
        return entries
    }

    private func configureWatcher() {
        guard let configManager else { return }
        let config = configManager.skillsConfig
        if !config.load.watch || !configManager.skillsSystemEnabled {
            watcher?.stop()
            watcher = nil
            return
        }

        let debounceMs = config.load.watchDebounceMs
        let paths = watchPaths(configManager: configManager, config: config)
        if watcher == nil {
            watcher = SkillWatcher(debounceMs: debounceMs) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        }
        watcher?.startWatching(paths: paths)
    }

    private func watchPaths(configManager: ConfigManager, config: SkillsConfig) -> [String] {
        var paths: [String] = []
        let workspace = configManager.currentProjectURL.appendingPathComponent("skills").path
        paths.append(workspace)
        if let managedDir = configManager.skillsManagedDirectoryURL?.path {
            paths.append(managedDir)
        }
        let extra = config.load.extraDirs.map { SkillRegistry.resolveUserPath($0).path }
        paths.append(contentsOf: extra)
        return paths
    }

    private func bumpSnapshot(reason: String) {
        snapshotVersion = Int(Date().timeIntervalSince1970 * 1000)
        Log.debug("Skills snapshot updated (\(reason)) -> \(snapshotVersion)")
    }

    private func isSystemToolEntry(_ entry: SkillEntry) -> Bool {
        return false
    }

    private static func resolveUserPath(_ path: String) -> URL {
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let expanded = home + path.dropFirst()
            return URL(fileURLWithPath: expanded)
        }
        return URL(fileURLWithPath: path)
    }

    private func bundledSkillsURL() -> URL? {
        #if DEBUG
        if let override = bundledSkillsURLOverride {
            return override
        }
        #endif
        guard let bundleURL = Bundle.main.url(forResource: "Skills", withExtension: "bundle"),
              let bundle = Bundle(url: bundleURL) else {
            return nil
        }
        return bundle.resourceURL
    }

    #if DEBUG
    private var bundledSkillsURLOverride: URL? {
        get { Self._bundledSkillsURLOverride }
        set { Self._bundledSkillsURLOverride = newValue }
    }
    private static var _bundledSkillsURLOverride: URL?

    func setBundledSkillsURLForTesting(_ url: URL?) {
        bundledSkillsURLOverride = url
    }
    #endif
}
