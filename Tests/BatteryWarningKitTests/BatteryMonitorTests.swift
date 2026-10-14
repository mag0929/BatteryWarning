import Foundation
import Testing
@testable import BatteryWarningKit

@Suite("電池監看")
struct BatteryMonitorTests {

    /// Reader that returns a scripted sequence and counts how often it was read.
    final class ScriptedReader: BatteryStatusReading {
        var statuses: [BatteryStatus]
        private(set) var readCount = 0

        init(_ statuses: [BatteryStatus]) { self.statuses = statuses }

        func readStatus() -> BatteryStatus {
            readCount += 1
            return statuses.isEmpty ? .unavailable : statuses.removeFirst()
        }
    }

    private func battery(_ percent: Int, external: Bool = false, charging: Bool = false) -> BatteryStatus {
        BatteryStatus(
            isBatteryPresent: true,
            percent: percent,
            isOnExternalPower: external,
            isCharging: charging
        )
    }

    @Test func testRefreshNowPublishesStatusChange() {
        let reader = ScriptedReader([battery(42), battery(41), battery(41)])
        let monitor = BatteryMonitor(reader: reader)

        var received: [BatteryStatus] = []
        monitor.onStatusChange = { received.append($0) }

        monitor.refreshNow()
        monitor.refreshNow()
        monitor.refreshNow()

        #expect(received == [battery(42), battery(41)], "unchanged status is not republished")
    }

    @Test func testStartWithSimulatedStatusSkipsReader() {
        let reader = ScriptedReader([battery(99)])
        let monitor = BatteryMonitor(reader: reader, simulated: battery(15, external: false))

        var received: [BatteryStatus] = []
        monitor.onStatusChange = { received.append($0) }
        monitor.start()

        #expect(received == [battery(15)])
        #expect(reader.readCount == 0, "simulated mode must not touch IOKit")
        monitor.stop()
    }

    @Test func testSimulatedStatusKeepsReportedValueOnRefresh() {
        let reader = ScriptedReader([battery(99), battery(98)])
        let monitor = BatteryMonitor(reader: reader, simulated: battery(15))

        monitor.refreshNow()
        monitor.refreshNow()

        #expect(reader.readCount == 0)
    }

    @Test func testRefreshesAfterWake() {
        let reader = ScriptedReader([battery(80)])
        let monitor = BatteryMonitor(reader: reader)

        var received: [BatteryStatus] = []
        monitor.onStatusChange = { received.append($0) }
        monitor.refreshNow()
        #expect(received.count == 1)

        // The workspace wake notification drives a re-read and republishes even
        // though the app already saw this value.
        monitor.handleSystemWake()
        #expect(received.count == 2)
        #expect(reader.readCount == 2)
        monitor.stop()
    }

    @Test func testPollIntervalIsThirtySeconds() {
        #expect(BatteryMonitor.pollInterval == 30)
    }

    @Test func testSimulationOptionsParseBothFlags() {
        let args = ["--simulate-battery", "15", "--simulate-external-power", "0"]
        let status = SimulationOptions.simulatedStatus(from: args)
        #expect(status == BatteryStatus(isBatteryPresent: true, percent: 15, isOnExternalPower: false, isCharging: false))
    }

    @Test func testSimulationOptionsParseExternalPowerOn() {
        let args = ["--simulate-battery", "15", "--simulate-external-power", "true"]
        let status = SimulationOptions.simulatedStatus(from: args)
        #expect(status?.isOnExternalPower == true)
        #expect(status?.percent == 15)
    }

    @Test func testSimulationOptionsAcceptEqualsForm() {
        // The documented invocation form: --simulate-battery=<percent>
        let args = ["--simulate-battery=15", "--simulate-external-power=0"]
        let status = SimulationOptions.simulatedStatus(from: args)
        #expect(status?.percent == 15)
        #expect(status?.isOnExternalPower == false)

        let plugged = ["--simulate-battery=15", "--simulate-external-power=1"]
        #expect(SimulationOptions.simulatedStatus(from: plugged)?.isOnExternalPower == true)
    }

    @Test func testSimulationOptionsAcceptMixedForms() {
        let args = ["--simulate-battery=20", "--simulate-external-power", "0"]
        #expect(SimulationOptions.simulatedStatus(from: args)?.percent == 20)
    }

    @Test func testSimulationOptionsIgnoredWhenArgumentsAbsent() {
        #expect(SimulationOptions.simulatedStatus(from: []) == nil)
        #expect(SimulationOptions.simulatedStatus(from: ["--other", "1"]) == nil)
    }

    @Test func testSimulationOptionsIgnoredWhenOnlyOneFlagPresent() {
        #expect(SimulationOptions.simulatedStatus(from: ["--simulate-battery", "15"]) == nil)
        #expect(SimulationOptions.simulatedStatus(from: ["--simulate-external-power", "0"]) == nil)
    }

    @Test func testSimulationOptionsRejectedForBadValues() {
        #expect(SimulationOptions.simulatedStatus(from: ["--simulate-battery", "abc", "--simulate-external-power", "0"]) == nil)
        #expect(SimulationOptions.simulatedStatus(from: ["--simulate-battery", "150", "--simulate-external-power", "0"]) == nil)
        #expect(SimulationOptions.simulatedStatus(from: ["--simulate-battery", "15", "--simulate-external-power", "maybe"]) == nil)
    }
}