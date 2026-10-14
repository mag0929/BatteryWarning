import Foundation
import ServiceManagement
import os

/// The system login item mechanism, behind a seam so the fallback path can be
/// tested without a real LaunchServices registration.
public protocol SystemLoginItem: AnyObject {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

/// Real `SMAppService` wrapper. This is the route the user can see and turn off
/// in System Settings › General › Login Items.
public final class SMAppLoginItem: SystemLoginItem {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

/// How the app gets itself registered to start at login.
public protocol LoginItemRegistering: AnyObject {
    func register() throws
    func unregister()
    var isRegistered: Bool { get }
}

public enum LoginItemError: Error {
    case primaryFailed(Error)
    case fallbackFailed(Error)
}

/// UID of the current login session, used for `launchctl gui/<uid>`.
public enum LoginItemEnvironment {
    public static var currentUID: String { String(getuid()) }
}

/// SMAppService first, LaunchAgent second.
///
/// An ad-hoc signed build can be rejected by the system, so a per-user
/// LaunchAgent is the fallback — less tidy, but it keeps the feature working
/// instead of failing silently.
public final class LoginItemRegistrar: LoginItemRegistering {
    private let primary: SystemLoginItem
    private let bundleIdentifier: String
    private let executableURL: URL
    private let launchAgentsDirectory: URL
    private let runCommand: (String, [String]) -> Int32
    private let fileManager: FileManager
    private let logger = Logger(
        subsystem: "com.local.batterywarning", category: "LoginItem"
    )

    public init(
        primary: SystemLoginItem = SMAppLoginItem(),
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.local.batterywarning",
        executableURL: URL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: "/Applications/BatteryWarning.app/Contents/MacOS/BatteryWarning"),
        launchAgentsDirectory: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        runCommand: @escaping (String, [String]) -> Int32 = LoginItemRegistrar.run,
        fileManager: FileManager = .default
    ) {
        self.primary = primary
        self.bundleIdentifier = bundleIdentifier
        self.executableURL = executableURL
        self.launchAgentsDirectory = launchAgentsDirectory
        self.runCommand = runCommand
        self.fileManager = fileManager
    }

    /// True when either mechanism is in place. The actual registration is the
    /// source of truth, not a stored preference.
    public var isRegistered: Bool {
        primary.isEnabled || fileManager.fileExists(atPath: launchAgentURL.path)
    }

    public func register() throws {
        do {
            try primary.register()
            logger.info("registered via SMAppService")
            return
        } catch {
            logger.notice("SMAppService rejected (\(String(describing: error), privacy: .public)); falling back to LaunchAgent")
        }
        do {
            try writeLaunchAgent()
            // Best effort — the file itself is what makes it work next login.
            let status = runCommand(
                "launchctl",
                ["bootstrap", "gui/\(LoginItemEnvironment.currentUID)", launchAgentURL.path]
            )
            logger.info("wrote LaunchAgent (launchctl status \(status))")
        } catch {
            logger.error("LaunchAgent fallback failed: \(String(describing: error), privacy: .public)")
            throw LoginItemError.fallbackFailed(error)
        }
    }

    public func unregister() {
        // Deliberately non-throwing: the user asked to stop auto-start, and a
        // cleanup failure must not be reported as a success.
        do {
            try primary.unregister()
        } catch {
            logger.notice("SMAppService unregister failed; continuing LaunchAgent cleanup")
        }
        _ = runCommand("launchctl", ["bootout", "gui/\(LoginItemEnvironment.currentUID)"])
        do {
            if fileManager.fileExists(atPath: launchAgentURL.path) {
                try fileManager.removeItem(at: launchAgentURL)
            }
        } catch {
            logger.error("could not remove \(self.launchAgentURL.path, privacy: .public)")
        }
    }

    // MARK: - LaunchAgent

    var launchAgentURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(bundleIdentifier).plist")
    }

    private func writeLaunchAgent() throws {
        try fileManager.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true
        )
        let plist: [String: Any] = [
            "Label": bundleIdentifier,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgentURL, options: .atomic)
    }

    public static func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return -1 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}