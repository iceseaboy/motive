//
//  SkillValidation.swift
//  Motive
//
//  Validates skill frontmatter against AgentSkills spec.
//  Produces warnings only - does not block loading.
//

import Foundation

enum SkillValidation {
    struct ValidationResult: Equatable {
        var warnings: [ValidationWarning]
        
        var hasWarnings: Bool { !warnings.isEmpty }
    }
    
    enum ValidationWarning: Equatable, CustomStringConvertible {
        case nameEmpty
        case nameNotLowercase
        case nameContainsConsecutiveHyphens
        case nameStartsWithHyphen
        case nameEndsWithHyphen
        case nameTooLong(Int)
        case nameDirectoryMismatch(expected: String, actual: String)
        case descriptionEmpty
        case descriptionTooLong(Int)
        case compatibilityTooLong(Int)
        
        var description: String {
            switch self {
            case .nameEmpty:
                return "name is empty"
            case .nameNotLowercase:
                return "name should be lowercase"
            case .nameContainsConsecutiveHyphens:
                return "name contains consecutive hyphens (--)"
            case .nameStartsWithHyphen:
                return "name should not start with hyphen"
            case .nameEndsWithHyphen:
                return "name should not end with hyphen"
            case .nameTooLong(let length):
                return "name is too long (\(length) chars, max 64)"
            case .nameDirectoryMismatch(let expected, let actual):
                return "name '\(actual)' does not match directory '\(expected)'"
            case .descriptionEmpty:
                return "description is empty"
            case .descriptionTooLong(let length):
                return "description is too long (\(length) chars, max 1024)"
            case .compatibilityTooLong(let length):
                return "compatibility is too long (\(length) chars, max 500)"
            }
        }
    }
    
    /// Validate frontmatter against AgentSkills spec.
    /// Returns warnings only - does not block loading.
    static func validate(frontmatter: SkillFrontmatter, directoryName: String) -> ValidationResult {
        var warnings: [ValidationWarning] = []
        
        // Validate name
        let name = frontmatter.name
        if name.isEmpty {
            warnings.append(.nameEmpty)
        } else {
            if name != name.lowercased() {
                warnings.append(.nameNotLowercase)
            }
            if name.contains("--") {
                warnings.append(.nameContainsConsecutiveHyphens)
            }
            if name.hasPrefix("-") {
                warnings.append(.nameStartsWithHyphen)
            }
            if name.hasSuffix("-") {
                warnings.append(.nameEndsWithHyphen)
            }
            if name.count > 64 {
                warnings.append(.nameTooLong(name.count))
            }
            if name != directoryName {
                warnings.append(.nameDirectoryMismatch(expected: directoryName, actual: name))
            }
        }
        
        // Validate description
        let description = frontmatter.description.trimmingCharacters(in: .whitespaces)
        if description.isEmpty {
            warnings.append(.descriptionEmpty)
        } else if description.count > 1024 {
            warnings.append(.descriptionTooLong(description.count))
        }
        
        // Validate compatibility (optional)
        if let compatibility = frontmatter.compatibility, compatibility.count > 500 {
            warnings.append(.compatibilityTooLong(compatibility.count))
        }
        
        return ValidationResult(warnings: warnings)
    }
    
    /// Validate name format only (for quick checks)
    static func validateName(_ name: String) -> [ValidationWarning] {
        var warnings: [ValidationWarning] = []
        
        if name.isEmpty {
            warnings.append(.nameEmpty)
            return warnings
        }
        
        if name != name.lowercased() {
            warnings.append(.nameNotLowercase)
        }
        if name.contains("--") {
            warnings.append(.nameContainsConsecutiveHyphens)
        }
        if name.hasPrefix("-") {
            warnings.append(.nameStartsWithHyphen)
        }
        if name.hasSuffix("-") {
            warnings.append(.nameEndsWithHyphen)
        }
        if name.count > 64 {
            warnings.append(.nameTooLong(name.count))
        }
        
        return warnings
    }
}
