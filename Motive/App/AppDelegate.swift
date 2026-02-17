//
//  AppDelegate.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var permissionCheckTask: Task<Void, Never>?
    private var hotkeyObserver: NSObjectProtocol?
    private var onboardingController: OnboardingWindowController?

    /// Parsed hotkey components from ConfigManager
    private var expectedModifiers: NSEvent.ModifierFlags = .option
    private var expectedKeyCode: UInt16 = 49 // Space key

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - we're a menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Create the status bar icon immediately — before anything else.
        // This guarantees it is visible from the very first frame, regardless
        // of whether onboarding is shown or skipped.
        appState?.ensureStatusBar()

        // Clean up any stale browser-sidecar processes from previous runs
        cleanupBrowserSidecar()

        // Apply saved appearance mode
        appState?.configManagerRef.applyAppearance()

        // Check if onboarding is needed
        if let configManager = appState?.configManagerRef, !configManager.hasCompletedOnboarding {
            showOnboarding()
            return
        }

        // Normal startup
        startNormalFlow()
    }

    /// Show onboarding window for first-time users
    private func showOnboarding() {
        guard let appState else { return }

        // Show dock icon during onboarding for better UX
        NSApp.setActivationPolicy(.regular)

        onboardingController = OnboardingWindowController()
        onboardingController?.show(configManager: appState.configManagerRef, appState: appState)

        // Observe when onboarding completes
        NotificationCenter.default.addObserver(
            forName: .onboardingCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await MainActor.run {
                    self?.onboardingDidComplete()
                }
            }
        }
    }

    /// Called when onboarding is completed
    private func onboardingDidComplete() {
        onboardingController?.close()
        onboardingController = nil

        // Switch back to accessory app (menu bar only)
        NSApp.setActivationPolicy(.accessory)

        // Start normal flow (status bar already exists from applicationDidFinishLaunching)
        startNormalFlow()
    }

    /// Start the normal app flow (after onboarding or on subsequent launches)
    private func startNormalFlow() {
        appState?.start()

        // Observe hotkey changes from settings
        observeHotkeyChanges()

        // Request accessibility permission
        requestAccessibilityAndRegisterHotkey()

        // Command bar starts hidden — user invokes via hotkey
        appState?.hideCommandBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stopScheduledTaskSystem()
        unregisterHotkey()
        permissionCheckTask?.cancel()
        if let observer = hotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Clean up browser-use-sidecar processes
        cleanupBrowserSidecar()
    }

    /// Kill any browser-use-sidecar processes when app terminates
    private func cleanupBrowserSidecar() {
        // Method 1: Try to send close command via CLI
        // Supports both --onedir and --onefile builds
        if let dirURL = Bundle.main.url(forResource: "browser-use-sidecar", withExtension: nil) {
            var sidecarPath = dirURL.appendingPathComponent("browser-use-sidecar").path
            if !FileManager.default.isExecutableFile(atPath: sidecarPath) {
                sidecarPath = dirURL.path
            }
            if FileManager.default.isExecutableFile(atPath: sidecarPath) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: sidecarPath)
                process.arguments = ["close"]
                process.standardOutput = nil
                process.standardError = nil
                do { try process.run() } catch { Log.debug("Sidecar close command failed: \(error)") }
            }
        }

        // Method 2: Kill by PID file (backup)
        let pidPath = FileManager.default.temporaryDirectory.appendingPathComponent("browser-use-sidecar.pid")
        if let pidString = try? String(contentsOf: pidPath, encoding: .utf8),
           let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            kill(pid, SIGTERM)
        }

        // Clean up temp files — ignore errors (files may not exist)
        let tempDir = FileManager.default.temporaryDirectory
        for file in ["browser-use-sidecar.sock", "browser-use-sidecar.pid", "browser-use-sidecar.lock"] {
            try? FileManager.default.removeItem(at: tempDir.appendingPathComponent(file))
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Skip during onboarding
        guard onboardingController == nil else { return }

        // Check if permission was granted while app was in background
        if globalMonitor == nil, AccessibilityHelper.hasPermission {
            registerHotkey()
        }
        appState?.ensureStatusBar()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Skip during onboarding
        guard onboardingController == nil else { return true }

        // Dock icon click opens Settings (not the command bar)
        SettingsWindowController.shared.show()
        return true
    }

    // MARK: - Accessibility Permission

    private func requestAccessibilityAndRegisterHotkey() {
        if AccessibilityHelper.hasPermission {
            // Already have permission
            registerHotkey()
            return
        }

        // Try to trigger system prompt (only works first time)
        let prompted = AccessibilityHelper.requestPermission()

        if !prompted {
            // System didn't show prompt (already asked before), show our own guide
            showAccessibilityGuide()
        }

        // Start polling for permission grant
        startPermissionCheckTimer()
    }

    private func showAccessibilityGuide() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            let hotkeyStr = self?.appState?.configManagerRef.hotkey ?? "⌥Space"
            let alert = NSAlert()
            alert.messageText = "Enable Accessibility for Hotkey"
            alert.informativeText = """
            To use the \(hotkeyStr) hotkey, please enable Motive in:

            System Settings → Privacy & Security → Accessibility

            Find "Motive" in the list and turn it ON.

            (If Motive is not in the list, you may need to click '+' and add it manually from Applications folder)
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "I'll do it later")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                AccessibilityHelper.openAccessibilitySettings()
            }
        }
    }

    private func startPermissionCheckTimer() {
        permissionCheckTask?.cancel()
        permissionCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if AccessibilityHelper.hasPermission {
                    self?.registerHotkey()
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Global Hotkey

    private func observeHotkeyChanges() {
        // Observe UserDefaults changes for hotkey
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await MainActor.run {
                    self?.reregisterHotkey()
                }
            }
        }
    }

    private func reregisterHotkey() {
        // Only re-parse if the hotkey string changed
        guard let configManager = appState?.configManagerRef else { return }
        let newHotkey = configManager.hotkey

        // Parse and update
        let (modifiers, keyCode) = HotkeyParser.parseToKeyCode(newHotkey)
        if modifiers != expectedModifiers || keyCode != expectedKeyCode {
            expectedModifiers = modifiers
            expectedKeyCode = keyCode
            Log.debug("Hotkey updated to: \(newHotkey) (keyCode: \(keyCode))")
        }
    }

    private func registerHotkey() {
        guard globalMonitor == nil else { return } // Already registered

        // Parse the hotkey from settings
        if let configManager = appState?.configManagerRef {
            let parsed = HotkeyParser.parseToKeyCode(configManager.hotkey)
            expectedModifiers = parsed.modifiers
            expectedKeyCode = parsed.keyCode
        }

        // Global monitor for when app is not active
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor for when app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // Consume the event
            }
            return event
        }

        let hotkeyStr = appState?.configManagerRef.hotkey ?? "⌥Space"
        Log.debug("Hotkey \(hotkeyStr) registered successfully (keyCode: \(expectedKeyCode))")
    }

    private func unregisterHotkey() {
        removeMonitor(&globalMonitor)
        removeMonitor(&localMonitor)
    }

    private func removeMonitor(_ monitor: inout Any?) {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Check if the pressed key matches our expected hotkey
        let pressedModifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])

        if pressedModifiers == expectedModifiers, event.keyCode == expectedKeyCode {
            Task { @MainActor [weak self] in
                self?.toggleCommandBar()
            }
            return true
        }
        return false
    }

    private func toggleCommandBar() {
        guard let appState else { return }

        if appState.isCommandBarVisible {
            appState.hideCommandBar()
        } else {
            appState.showCommandBar()
        }
    }
}
