//
//  CommandRunner.swift
//  Motive
//
//  Abstraction for executing shell commands.
//  Provides testable interface via protocol.
//

import Foundation

// MARK: - Protocol

protocol CommandRunnerProtocol: Sendable {
    func run(_ argv: [String], timeout: Int, env: [String: String]?) async -> CommandResult
    func hasBinary(_ name: String) -> Bool
}

// MARK: - Result

struct CommandResult: Sendable, Equatable {
    var stdout: String
    var stderr: String
    var exitCode: Int?
    
    var succeeded: Bool { exitCode == 0 }
}

// MARK: - Implementation

final class CommandRunner: CommandRunnerProtocol, @unchecked Sendable {
    static let shared = CommandRunner()
    
    private var binaryCache: [String: Bool] = [:]
    private let cacheLock = NSLock()
    
    private init() {}
    
    /// Clear the binary existence cache (call after installing new tools)
    func clearBinaryCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        binaryCache.removeAll()
    }
    
    func run(_ argv: [String], timeout: Int, env: [String: String]? = nil) async -> CommandResult {
        guard !argv.isEmpty else {
            return CommandResult(stdout: "", stderr: "Empty command", exitCode: 1)
        }
        
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // Set environment with extended PATH for GUI apps
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.effectivePaths().joined(separator: ":")
        if let env = env {
            for (key, value) in env {
                environment[key] = value
            }
        }
        process.environment = environment
        
        // Run with timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                    
                    // Set timeout
                    let timeoutSeconds = Double(timeout)
                    let deadline = DispatchTime.now() + timeoutSeconds
                    
                    DispatchQueue.global().asyncAfter(deadline: deadline) {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                    
                    process.waitUntilExit()
                    
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    
                    continuation.resume(returning: CommandResult(
                        stdout: stdout,
                        stderr: stderr,
                        exitCode: Int(process.terminationStatus)
                    ))
                } catch {
                    continuation.resume(returning: CommandResult(
                        stdout: "",
                        stderr: error.localizedDescription,
                        exitCode: nil
                    ))
                }
            }
        }
    }
    
    func hasBinary(_ name: String) -> Bool {
        // Check cache first
        cacheLock.lock()
        if let cached = binaryCache[name] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        // Build comprehensive PATH list
        // GUI apps don't inherit shell PATH, so we add common locations
        let paths = Self.effectivePaths()
        
        var result = false
        for path in paths {
            let fullPath = (path as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                result = true
                break
            }
        }
        
        // Cache the result
        cacheLock.lock()
        binaryCache[name] = result
        cacheLock.unlock()
        
        return result
    }
    
    /// Build effective PATH including common tool locations
    /// GUI apps don't inherit shell config, so we manually add known paths
    static func effectivePaths() -> [String] {
        var paths: [String] = []
        
        // Start with system PATH
        let systemPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        paths.append(contentsOf: systemPath.split(separator: ":").map(String.init))
        
        // Add common macOS tool locations (order matters - first match wins)
        let commonPaths = [
            // Homebrew (Apple Silicon)
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            // Homebrew (Intel)
            "/usr/local/bin",
            "/usr/local/sbin",
            // System
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            // Go
            "\(NSHomeDirectory())/go/bin",
            "/usr/local/go/bin",
            // Rust/Cargo
            "\(NSHomeDirectory())/.cargo/bin",
            // Python/pip
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/opt/python/libexec/bin",
            // Node/npm global
            "/opt/homebrew/lib/node_modules/.bin",
            "/usr/local/lib/node_modules/.bin",
            // pnpm
            "\(NSHomeDirectory())/Library/pnpm",
            // uv
            "\(NSHomeDirectory())/.local/bin",
        ]
        
        for path in commonPaths where !paths.contains(path) {
            paths.append(path)
        }
        
        return paths
    }
}

// MARK: - Mock for Testing

final class MockCommandRunner: CommandRunnerProtocol, @unchecked Sendable {
    var stubbedResults: [String: CommandResult] = [:]
    var stubbedBinaries: Set<String> = []
    var runCalls: [[String]] = []
    
    func run(_ argv: [String], timeout: Int, env: [String: String]?) async -> CommandResult {
        runCalls.append(argv)
        let key = argv.joined(separator: " ")
        return stubbedResults[key] ?? CommandResult(stdout: "", stderr: "", exitCode: 0)
    }
    
    func hasBinary(_ name: String) -> Bool {
        stubbedBinaries.contains(name)
    }
    
    func reset() {
        stubbedResults = [:]
        stubbedBinaries = []
        runCalls = []
    }
}
