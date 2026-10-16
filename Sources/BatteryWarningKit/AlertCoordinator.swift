import Foundation

/// 警示面板對目前狀態該做什麼。
public protocol AlertPresenting: AnyObject {
    /// 從「沒有提醒」轉為「有提醒」，面板該出現。
    func presentAlert(for status: BatteryStatus)
    /// 從「有提醒」轉為「沒有提醒」，面板該消失。
    func dismissAlert()
    /// 提醒仍在進行，但狀態變了。面板已經在畫面上，只需要把內容跟上——
    /// 若每次輪詢都重新 present 一次，那只是白做工。
    func refreshAlertContent(for status: BatteryStatus)
}

/// 警示面板與下拉選單背後唯一的狀態機。
///
/// 「現在是否在提醒」不會有任何下游自己重新推導：面板與選單摘要都是這個物件的
/// 觀察者，因此兩者不可能對提醒狀態有不同看法。門檻每次評估都從 store 重新讀取，
/// 所以調整門檻會立刻重新評估，不必等下一次輪詢。
///
/// 選單列的圖示是例外：它固定不變、不反映提醒狀態，因此並非本物件的觀察者。
public final class AlertCoordinator {
    public private(set) var latestStatus: BatteryStatus = .unavailable
    public private(set) var isAlerting = false
    public var thresholds: AlertThresholds {
        didSet {
            // 門檻被設成同一個值不算改變，不必重算。這讓外部可以把 UI 狀態
            // 綁在這個屬性上而不用擔心觸發多餘的重新評估。
            guard thresholds != oldValue else { return }
            reevaluateAfterThresholdChange()
        }
    }

    /// 每次狀態轉換都觸發，供面板以外的觀察者使用。
    public var onChange: ((BatteryStatus, Bool) -> Void)?

    private let monitor: BatteryMonitor
    private let store: ThresholdStore
    /// 弱參考：協調器不負責面板的生命週期，是 AppDelegate 持有面板。
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
        // weak self：monitor 與 store 都比本物件活得久，若閉包強參考 self
        // 會形成不會釋放的循環。
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

    /// 立刻重讀電池並重新評估。
    public func refreshNow() {
        monitor.refreshNow()
    }

    /// 來自監控層的新狀態，沿用前次的提醒狀態。
    func ingest(_ status: BatteryStatus) {
        apply(status, coldStart: false)
    }

    /// 門檻改變是一次全新的判斷，不是前一次的延續：使用者剛重新定義了「什麼程度
    /// 算低電量」，所以舊的提醒狀態對這次判斷沒有任何參考價值。
    private func reevaluateAfterThresholdChange() {
        apply(latestStatus, coldStart: true)
    }

    private func apply(_ status: BatteryStatus, coldStart: Bool) {
        latestStatus = status
        // coldStart 時無視前次狀態，當作「尚未提醒」重新評估。
        let previous = coldStart ? false : isAlerting
        let next = ThresholdEvaluator.isAlerting(
            previous: previous,
            status: status,
            thresholds: thresholds
        )
        let changed = next != isAlerting
        isAlerting = next

        if next {
            // present 只用在狀態轉換。已經在畫面上的面板只需要更新數字，
            // 否則它會永遠停在剛出現時的那個電量。
            if changed {
                presenter?.presentAlert(for: status)
            } else {
                presenter?.refreshAlertContent(for: status)
            }
        } else if changed {
            presenter?.dismissAlert()
        }
        onChange?(status, isAlerting)
    }
}