//
//  SkillTypes.swift
//  Motive
//
//  Core data models for OpenClaw-style skills.
//

import Foundation

enum SkillSource: String, Codable {
    case bundled
    case managed
    case workspace
    case extra
}

struct SkillFrontmatter: Codable, Equatable {
    var name: String = ""
    var description: String = ""
    var metadataRaw: String?
    var disableModelInvocation: Bool = false
    var userInvocable: Bool = true
}

struct SkillRequirements: Codable, Equatable {
    var bins: [String] = []
    var anyBins: [String] = []
    var env: [String] = []
    var config: [String] = []
}

struct SkillMetadata: Codable, Equatable {
    var always: Bool = false
    var os: [String] = []
    var primaryEnv: String?
    var emoji: String?
    var homepage: String?
    var requires: SkillRequirements?
    var skillKey: String?
}

struct SkillInvocationPolicy: Codable, Equatable {
    var disableModelInvocation: Bool = false
    var userInvocable: Bool = true
}

enum SkillWiring: Equatable {
    case mcp(SkillMcpSpec)
    case bin(SkillToolSpec)
    case none
}

struct SkillMcpSpec: Codable, Equatable {
    var type: String?
    var command: [String]
    var environment: [String: String] = [:]
    var timeoutMs: Int?
    var enabled: Bool?
}

struct SkillToolSpec: Codable, Equatable {
    var command: String
    var args: [String] = []
}

struct SkillEligibility: Equatable {
    var isEligible: Bool
    var reasons: [String]
}

struct SkillEntry: Equatable, Identifiable {
    var id: String { name }
    var name: String
    var description: String
    var filePath: String
    var source: SkillSource
    var frontmatter: SkillFrontmatter
    var metadata: SkillMetadata?
    var invocation: SkillInvocationPolicy
    var wiring: SkillWiring
    var eligibility: SkillEligibility
}

// MARK: - Config

struct SkillsConfig: Codable, Equatable {
    var load: SkillsLoadConfig = .init()
    var allowBundled: [String] = []
    var entries: [String: SkillEntryConfig] = [:]
}

struct SkillsLoadConfig: Codable, Equatable {
    var extraDirs: [String] = []
    var watch: Bool = true
    var watchDebounceMs: Int = 250
}

struct SkillEntryConfig: Codable, Equatable {
    var enabled: Bool?
    var env: [String: String] = [:]
    var apiKey: String?
    var config: [String: String] = [:]
}
