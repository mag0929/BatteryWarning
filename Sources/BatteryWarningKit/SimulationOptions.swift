import Foundation
import os

/// 解析 design 文件記載的除錯啟動參數。
///
/// 只有 `--simulate-battery` 與 `--simulate-external-power` 兩個參數會被辨識，
/// 而且必須兩個都格式正確才生效。正常啟動時不會有任何參數走到這裡，
/// 因此實際出貨走的永遠是真正的 IOKit 路徑。
public enum SimulationOptions {
    public static let batteryFlag = "--simulate-battery"
    public static let externalPowerFlag = "--simulate-external-power"

    private static let logger = Logger(
        subsystem: "com.local.batterywarning", category: "Simulation"
    )

    /// 解析成功回傳模擬的狀態，否則回傳 `nil`（代表「沒有要求模擬」）。
    ///
    /// 只給一個參數不算數：模擬狀態需要同時決定電量與電源狀態，缺一半會讓
    /// 另一半沿用真實讀值，產生一個現實中不可能出現的組合。
    public static func simulatedStatus(from arguments: [String]) -> BatteryStatus? {
        let batteryValue = value(of: batteryFlag, in: arguments)
        let externalValue = value(of: externalPowerFlag, in: arguments)

        guard let batteryValue, let externalValue else { return nil }

        guard let percent = Int(batteryValue), (0...100).contains(percent) else {
            logger.warning("ignoring \(batteryFlag) with value \(batteryValue, privacy: .public)")
            return nil
        }
        guard let external = parseBool(externalValue) else {
            logger.warning("ignoring \(externalPowerFlag) with value \(externalValue, privacy: .public)")
            return nil
        }

        return BatteryStatus(
            isBatteryPresent: true,
            percent: percent,
            isOnExternalPower: external,
            // 模擬參數無法表示「充電中」：真實的充電狀態來自 IOKit 的
            // AppleSmartBattery 資訊，而模擬路徑繞過了那一層。因此充電圖示
            // 只能靠單元測試驗證，實機模擬驗不出來。
            isCharging: false
        )
    }

    /// 同時接受 `--flag value` 與 design 文件記載的 `--flag=value` 兩種寫法。
    private static func value(of flag: String, in arguments: [String]) -> String? {
        for argument in arguments {
            if argument == flag {
                // flag 單獨出現而後面沒有值，視為格式錯誤而不是取用下一個參數——
                // 否則 `--simulate-battery --other` 會把 `--other` 當成電量。
                guard let index = arguments.firstIndex(of: argument),
                      arguments.index(after: index) < arguments.endIndex
                else { return nil }
                return arguments[arguments.index(after: index)]
            }
            if argument.hasPrefix("\(flag)=") {
                return String(argument.dropFirst(flag.count + 1))
            }
        }
        return nil
    }

    /// 文件記載的寫法是 `<0|1>`，而 Swift 的 `Bool("0")` 是 `nil`，因此數字
    /// 形式必須和字面形式分開處理。
    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }
}