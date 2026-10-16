import Foundation
import ServiceManagement
import os

/// 系統登入項目的機制介面。藏在一層接縫後面，讓 fallback 路徑不必真的做
/// LaunchServices 註冊就能測試。
public protocol SystemLoginItem: AnyObject {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

/// 真正的 `SMAppService` 包裝。這是使用者看得到、也關得掉的路徑：
/// 「系統設定 › 一般 › 登入項目」。
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

/// App 用什麼方式把自己註冊為登入時啟動。
public protocol LoginItemRegistering: AnyObject {
    func register() throws
    func unregister()
    var isRegistered: Bool { get }
}

/// 兩種機制都註冊失敗。分開兩個 case，是為了讓 log 能分辨是哪一步壞掉。
public enum LoginItemError: Error {
    /// `SMAppService` 拒絕（多半是簽章問題）。
    case primaryFailed(Error)
    /// `SMAppService` 已失敗，寫 LaunchAgent 也失敗。
    case fallbackFailed(Error)
}

/// 目前登入工作階段的 UID，給 `launchctl gui/<uid>` 用。
public enum LoginItemEnvironment {
    public static var currentUID: String { String(getuid()) }
}

/// 先試 `SMAppService`，再退到 LaunchAgent。
///
/// ad-hoc 簽章的組建可能被系統拒絕，因此以每個使用者自己的 LaunchAgent 作為
/// fallback——不那麼乾淨，但能讓這項功能繼續可用，而不是靜默失效。
public final class LoginItemRegistrar: LoginItemRegistering {
    private let primary: SystemLoginItem
    private let bundleIdentifier: String
    private let executableURL: URL
    private let launchAgentsDirectory: URL
    /// 執行外部指令的注入點。測試用假實作取代真的呼叫 launchctl。
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

    /// 任一機制到位就回傳 true。事實來源是實際註冊狀態，不是存檔的偏好值。
    public var isRegistered: Bool {
        primary.isEnabled || fileManager.fileExists(atPath: launchAgentURL.path)
    }

    public func register() throws {
        do {
            try primary.register()
            logger.info("registered via SMAppService")
            return
        } catch {
            // 不拋出：這是預期到的降級路徑，不是錯誤。記在 notice 級別，
            // 讓它在正常運作時不至於被當成要追的錯誤。
            logger.notice("SMAppService rejected (\(String(describing: error), privacy: .public)); falling back to LaunchAgent")
        }
        do {
            try writeLaunchAgent()
            // launchctl 是盡力而為：讓下次登入能啟動的是那個 plist 檔本身，
            // 就算現在 bootstrap 失敗，下次登入時 launchd 還是會讀到它。
            let status = runCommand(
                "launchctl",
                ["bootstrap", "gui/\(LoginItemEnvironment.currentUID)", launchAgentURL.path]
            )
            logger.info("wrote LaunchAgent (launchctl status \(status))")
        } catch {
            // 兩條路都失敗才拋錯，這時使用者按的開關確實沒生效，
            // 值得讓呼叫端知道（`LoginItemController` 會把開關設回關閉）。
            logger.error("LaunchAgent fallback failed: \(String(describing: error), privacy: .public)")
            throw LoginItemError.fallbackFailed(error)
        }
    }

    /// 刻意不拋錯：使用者要求停止自動啟動，而清理失敗絕不能被回報成成功——
    /// 那會讓選單上的開關顯示為關閉，實際上 App 下次還是會自己開起來。
    /// 這個方法只記錄，不改變 `isRegistered` 的判斷依據。
    public func unregister() {
        do {
            try primary.unregister()
        } catch {
            logger.notice("SMAppService unregister failed; continuing LaunchAgent cleanup")
        }
        // 兩種機制都要清：使用者可能先用 LaunchAgent 註冊過，
        // 只清其中一種會留下孤兒設定。
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

    /// LaunchAgent plist 的位置。以 bundle identifier 命名而非 App 名稱，
    /// 避免使用者同時裝了多份時互相覆寫。
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
            // Interactive：讓 launchd 在 GUI 工作階段啟動它，這樣選單列圖示
            // 才會出現在畫面上。預設的 Standard 會被排程到背景。
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        // .atomic：先寫暫存檔再 rename，避免系統在寫到一半時讀到損壞的 plist。
        try data.write(to: launchAgentURL, options: .atomic)
    }

    /// 執行外部指令並回傳結束狀態。
    ///
    /// 找不到執行檔或啟動失敗時回傳 `-1`，讓呼叫端能用「非 0」統一判斷失敗，
    /// 不必分別處理「沒有檔案」與「啟動失敗」兩種情況。
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