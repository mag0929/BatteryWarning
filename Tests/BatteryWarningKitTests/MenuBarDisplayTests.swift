import Foundation
import Testing
@testable import BatteryWarningKit

@Suite("選單列顯示")
struct MenuBarDisplayTests {
    private func battery(_ percent: Int) -> BatteryStatus {
        BatteryStatus(
            isBatteryPresent: true,
            percent: percent,
            isOnExternalPower: false,
            isCharging: false
        )
    }

    // Scenario: Normal battery level
    @Test func testNormalBatteryLevelHasNoWarningColour() {
        let display = MenuBarDisplayBuilder.make(status: battery(63), isAlerting: false)
        #expect(display.title == "63%")
        #expect(display.style == .normal)
        #expect(
            !display.title.contains(MenuBarDisplayBuilder.chargingPrompt),
            "the charging prompt appears only while alerting"
        )
    }

    // Scenario: Alert active
    @Test func testAlertActiveShowsWarningColourAndChargingPrompt() {
        let display = MenuBarDisplayBuilder.make(status: battery(15), isAlerting: true)
        #expect(display.style == .warning)
        #expect(display.title.contains(MenuBarDisplayBuilder.chargingPrompt))
        #expect(display.title.contains("15%"), "level is still shown alongside the prompt")
        #expect(display.title == "請插電充電 15%")
    }

    // Scenario: Alert clears
    @Test func testAlertClearReturnsToNormalAppearance() {
        let before = MenuBarDisplayBuilder.make(status: battery(15), isAlerting: true)
        let after = MenuBarDisplayBuilder.make(status: battery(15), isAlerting: false)
        #expect(before.style == .warning)
        #expect(after.style == .normal)
        #expect(before != after, "the same update that hides the panel changes the item")
    }

    @Test func testBatteryLevelFollowsTheReportedPercent() {
        #expect(MenuBarDisplayBuilder.make(status: battery(5), isAlerting: false).title == "5%")
        #expect(MenuBarDisplayBuilder.make(status: battery(100), isAlerting: false).title == "100%")
        #expect(MenuBarDisplayBuilder.make(status: battery(100), isAlerting: true).title == "請插電充電 100%")
    }

    // Scenario: Desktop Mac with no battery
    @Test func testNoBatteryReportsAbsenceNotZeroPercent() {
        let display = MenuBarDisplayBuilder.make(status: .unavailable, isAlerting: false)
        #expect(display.title == MenuBarDisplayBuilder.noBatteryText)
        #expect(display.style == .noBattery)
        #expect(!display.title.contains("%"))
    }

    @Test func testNoBatteryStaysQuietEvenIfAlertingFlagWereSet() {
        // Absence of a battery is not an alert state, whatever the flag says.
        let display = MenuBarDisplayBuilder.make(status: .unavailable, isAlerting: true)
        #expect(display.style == .noBattery)
        #expect(display.title == MenuBarDisplayBuilder.noBatteryText)
    }

    @Test func testBatteryPresentButPercentUnreadableIsTreatedAsNoBattery() {
        let unreadable = BatteryStatus(
            isBatteryPresent: true,
            percent: nil,
            isOnExternalPower: false,
            isCharging: false
        )
        let display = MenuBarDisplayBuilder.make(status: unreadable, isAlerting: false)
        #expect(display.style == .noBattery)
        #expect(display.title == MenuBarDisplayBuilder.noBatteryText)
    }
}