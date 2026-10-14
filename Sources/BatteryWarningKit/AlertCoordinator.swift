import Foundation

/// What the alert panel must do about the current state.
public protocol AlertPresenting: AnyObject {
    func presentAlert(for status: BatteryStatus)
    func dismissAlert()
}

/// The single state machine behind both the panel and the menu bar.
///
/// Nothing downstream re-derives "are we alerting": the panel and the status
/// item are both observers of this object, which is why they cannot disagree
/// about the alert state. Thresholds are read from the store on every
/// evaluation, so changing the threshold re-evaluates immediately rather than
/// waiting for the next poll.
public final class AlertCoordinator {
    public private(set) var latestStatus: BatteryStatus = .unavailable
    public private(set) var isAlerting = false
    public var thresholds: AlertThresholds {
        didSet {
            guard thresholds != oldValue else { return }
            reevaluateAfterThresholdChange()
        }
    }

    /// Fired on every state change for observers that are not the panel.
    public var onChange: ((BatteryStatus, Bool) -> Void)?

    private let monitor: BatteryMonitor
    private let store: ThresholdStore
    private weak var presenter: AlertPresenting?

    public init(
        monitor: BatteryMonitor,
        store: ThresholdStore,
        presenter: AlertPresenting
    ) {
        self.monitor = monitor
        self.store = store
        self.presenter = presenter
        self.thresholds = store.current
        monitor.onStatusChange = { [weak self] status in
            self?.ingest(status)
        }
        store.onChange = { [weak self] newThresholds in
            self?.thresholds = newThresholds
        }
    }

    public func start() {
        monitor.start()
    }

    public func stop() {
        monitor.stop()
    }

    /// Re-reads the battery and re-evaluates now.
    public func refreshNow() {
        monitor.refreshNow()
    }

    func ingest(_ status: BatteryStatus) {
        apply(status, coldStart: false)
    }

    /// A threshold change is a fresh decision, not a continuation: the user has
    /// just redefined which levels count as low, so the previous alert state is
    /// not evidence for anything.
    private func reevaluateAfterThresholdChange() {
        apply(latestStatus, coldStart: true)
    }

    private func apply(_ status: BatteryStatus, coldStart: Bool) {
        latestStatus = status
        let previous = coldStart ? false : isAlerting
        let next = ThresholdEvaluator.isAlerting(
            previous: previous,
            status: status,
            thresholds: thresholds
        )
        let changed = next != isAlerting
        isAlerting = next

        if changed {
            if next {
                presenter?.presentAlert(for: status)
            } else {
                presenter?.dismissAlert()
            }
        }
        onChange?(status, isAlerting)
    }
}