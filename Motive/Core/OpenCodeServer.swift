//
//  OpenCodeServer.swift
//  Motive
//
//  Manages the persistent `opencode serve` background process.
//  Uses Foundation Process directly (no PTY needed for HTTP server).
//

import Foundation
import os

/// Manages the `opencode serve` HTTP server process lifecycle.
///
/// Responsibilities:
/// - Spawn `opencode serve --port 0` via Foundation Process
/// - Parse stdout for the actual port ("listening on http://...")
/// - Health check via HTTP GET
/// - Auto-restart on crash with exponential backoff (max 3 retries)
/// - Graceful shutdown: SIGTERM -> wait 2s -> SIGKILL
/// - Notify via `onRestart` when the server restarts on a new URL
actor OpenCodeServer {

    // MARK: - Types

    struct Configuration: Sendable {
        let binaryURL: URL
        let environment: [String: String]
        let workingDirectory: String
    }

    enum ServerError: Error, LocalizedError {
        case notConfigured
        case startFailed(String)
        case portDetectionTimeout
        case maxRetriesExceeded(attempts: Int)
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Server not configured"
            case .startFailed(let reason):
                return "Failed to start OpenCode server: \(reason)"
            case .portDetectionTimeout:
                return "Timed out waiting for server to report its port"
            case .maxRetriesExceeded(let attempts):
                return "Server failed to start after \(attempts) attempts"
            case .alreadyRunning:
                return "Server is already running"
            }
        }
    }

    private enum State: Sendable {
        case stopped
        case starting
        case running(URL)
        case crashed
    }

    // MARK: - Properties

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var state: State = .stopped
    private var monitorTask: Task<Void, Never>?
    private var stdoutDrainTask: Task<Void, Never>?
    private var stderrDrainTask: Task<Void, Never>?
    private var restartCount: Int = 0
    private static let maxRestartAttempts = MotiveConstants.Limits.maxServerRestartAttempts
    private static let portDetectionTimeoutSeconds: TimeInterval = MotiveConstants.Timeouts.portDetection
    private static let gracefulShutdownSeconds: TimeInterval = MotiveConstants.Timeouts.gracefulShutdown

    /// Called when the server restarts on a new URL after a crash.
    /// The Bridge uses this to update SSE and API client URLs.
    private var onRestart: (@Sendable (URL) async -> Void)?

    private let logger = Logger(subsystem: "com.velvet.motive", category: "OpenCodeServer")

    /// The URL of the running server, if available.
    var serverURL: URL? {
        if case .running(let url) = state {
            return url
        }
        return nil
    }

    /// Whether the server process is currently running.
    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    // MARK: - Lifecycle

    /// Set a handler that fires when the server restarts on a new URL.
    func setRestartHandler(_ handler: @escaping @Sendable (URL) async -> Void) {
        self.onRestart = handler
    }

    /// Start the server and return the base URL once it's ready.
    ///
    /// - Parameter configuration: Binary path, environment, and working directory.
    /// - Returns: The base URL of the running server.
    /// - Throws: `ServerError` if the server fails to start.
    func start(configuration: Configuration) async throws -> URL {
        if case .running(let url) = state {
            logger.info("Server already running at \(url.absoluteString)")
            return url
        }

        state = .starting
        restartCount = 0

        let url = try await spawnAndDetectPort(configuration: configuration)
        state = .running(url)

        // Monitor the process for unexpected termination
        startMonitor(configuration: configuration)

        logger.info("OpenCode server started at \(url.absoluteString)")
        return url
    }

    /// Stop the server gracefully.
    func stop() async {
        monitorTask?.cancel()
        monitorTask = nil
        stdoutDrainTask?.cancel()
        stdoutDrainTask = nil
        stderrDrainTask?.cancel()
        stderrDrainTask = nil

        guard let process else {
            state = .stopped
            return
        }

        logger.info("Stopping OpenCode server (PID: \(process.processIdentifier))...")

        // SIGTERM first
        process.terminate()

        // Wait for graceful shutdown (poll instead of blocking)
        let deadline = Date().addingTimeInterval(Self.gracefulShutdownSeconds)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(MotiveConstants.Timeouts.serverStartupPoll * 1_000_000_000))
        }

        // Force kill if still running
        if process.isRunning {
            logger.warning("Server did not stop gracefully, sending SIGKILL")
            kill(process.processIdentifier, SIGKILL)
        }

        self.process = nil
        self.stdoutPipe = nil
        state = .stopped
        restartCount = 0
        logger.info("OpenCode server stopped")
    }

    /// Check if the server is healthy by making a simple HTTP request.
    func isHealthy() async -> Bool {
        guard let url = serverURL else { return false }

        let healthURL = url.appendingPathComponent("session")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...499).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Internal

    /// Spawn the process and wait for the port to appear in stdout.
    private func spawnAndDetectPort(configuration: Configuration) async throws -> URL {
        let proc = Process()
        proc.executableURL = configuration.binaryURL
        proc.arguments = ["serve", "--port", "0", "--hostname", "127.0.0.1"]
        proc.currentDirectoryURL = URL(fileURLWithPath: configuration.workingDirectory)

        // Set environment
        var env = ProcessInfo.processInfo.environment
        for (key, value) in configuration.environment {
            env[key] = value
        }
        if env["TERM"] == nil {
            env["TERM"] = "dumb"
        }
        proc.environment = env

        // Create pipes for stdout (stderr logged via separate pipe for diagnostics)
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            throw ServerError.startFailed(error.localizedDescription)
        }

        self.process = proc
        self.stdoutPipe = pipe
        logger.info("Spawned opencode serve (PID: \(proc.processIdentifier)) binary: \(configuration.binaryURL.path)")

        // Read lines until we find the port announcement
        return try await detectPort(from: pipe.fileHandleForReading)
    }

    /// Read stdout lines looking for the "listening on http://..." message.
    /// After finding the port, continues draining stdout in the background
    /// to prevent the pipe buffer from filling and blocking the child process.
    private func detectPort(from fileHandle: FileHandle) async throws -> URL {
        let lines = fileHandle.bytes.lines
        let deadline = Date().addingTimeInterval(Self.portDetectionTimeoutSeconds)

        var iterator = lines.makeAsyncIterator()

        do {
            while let line = try await iterator.next() {
                guard Date() < deadline else {
                    throw ServerError.portDetectionTimeout
                }

                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                logger.debug("Server output: \(trimmed)")

                // Look for the listening announcement
                if let url = parseListeningURL(from: trimmed) {
                    // Continue draining stdout in the background
                    startStdoutDrain(fileHandle: fileHandle)
                    return url
                }
            }
        } catch let error as ServerError {
            throw error
        } catch {
            if !Task.isCancelled {
                throw ServerError.startFailed("Stdout stream ended: \(error.localizedDescription)")
            }
        }

        throw ServerError.portDetectionTimeout
    }

    /// Continuously drain stdout to prevent buffer fill-up.
    /// Uses Task.detached to avoid competing with actor-isolated work.
    private func startStdoutDrain(fileHandle: FileHandle) {
        stdoutDrainTask?.cancel()
        let log = self.logger
        stdoutDrainTask = Task.detached {
            do {
                let lines = fileHandle.bytes.lines
                for try await line in lines {
                    guard !Task.isCancelled else { break }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        log.debug("Server output: \(trimmed)")
                    }
                }
            } catch {
                if !Task.isCancelled {
                    log.debug("Server stdout drain ended: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Continuously drain stderr and log for diagnostics.
    /// Uses Task.detached to avoid competing with detectPort for actor execution.
    private func startStderrDrain(fileHandle: FileHandle) {
        stderrDrainTask?.cancel()
        let log = self.logger
        stderrDrainTask = Task.detached {
            do {
                let lines = fileHandle.bytes.lines
                for try await line in lines {
                    guard !Task.isCancelled else { break }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        log.warning("Server stderr: \(trimmed)")
                    }
                }
            } catch {
                if !Task.isCancelled {
                    log.debug("Server stderr drain ended: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Parse a URL from a line like "listening on http://127.0.0.1:4096"
    func parseListeningURL(from line: String) -> URL? {
        let lowered = line.lowercased()
        guard lowered.contains("listening") else { return nil }

        let patterns = ["http://127.0.0.1:", "http://localhost:", "http://0.0.0.0:"]
        for pattern in patterns {
            guard let range = line.range(of: pattern, options: .caseInsensitive) else { continue }
            let afterPattern = line[range.upperBound...]
            let portString = afterPattern.prefix(while: { $0.isNumber })
            guard let port = Int(portString), port > 0 else { continue }
            return URL(string: "http://127.0.0.1:\(port)")
        }

        return nil
    }

    /// Monitor the server process and auto-restart on crash.
    private func startMonitor(configuration: Configuration) {
        monitorTask?.cancel()
        let log = self.logger
        monitorTask = Task { [weak self] in
            guard let self else { return }

            // Poll isRunning instead of blocking
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(MotiveConstants.Timeouts.serverHealthCheck * 1_000_000_000))
                guard !Task.isCancelled else { return }

                guard let process = await self.process else { return }
                if !process.isRunning {
                    guard !Task.isCancelled else { return }
                    let exitCode = process.terminationStatus
                    log.error("OpenCode server exited unexpectedly (code: \(exitCode))")
                    await self.handleCrash(configuration: configuration)
                    return
                }
            }
        }
    }

    /// Handle a server crash with exponential backoff restart.
    private func handleCrash(configuration: Configuration) async {
        stdoutDrainTask?.cancel()
        stdoutDrainTask = nil
        stderrDrainTask?.cancel()
        stderrDrainTask = nil
        process = nil
        stdoutPipe = nil
        state = .crashed

        restartCount += 1
        guard restartCount <= Self.maxRestartAttempts else {
            logger.error("Max restart attempts (\(Self.maxRestartAttempts)) exceeded, giving up")
            return
        }

        let delay = pow(2.0, Double(restartCount - 1)) // 1s, 2s, 4s
        logger.info("Restarting server in \(delay)s (attempt \(self.restartCount)/\(Self.maxRestartAttempts))...")

        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }

            let url = try await spawnAndDetectPort(configuration: configuration)
            state = .running(url)
            startMonitor(configuration: configuration)
            logger.info("Server restarted successfully at \(url.absoluteString)")

            // Notify the bridge so it can reconnect SSE and update API client
            await onRestart?(url)
        } catch {
            logger.error("Server restart failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Protocol Conformance

extension OpenCodeServer: OpenCodeServerProtocol {}
