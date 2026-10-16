import Foundation
import Testing
@testable import BatteryWarningKit

@Suite("電池圖示選擇")
struct BatteryIconTests {
    private func battery(
        _ percent: Int?,
        charging: Bool = false,
        present: Bool = true
    ) -> BatteryStatus {
        BatteryStatus(
            isBatteryPresent: present,
            percent: percent,
            isOnExternalPower: charging,
            isCharging: charging
        )
    }

    // Scenario: Panel icon shows the observed level（面板圖示顯示觀測到的電量）
    // Example: observed level resolves to an icon bucket（觀測到的電量對應到某一階圖示）
    @Test(
        "電量分級對應到指定的圖示",
        arguments: [
            (0, BatteryIcon.quarter),
            (25, BatteryIcon.quarter),
            (26, BatteryIcon.half),
            (50, BatteryIcon.half),
            (51, BatteryIcon.threeQuarters),
            (75, BatteryIcon.threeQuarters),
            (76, BatteryIcon.full),
            (100, BatteryIcon.full)
        ]
    )
    func testLevelResolvesToIconBucket(percent: Int, expected: String) {
        #expect(
            BatteryIcon.iconName(for: battery(percent), appearance: .light) == expected
        )
    }

    // Scenario: Panel icon shows the charging state（面板圖示顯示充電狀態）
    // Example: charging takes priority over the level（充電優先於電量分級）
    @Test func testChargingWinsOverEveryLevel() {
        for percent in [0, 25, 26, 50, 51, 75, 76, 100] {
            #expect(
                BatteryIcon.iconName(for: battery(percent, charging: true), appearance: .light)
                    == BatteryIcon.charging,
                "\(percent)% 時充電應顯示閃電"
            )
        }
    }

    // Scenario: No battery means no panel icon（沒有電池就沒有面板圖示）
    // Example: desktop Mac with no internal battery（桌上型電腦沒有內建電池）
    @Test func testNoBatteryHasNoIcon() {
        #expect(BatteryIcon.iconName(for: battery(nil, present: false), appearance: .light) == nil)
        #expect(BatteryIcon.iconName(for: battery(80, present: false), appearance: .light) == nil)
    }

    @Test func testUnreadableLevelHasNoIcon() {
        #expect(BatteryIcon.iconName(for: battery(nil), appearance: .light) == nil)
    }

    // Scenario: Level outside the covered ranges still yields an icon（超出範圍的電量仍有圖示）
    // Example: levels outside the covered range（落在涵蓋範圍之外的電量）
    @Test(
        "超出範圍的電量取最近的分級",
        arguments: [
            (-1, BatteryIcon.quarter),
            (101, BatteryIcon.full),
            (150, BatteryIcon.full)
        ]
    )
    func testLevelOutsideRangeClampsToNearest(percent: Int, expected: String) {
        #expect(
            BatteryIcon.iconName(for: battery(percent), appearance: .light) == expected
        )
    }

    // 原先這裡有個 testBothSurfacesResolveTheSameState，斷言的是
    // `iconName(...) == iconName(...)`——同一個呼叫比兩次，永遠成立。
    // 它的前提是選單列與面板都會呼叫 iconName；選單列改用固定狀態圖示後，
    // 面板是唯一的呼叫者，「兩個使用面一致」已無從驗證。
    // 跨介面的一致性改由 AlertCoordinatorTests 的面板可見度斷言把關。

    // Scenario: Icon stays distinguishable under the dark system appearance（深色系統外觀下圖示仍可辨識）
    // 淺色外觀的對應測試在下方；規格只為深色外觀列了場景，
    // 淺色則由該條需求的「兩種外觀都要清楚」一句涵蓋。
    @Test func testDarkAppearanceUsesTheLightOutlineVariant() {
        for percent in [0, 25, 50, 75, 100] {
            #expect(
                BatteryIcon.iconName(for: battery(percent), appearance: .dark)
                    == "\(BatteryIcon.levelIcon(forPercent: percent))-light",
                "深色背景下，\(percent)% 需要淺色外框"
            )
        }
        #expect(
            BatteryIcon.iconName(for: battery(15, charging: true), appearance: .dark)
                == "battery-charging-light"
        )
    }

    // 對應規格需求「淺色與深色系統外觀下都要清楚」，規格未另立場景。
    @Test func testLightAppearanceUsesTheStandardVariant() {
        for percent in [0, 25, 50, 75, 100] {
            #expect(
                BatteryIcon.iconName(for: battery(percent), appearance: .light)
                    == BatteryIcon.levelIcon(forPercent: percent),
                "淺色背景下，\(percent)% 需要深藍外框"
            )
        }
        #expect(
            BatteryIcon.iconName(for: battery(15, charging: true), appearance: .light)
                == "battery-charging"
        )
    }

    @Test func testEveryVariantNameIsUsableAsAFileName() {
        for icon in BatteryIcon.levelIcons + [BatteryIcon.charging] {
            for appearance in [SystemAppearance.light, .dark] {
                let name = BatteryIcon.resourceName(for: icon, appearance: appearance)
                #expect(!name.isEmpty)
                #expect(!name.contains(" "))
                #expect(name.hasSuffix(".png") == false)
            }
        }
    }
}