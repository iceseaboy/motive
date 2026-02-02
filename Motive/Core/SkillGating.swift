//
//  SkillGating.swift
//  Motive
//
//  OpenClaw-style gating rules for skills.
//

import Foundation

enum SkillGating {
    static func evaluate(
        entry: SkillEntry,
        config: SkillsConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        platform: String = SkillPlatform.current
    ) -> SkillEligibility {
        var reasons: [String] = []
        let skillKey = resolveSkillKey(entry)
        let skillConfig = config.entries[skillKey] ?? config.entries[entry.name]

        if skillConfig?.enabled == false {
            reasons.append("disabled")
            return SkillEligibility(isEligible: false, reasons: reasons)
        }

        if entry.source == .bundled, !isBundledAllowed(entry: entry, config: config) {
            reasons.append("bundled_not_allowed")
            return SkillEligibility(isEligible: false, reasons: reasons)
        }

        if let osList = entry.metadata?.os, !osList.isEmpty, !osList.contains(platform) {
            reasons.append("os_mismatch")
            return SkillEligibility(isEligible: false, reasons: reasons)
        }

        if entry.metadata?.always == true {
            return SkillEligibility(isEligible: true, reasons: [])
        }

        if let requires = entry.metadata?.requires {
            if !requires.bins.isEmpty {
                for bin in requires.bins where !hasBinary(bin) {
                    reasons.append("missing_bin:\(bin)")
                }
            }

            if !requires.anyBins.isEmpty {
                let hasAny = requires.anyBins.contains { hasBinary($0) }
                if !hasAny {
                    reasons.append("missing_any_bin")
                }
            }

            if !requires.env.isEmpty {
                for envName in requires.env {
                    if environment[envName]?.isEmpty == false {
                        continue
                    }
                    if let configEnv = skillConfig?.env[envName], !configEnv.isEmpty {
                        continue
                    }
                    if let apiKey = skillConfig?.apiKey,
                       !apiKey.isEmpty,
                       entry.metadata?.primaryEnv == envName {
                        continue
                    }
                    reasons.append("missing_env:\(envName)")
                }
            }

            if !requires.config.isEmpty {
                for configPath in requires.config where !isConfigPathTruthy(configPath, entryConfig: skillConfig) {
                    reasons.append("missing_config:\(configPath)")
                }
            }
        }

        return SkillEligibility(isEligible: reasons.isEmpty, reasons: reasons)
    }

    static func resolveSkillKey(_ entry: SkillEntry) -> String {
        if let key = entry.metadata?.skillKey, !key.isEmpty {
            return key
        }
        return entry.name
    }

    private static func isBundledAllowed(entry: SkillEntry, config: SkillsConfig) -> Bool {
        let allowlist = config.allowBundled.map { $0.lowercased() }.filter { !$0.isEmpty }
        if allowlist.isEmpty {
            return true
        }
        let skillKey = resolveSkillKey(entry).lowercased()
        return allowlist.contains(skillKey) || allowlist.contains(entry.name.lowercased())
    }

    private static func hasBinary(_ bin: String) -> Bool {
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let parts = pathEnv.split(separator: ":").map(String.init).filter { !$0.isEmpty }
        for part in parts {
            let candidate = (part as NSString).appendingPathComponent(bin)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return true
            }
        }
        return false
    }

    private static func isConfigPathTruthy(_ path: String, entryConfig: SkillEntryConfig?) -> Bool {
        guard let value = entryConfig?.config[path]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return false
        }
        let lower = value.lowercased()
        return !(lower == "false" || lower == "0" || lower == "no")
    }
}

enum SkillPlatform {
    static var current: String {
        #if os(macOS)
        return "darwin"
        #elseif os(Linux)
        return "linux"
        #elseif os(Windows)
        return "win32"
        #else
        return "unknown"
        #endif
    }
}
