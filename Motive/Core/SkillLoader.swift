//
//  SkillLoader.swift
//  Motive
//
//  Loads skill folders from disk and parses SKILL.md metadata.
//

import Foundation

enum SkillLoader {
    static func loadEntries(from directory: URL, source: SkillSource) -> [SkillEntry] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        guard let subdirs = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return subdirs.compactMap { dir -> SkillEntry? in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }
            return loadSkill(from: dir, source: source)
        }
    }

    static func mergeByPrecedence(
        extra: [SkillEntry],
        bundled: [SkillEntry],
        managed: [SkillEntry],
        workspace: [SkillEntry]
    ) -> [SkillEntry] {
        var merged: [String: SkillEntry] = [:]
        for entry in extra {
            merged[entry.name] = entry
        }
        for entry in bundled {
            merged[entry.name] = entry
        }
        for entry in managed {
            merged[entry.name] = entry
        }
        for entry in workspace {
            merged[entry.name] = entry
        }
        return Array(merged.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Internals

    private static func loadSkill(from directory: URL, source: SkillSource) -> SkillEntry? {
        let skillMd = directory.appendingPathComponent("SKILL.md")
        guard FileManager.default.fileExists(atPath: skillMd.path),
              let content = try? String(contentsOf: skillMd, encoding: .utf8) else {
            return nil
        }

        let (frontmatter, _) = parseFrontmatter(content)
        guard !frontmatter.name.isEmpty else {
            return nil
        }

        let metadata = parseMetadata(from: frontmatter.metadataRaw)
        let invocation = SkillInvocationPolicy(
            disableModelInvocation: frontmatter.disableModelInvocation,
            userInvocable: frontmatter.userInvocable
        )

        let wiring = resolveWiring(in: directory)
        let eligibility = SkillEligibility(isEligible: true, reasons: [])

        return SkillEntry(
            name: frontmatter.name,
            description: frontmatter.description,
            filePath: skillMd.path,
            source: source,
            frontmatter: frontmatter,
            metadata: metadata,
            invocation: invocation,
            wiring: wiring,
            eligibility: eligibility
        )
    }

    private static func resolveWiring(in directory: URL) -> SkillWiring {
        let mcpPath = directory.appendingPathComponent("mcp.json")
        if let mcpSpec = readMcpSpec(from: mcpPath, baseDir: directory) {
            return .mcp(mcpSpec)
        }

        let toolPath = directory.appendingPathComponent("tool.json")
        if let toolSpec = readToolSpec(from: toolPath, baseDir: directory) {
            return .bin(toolSpec)
        }

        return .none
    }

    private static func readMcpSpec(from url: URL, baseDir: URL) -> SkillMcpSpec? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              var spec = try? JSONDecoder().decode(SkillMcpSpec.self, from: data) else {
            return nil
        }
        spec.command = spec.command.map { resolveBaseDir($0, baseDir: baseDir) }
        var updatedEnv: [String: String] = [:]
        for (key, value) in spec.environment {
            updatedEnv[key] = resolveBaseDir(value, baseDir: baseDir)
        }
        spec.environment = updatedEnv
        return spec
    }

    private static func readToolSpec(from url: URL, baseDir: URL) -> SkillToolSpec? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              var spec = try? JSONDecoder().decode(SkillToolSpec.self, from: data) else {
            return nil
        }
        spec.command = resolveBaseDir(spec.command, baseDir: baseDir)
        spec.args = spec.args.map { resolveBaseDir($0, baseDir: baseDir) }
        return spec
    }

    private static func resolveBaseDir(_ value: String, baseDir: URL) -> String {
        value.replacingOccurrences(of: "{baseDir}", with: baseDir.path)
    }

    private static func parseFrontmatter(_ content: String) -> (SkillFrontmatter, String) {
        var frontmatter = SkillFrontmatter()
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return (frontmatter, content)
        }

        var frontmatterLines: [Substring] = []
        var bodyStartIndex = 0
        for (index, line) in lines.enumerated() {
            if index == 0 { continue }
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                bodyStartIndex = index + 1
                break
            }
            frontmatterLines.append(line)
        }

        for line in frontmatterLines {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "name":
                frontmatter.name = value
            case "description":
                frontmatter.description = value
            case "metadata":
                frontmatter.metadataRaw = value
            case "disable-model-invocation":
                frontmatter.disableModelInvocation = parseBool(value)
            case "user-invocable":
                frontmatter.userInvocable = parseBool(value, defaultValue: true)
            default:
                break
            }
        }

        let bodyLines = lines.dropFirst(bodyStartIndex)
        let body = bodyLines.joined(separator: "\n")
        return (frontmatter, body)
    }

    private static func parseMetadata(from raw: String?) -> SkillMetadata? {
        guard let raw else { return nil }
        guard let object = JSON5Parser.parseObject(raw) else { return nil }

        let metadataObject: [String: Any]
        if let openclaw = object["openclaw"] as? [String: Any] {
            metadataObject = openclaw
        } else if let motive = object["motive"] as? [String: Any] {
            metadataObject = motive
        } else {
            metadataObject = object
        }

        var metadata = SkillMetadata()
        metadata.always = (metadataObject["always"] as? Bool) ?? false
        metadata.os = parseStringList(metadataObject["os"])
        metadata.primaryEnv = metadataObject["primaryEnv"] as? String
        metadata.emoji = metadataObject["emoji"] as? String
        metadata.homepage = metadataObject["homepage"] as? String
        metadata.skillKey = metadataObject["skillKey"] as? String

        if let requires = metadataObject["requires"] as? [String: Any] {
            var req = SkillRequirements()
            req.bins = parseStringList(requires["bins"])
            req.anyBins = parseStringList(requires["anyBins"])
            req.env = parseStringList(requires["env"])
            req.config = parseStringList(requires["config"])
            metadata.requires = req
        }

        return metadata
    }

    private static func parseStringList(_ value: Any?) -> [String] {
        if let list = value as? [String] {
            return list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let value = value as? String {
            return value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    private static func parseBool(_ value: String, defaultValue: Bool = false) -> Bool {
        switch value.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return defaultValue
        }
    }
}
