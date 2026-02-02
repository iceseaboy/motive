import Foundation
import Testing
@testable import Motive

struct McpScriptManagerTests {
    @Test func copiesScriptsFromSourceDirectory() async throws {
        try withTempDirectory { sourceDir in
            let skillsDir = sourceDir.appendingPathComponent("skills")
            let filePermissionDir = skillsDir.appendingPathComponent("file-permission")
            let askUserDir = skillsDir.appendingPathComponent("ask-user-question")
            try FileManager.default.createDirectory(at: filePermissionDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: askUserDir, withIntermediateDirectories: true)
            
            let filePermissionSource = filePermissionDir.appendingPathComponent("file-permission.js")
            let askUserSource = askUserDir.appendingPathComponent("ask-user-question.js")
            try "console.log('file-permission');".write(to: filePermissionSource, atomically: true, encoding: .utf8)
            try "console.log('ask-user-question');".write(to: askUserSource, atomically: true, encoding: .utf8)
            
            try withTempDirectory { targetDir in
                let result = McpScriptManager.ensureScripts(in: targetDir, sourceDirectory: skillsDir)
                #expect(result != nil)
                
                let filePermissionPath = targetDir.appendingPathComponent("file-permission.js")
                let askUserPath = targetDir.appendingPathComponent("ask-user-question.js")
                #expect(FileManager.default.fileExists(atPath: filePermissionPath.path))
                #expect(FileManager.default.fileExists(atPath: askUserPath.path))
                
                let filePermissionContent = try String(contentsOf: filePermissionPath, encoding: .utf8)
                let askUserContent = try String(contentsOf: askUserPath, encoding: .utf8)
                #expect(filePermissionContent.contains("file-permission"))
                #expect(askUserContent.contains("ask-user-question"))
            }
        }
    }
}

private func withTempDirectory(_ body: (URL) throws -> Void) throws {
    let base = URL(fileURLWithPath: NSTemporaryDirectory())
    let dir = base.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}
