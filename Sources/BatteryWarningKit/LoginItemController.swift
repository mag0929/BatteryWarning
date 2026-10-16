import Foundation
import os

/// 在選單與系統之間斡旋「登入時啟動」這個開關。
///
/// 存檔的偏好值一律不當成事實，App 也絕不主動重新註冊自己：使用者若在
/// 「系統設定」把 App 移除了，下次啟動時開關會顯示為關閉，就這樣維持下去。
/// 要重新啟用只有使用者自己能做，也就是自己把開關打回去。
public final class LoginItemController {
    public static let preferenceKey = "launchAtLoginEnabled"

    public var onChange: ((Bool) -> Void)?

    private let registrar: LoginItemRegistering
    private let defaults: UserDefaults
    private let logger = Logger(
        subsystem: "com.local.batterywarning", category: "LoginItemController"
    )
    /// 目前開關狀態。真正的來源是 `registrar.isRegistered`，這個值只是把查詢
    /// 結果快取起來給選單用。
    public private(set) var isEnabled = false

    public init(
        registrar: LoginItemRegistering,
        defaults: UserDefaults = .standard
    ) {
        self.registrar = registrar
        self.defaults = defaults
    }

    /// 讀取真正的註冊狀態並採用它。不做任何註冊。
    @discardableResult
    public func reconcile() -> Bool {
        isEnabled = registrar.isRegistered
        // 把存檔的偏好值同步成真實狀態，讓選單與系統不會各說各話。
        if defaults.bool(forKey: Self.preferenceKey) != isEnabled {
            defaults.set(isEnabled, forKey: Self.preferenceKey)
        }
        onChange?(isEnabled)
        return isEnabled
    }

    /// 翻轉開關。永不拋錯：失敗時開關維持關閉並記錄到 log，
    /// 不會跳出對話框——選單列小工具在別人正忙著時彈視窗是一種冒犯。
    public func setEnabled(_ enabled: Bool) {
        if enabled {
            do {
                try registrar.register()
                // 註冊後回讀而不是直接設為 true：register() 成功不代表系統一定
                // 接受了（例如 ServiceManagement 在受管設備上會拒絕）。
                isEnabled = registrar.isRegistered
            } catch {
                logger.error("registration failed: \(String(describing: error), privacy: .public)")
                isEnabled = false
            }
        } else {
            registrar.unregister()
            isEnabled = registrar.isRegistered
        }
        defaults.set(isEnabled, forKey: Self.preferenceKey)
        onChange?(isEnabled)
    }
}