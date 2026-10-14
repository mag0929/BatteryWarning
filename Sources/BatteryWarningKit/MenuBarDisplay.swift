import Foundation

/// What the menu bar item should display, computed without AppKit so the
/// presentation rule can be tested directly.
///
/// The app layer is responsible only for turning `style` into a colour; the
/// text and the warning decision live here.
public struct MenuBarDisplay: Equatable {
    public enum Style: Equatable {
        /// Battery level only, default colour.
        case normal
        /// Warning colour plus the charging prompt.
        case warning
        /// No battery information could be read.
        case noBattery
    }

    public let title: String
    public let style: Style

    public init(title: String, style: Style) {
        self.title = title
        self.style = style
    }
}

public enum MenuBarDisplayBuilder {
    /// Shown while the alert is active, as the spec requires the item to carry
    /// a charging prompt rather than only a colour change.
    public static let chargingPrompt = "請插電充電"
    public static let noBatteryText = "無電池資訊"

    public static func make(
        status: BatteryStatus,
        isAlerting: Bool
    ) -> MenuBarDisplay {
        guard status.isBatteryPresent, let percent = status.percent else {
            return MenuBarDisplay(title: noBatteryText, style: .noBattery)
        }

        let level = "\(percent)%"
        guard isAlerting else {
            return MenuBarDisplay(title: level, style: .normal)
        }
        return MenuBarDisplay(title: "\(chargingPrompt) \(level)", style: .warning)
    }
}