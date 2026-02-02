import Foundation

@MainActor
extension ConfigManager {
    func makeEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let apiKeyValue = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove proxy environment variables to avoid SOCKS proxy errors with browser-use
        // browser-use uses httpx which doesn't have socksio installed by default
        let proxyKeys = ["ALL_PROXY", "all_proxy", "HTTP_PROXY", "http_proxy",
                         "HTTPS_PROXY", "https_proxy", "NO_PROXY", "no_proxy",
                         "SOCKS_PROXY", "socks_proxy"]
        for key in proxyKeys {
            environment.removeValue(forKey: key)
        }
        
        // Extend PATH with common Node.js installation paths
        // This is critical because /bin/sh doesn't load user's shell config
        environment["PATH"] = buildExtendedPath(base: environment["PATH"])
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        environment["FORCE_COLOR"] = "0"
        environment["CI"] = "1"
        environment["OPENCODE_NO_INTERACTIVE"] = "1"
        
        // Sync API keys to OpenCode's auth.json
        syncToOpenCodeAuth()
        
        // ALWAYS generate config (sets permission: "allow" to avoid blocking)
        generateOpenCodeConfig()
        
        if !apiKeyValue.isEmpty {
            // Also set environment variables as backup
            switch provider {
            case .claude:
                environment["ANTHROPIC_API_KEY"] = apiKeyValue
                Log.config(" Using Anthropic API key: \(apiKeyValue.prefix(10))...")
            case .openai:
                environment["OPENAI_API_KEY"] = apiKeyValue
                Log.config(" Using OpenAI API key: \(apiKeyValue.prefix(10))...")
            case .gemini:
                environment["GOOGLE_API_KEY"] = apiKeyValue
                Log.config(" Using Google API key: \(apiKeyValue.prefix(10))...")
            case .ollama:
                Log.config(" Using Ollama (no API key needed)")
            }
        } else {
            Log.config(" WARNING - No API key configured!")
        }
        
        // Note: baseURL is configured via opencode.json provider.options.baseURL
        // Environment variables are not needed as OpenCode reads from config file
        
        if debugMode {
            environment["DEBUG"] = "1"
        }

        // Inject skill-specific environment overrides (OpenClaw-style)
        if skillsSystemEnabled {
            let overrides = SkillRegistry.shared.environmentOverrides()
            for (key, value) in overrides {
                if environment[key]?.isEmpty ?? true {
                    environment[key] = value
                }
            }
        }
        
        // Set Browser Agent API key for browser-use-sidecar agent_task
        // Only use cached value to avoid triggering additional Keychain prompts
        if browserUseEnabled, let cachedKey = cachedBrowserAgentAPIKey, !cachedKey.isEmpty {
            let envKeyName = browserAgentProvider.envKeyName
            environment[envKeyName] = cachedKey
            Log.config(" Browser Agent API key (\(envKeyName)): \(cachedKey.prefix(10))...")
            
            // Set base URL if configured
            if let baseUrlEnvName = browserAgentProvider.baseUrlEnvName, !browserAgentBaseUrl.isEmpty {
                environment[baseUrlEnvName] = browserAgentBaseUrl
                Log.config(" Browser Agent Base URL (\(baseUrlEnvName)): \(browserAgentBaseUrl)")
            }
        }
        
        // Set OPENCODE_CONFIG if we generated a config file
        if !openCodeConfigPath.isEmpty {
            environment["OPENCODE_CONFIG"] = openCodeConfigPath
            Log.config(" Using OpenCode config: \(openCodeConfigPath)")
            
            // Verify the config file exists
            if FileManager.default.fileExists(atPath: openCodeConfigPath) {
                Log.config(" Config file verified at: \(openCodeConfigPath)")
            } else {
                Log.config(" WARNING - Config file NOT found at: \(openCodeConfigPath)")
            }
            
            if !openCodeConfigDir.isEmpty {
                environment["OPENCODE_CONFIG_DIR"] = openCodeConfigDir
                Log.config(" Using OpenCode config dir: \(openCodeConfigDir)")
            }
        } else {
            Log.config(" WARNING - openCodeConfigPath is empty!")
        }
        
        return environment
    }
    
    /// Build extended PATH with common Node.js installation paths
    /// This is needed because /bin/sh doesn't load user's shell config (.zshrc etc)
    func buildExtendedPath(base: String?) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        var pathParts: [String] = []
        
        // Add App Bundle Resources path for bundled binaries (browser-use-sidecar)
        if let resourcesPath = Bundle.main.resourcePath {
            pathParts.append(resourcesPath)
        }
        
        // NVM paths (dynamic - check all installed versions)
        let nvmVersionsDir = "\(homeDir)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsDir) {
            let sortedVersions = versions
                .filter { $0.hasPrefix("v") }
                .sorted { v1, v2 in
                    // Sort by version (descending - newest first)
                    let parse: (String) -> Int = { v in
                        let parts = v.dropFirst().split(separator: ".").compactMap { Int($0) }
                        let major = parts.count > 0 ? parts[0] : 0
                        let minor = parts.count > 1 ? parts[1] : 0
                        let patch = parts.count > 2 ? parts[2] : 0
                        return major * 10000 + minor * 100 + patch
                    }
                    return parse(v1) > parse(v2)
                }
            for version in sortedVersions {
                let binPath = "\(nvmVersionsDir)/\(version)/bin"
                if FileManager.default.fileExists(atPath: binPath) {
                    pathParts.append(binPath)
                }
            }
        }
        
        // Common Node.js paths
        let commonPaths = [
            "/opt/homebrew/bin",           // Apple Silicon Homebrew
            "/usr/local/bin",              // Intel Mac / general
            "\(homeDir)/.volta/bin",       // Volta
            "\(homeDir)/.asdf/shims",      // asdf
            "\(homeDir)/.fnm/current/bin", // fnm
            "\(homeDir)/.nodenv/shims",    // nodenv
            "\(homeDir)/.local/bin",       // pip/pipx style
            "/opt/local/bin",              // MacPorts
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) && !pathParts.contains(path) {
                pathParts.append(path)
            }
        }
        
        // Add system PATH from path_helper
        if let systemPath = getSystemPath() {
            for path in systemPath.split(separator: ":").map(String.init) {
                if !pathParts.contains(path) {
                    pathParts.append(path)
                }
            }
        }
        
        // Add base PATH
        if let base = base {
            for path in base.split(separator: ":").map(String.init) {
                if !pathParts.contains(path) {
                    pathParts.append(path)
                }
            }
        }
        
        let result = pathParts.joined(separator: ":")
        Log.config(" Extended PATH: \(result.prefix(200))...")
        return result
    }
    
    /// Get system PATH from macOS path_helper utility
    func getSystemPath() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/libexec/path_helper")
        task.arguments = ["-s"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Parse: PATH="..."; export PATH;
                if let match = output.range(of: #"PATH="([^"]+)""#, options: .regularExpression) {
                    let pathValue = output[match]
                        .dropFirst(6) // Remove PATH="
                        .dropLast(1)  // Remove trailing "
                    return String(pathValue)
                }
            }
        } catch {
            Log.config(" path_helper failed: \(error)")
        }
        
        return nil
    }
}
