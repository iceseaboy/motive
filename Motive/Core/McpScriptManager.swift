//
//  McpScriptManager.swift
//  Motive
//
//  Extracted MCP script generation from ConfigManager.
//

import Foundation

enum McpScriptManager {
    static func ensureScripts(in directory: URL) -> (filePermission: String, askUserQuestion: String)? {
        ensureScripts(in: directory, sourceDirectory: nil)
    }

    static func ensureScripts(in directory: URL, sourceDirectory: URL?) -> (filePermission: String, askUserQuestion: String)? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Log.config(" Failed to create MCP scripts directory: \(error)")
            return nil
        }
        
        let sourceRoot = sourceDirectory ?? bundledSkillsRootURL()
        guard let sourceRoot else {
            Log.config(" MCP script source directory missing")
            return nil
        }
        
        let filePermissionSource = sourceRoot
            .appendingPathComponent("file-permission")
            .appendingPathComponent("file-permission.js")
        let askUserSource = sourceRoot
            .appendingPathComponent("ask-user-question")
            .appendingPathComponent("ask-user-question.js")
        
        guard FileManager.default.fileExists(atPath: filePermissionSource.path),
              FileManager.default.fileExists(atPath: askUserSource.path) else {
            Log.config(" MCP script source files not found in \(sourceRoot.path)")
            return nil
        }
        
        let filePermissionPath = directory.appendingPathComponent("file-permission.js")
        let askUserPath = directory.appendingPathComponent("ask-user-question.js")
        
        do {
            if FileManager.default.fileExists(atPath: filePermissionPath.path) {
                try FileManager.default.removeItem(at: filePermissionPath)
            }
            if FileManager.default.fileExists(atPath: askUserPath.path) {
                try FileManager.default.removeItem(at: askUserPath)
            }
            try FileManager.default.copyItem(at: filePermissionSource, to: filePermissionPath)
            try FileManager.default.copyItem(at: askUserSource, to: askUserPath)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: filePermissionPath.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: askUserPath.path)
        } catch {
            Log.config(" Failed to copy MCP scripts: \(error)")
            return nil
        }
        
        return (filePermissionPath.path, askUserPath.path)
    }

    private static func bundledSkillsRootURL() -> URL? {
        guard let bundleURL = Bundle.main.url(forResource: "Skills", withExtension: "bundle"),
              let bundle = Bundle(url: bundleURL) else {
            return nil
        }
        return bundle.resourceURL
    }
}
