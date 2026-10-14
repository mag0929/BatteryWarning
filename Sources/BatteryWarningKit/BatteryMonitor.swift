import AppKit
import Foundation
import IOKit.ps
import os

/// Watches battery state and republishes it.
///
/// Two inputs, per the design: an IOKit run-loop notification for immediate
/// reaction to power events, and a 30-second timer as insurance — macOS
/// reports battery level in coarse steps, so a percent change can slip
/// through without any event arriving. Waking from sleep re-reads at once.
public final class BatteryMonitor {
    public static let pollInterval: TimeInterval = 30

    public var onStatusChange: ((BatteryStatus) -> Void)?

    private let reader: BatteryStatusReading
    private let pollInterval: TimeInterval
    private let logger = Logger(
        subsystem: "com.local.batterywarning", category: "BatteryMonitor"
    )

    private var timer: Timer?
    private var runLoopSource: CFRunLoopSource?
    private var lastStatus: BatteryStatus?

    /// When set, the monitor reports this instead of touching IOKit and stops
    /// its timer and notification. Only reachable through the documented
    /// `--simulate-battery` launch arguments; a normal launch never sets it.
    private let simulated: BatteryStatus?

    public init(
        reader: BatteryStatusReading = IOKitBatteryStatusReader(),
        pollInterval: TimeInterval = BatteryMonitor.pollInterval,
        simulated: BatteryStatus? = nil
    ) {
        self.reader = reader
        self.pollInterval = pollInterval
        self.simulated = simulated
    }

    deinit { stop() }

    public func start() {
        guard timer == nil || simulated != nil else { return }

        if let simulated {
            // Debug path: one immediate report, no IOKit, no timer.
            lastStatus = simulated
            onStatusChange?(simulated)
            return
        }

        startNotification()
        startTimer()
        refreshNow()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
    }

    /// Re-reads immediately and publishes when anything changed.
    public func refreshNow() {
        let status = simulated ?? reader.readStatus()
        guard status != lastStatus else { return }
        lastStatus = status
        onStatusChange?(status)
    }

    // MARK: - Inputs

    private func startTimer() {
        let t = Timer(
            timeInterval: pollInterval,
            target: self,
            selector: #selector(pollFired),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func pollFired() {
        refreshNow()
    }

    @objc private func systemDidWake() {
        handleSystemWake()
    }

    /// Wake handling, internal so tests can drive it without the workspace.
    func handleSystemWake() {
        // Never act on the value remembered from before sleep.
        lastStatus = nil
        refreshNow()
    }

    private func startNotification() {
        // The public API takes only a callback and context — there is no
        // type filter — and fires whenever a power source is added, removed,
        // or changes, including percent remaining.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let unmanaged = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            // Hop to the main run loop: observers touch AppKit.
            DispatchQueue.main.async { monitor.refreshNow() }
        }, context) else {
            logger.error("could not create IOKit power source notification")
            return
        }
        let source = unmanaged.takeRetainedValue()
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    }
}