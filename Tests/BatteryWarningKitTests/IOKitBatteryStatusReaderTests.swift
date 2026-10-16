import Foundation
import IOKit.ps
import Testing
@testable import BatteryWarningKit

/// 解析真正的 IOKit descriptor 字典，不需要真的有一顆電池。
@Suite("IOKit 狀態解析")
struct IOKitBatteryStatusReaderTests {

    private func descriptor(
        current: Int? = 15,
        maximum: Int? = 100,
        present: Bool? = true,
        external: Bool? = false,
        charging: Bool? = false
    ) -> [String: Any] {
        var d: [String: Any] = [:]
        if let present { d[kIOPSIsPresentKey as String] = present }
        if let current { d[kIOPSCurrentCapacityKey as String] = current }
        if let maximum { d[kIOPSMaxCapacityKey as String] = maximum }
        // 外部電源是靠電源狀態字串表達的，沒有專屬的旗標。
        d[kIOPSPowerSourceStateKey as String] = (external ?? false)
            ? kIOPSACPowerValue as String
            : kIOPSBatteryPowerValue as String
        if let charging { d[kIOPSIsChargingKey as String] = charging }
        return d
    }

    @Test func testReadsCurrentCapacityAndPowerFlags() {
        let status = IOKitBatteryStatusReader.makeStatus(
            from: descriptor(current: 15, maximum: 100, external: false, charging: false)
        )
        #expect(status.isBatteryPresent == true)
        #expect(status.percent == 15)
        #expect(status.isOnExternalPower == false)
        #expect(status.isCharging == false)

        let plugged = IOKitBatteryStatusReader.makeStatus(
            from: descriptor(current: 80, maximum: 100, external: true, charging: true)
        )
        #expect(plugged.percent == 80)
        #expect(plugged.isOnExternalPower == true)
        #expect(plugged.isCharging == true)
    }

    @Test func testPercentIsRoundedAndClamped() {
        #expect(IOKitBatteryStatusReader.makeStatus(from: descriptor(current: 155, maximum: 100)).percent == 100)
        #expect(IOKitBatteryStatusReader.makeStatus(from: descriptor(current: 1, maximum: 3)).percent == 33)
        #expect(IOKitBatteryStatusReader.makeStatus(from: descriptor(current: 2, maximum: 3)).percent == 67)
        #expect(IOKitBatteryStatusReader.makeStatus(from: descriptor(current: -5, maximum: 100)).percent == 0)
    }

    @Test func testCapacityKeysMissingYieldsNoPercentage() {
        let status = IOKitBatteryStatusReader.makeStatus(
            from: descriptor(current: nil, maximum: nil)
        )
        #expect(status.isBatteryPresent == true)
        #expect(status.percent == nil, "寧可沒有答案，也不要一個錯的數字")
    }

    @Test func testZeroMaximumYieldsNoPercentage() {
        let status = IOKitBatteryStatusReader.makeStatus(from: descriptor(current: 50, maximum: 0))
        #expect(status.percent == nil)
    }

    @Test func testDesktopDescriptorIsNotPresent() {
        let status = IOKitBatteryStatusReader.makeStatus(from: descriptor(present: false))
        #expect(status.isBatteryPresent)
    }
}