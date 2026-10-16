import Foundation
import Testing
@testable import BatteryWarningKit

@Suite("選單摘要文字")
struct MenuSummaryTextTests {
    private func battery(
        _ percent: Int?,
        onExternalPower: Bool = false,
        charging: Bool = false,
        present: Bool = true
    ) -> BatteryStatus {
        BatteryStatus(
            isBatteryPresent: present,
            percent: percent,
            isOnExternalPower: onExternalPower,
            isCharging: charging
        )
    }

    // 分隔符號是 U+2009 THIN SPACE，不是普通空格。
    private let sep = "\u{2009}·\u{2009}"

    // Scenario: Battery level is reported when the menu opens（選單打開時報出電量）
    @Test func testReportsLevelAndPowerSource() {
        #expect(MenuSummaryText.make(for: battery(63)) == "電量 63%\(sep)使用電池")
        #expect(MenuSummaryText.make(for: battery(5)) == "電量 5%\(sep)使用電池")
        #expect(MenuSummaryText.make(for: battery(100)) == "電量 100%\(sep)使用電池")
        #expect(
            MenuSummaryText.make(for: battery(80, onExternalPower: true))
                == "電量 80%\(sep)已接電源"
        )
        #expect(
            MenuSummaryText.make(for: battery(80, onExternalPower: true, charging: true))
                == "電量 80%\(sep)充電中"
        )
    }

    @Test func testLevelFollowsTheReportedPercent() {
        #expect(MenuSummaryText.make(for: battery(5)).contains("5%"))
        #expect(MenuSummaryText.make(for: battery(100)).contains("100%"))
    }

    // Scenario: Desktop Mac with no battery（沒有電池的桌上型電腦）
    @Test func testNoBatteryReportsAbsenceNotZeroPercent() {
        let text = MenuSummaryText.make(for: .unavailable)
        #expect(text == MenuSummaryText.noBatteryText)
        #expect(!text.contains("%"))
    }

    // Scenario: Battery status cannot be read（電池狀態無法讀取）
    @Test func testBatteryPresentButPercentUnreadableIsTreatedAsNoBattery() {
        #expect(
            MenuSummaryText.make(for: battery(nil)) == MenuSummaryText.noBatteryText
        )
        #expect(
            MenuSummaryText.make(for: battery(80, present: false)) == MenuSummaryText.noBatteryText
        )
    }
}