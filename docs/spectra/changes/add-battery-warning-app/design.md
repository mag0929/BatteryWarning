## Context

全新專案，目前 `docs/spectra/specs/` 沒有任何能力規格，也沒有任何程式碼。本變更要建立一個 macOS 原生 App，常駐在選單列，開機自動啟動，並在使用者沒有在充電時把電量壓到門檻以下的情況下主動提醒。

本機工具鏈現況（實測，非假設）：

| 工具 | 狀態 | 對設計的影響 |
| --- | --- | --- |
| Swift 6.4.3 | 可用，target `arm64-apple-macosx26.0` | 原生 App 可行 |
| Rust / Node | 未安裝 | Tauri、Electron 直接排除 |
| Xcode | `/Applications/Xcode.app` 存在，但 `xcode-select -p` 指向 `/Library/Developer/CommandLineTools`，`xcodebuild` 目前無法執行 | 不能假設有完整 Xcode 工具鏈，也不假設能改系統設定 |
| Python 3.13 | 可用 | 需 py2app 才能打包，登入項註冊較不穩 |

約束：

- 建置流程不得要求 `sudo xcode-select`，使用者未要求修改系統開發者目錄。
- App 不應搶走使用者當下的焦點。使用者明確表示提示必須壓過當下 active 的 app，但同時他仍在該 app 裡工作。
- 部署目標為使用者自己的 Mac，僅需本機有效，不做 App Store 或公證（notarization）。

## Goals / Non-Goals

**Goals:**

- 開機後自動在背景啟動，使用者不需要手動開啟。
- 選單列常駐，隨時可看到目前電量與充電狀態。
- 電量低於門檻時，以壓過所有 app 的浮動提示提醒充電，直到使用者開始充電才自動收起。
- 提示出現與消失全自動，不需使用者操作任何按鈕。
- 使用者可在選單列下拉選單內調整低電量提醒門檻，不必開啟任何設定視窗。
- 在無電池的桌上型 Mac 上完全不出現。

**Non-Goals:**

- 不新增任何其他使用者設定。面板大小、提醒頻率、靜音時段、門檻以外的偏好一律不做，本次僅開放門檻一項。
- 不讓使用者分別設定「觸發門檻」與「解除門檻」兩個數字，解除門檻由觸發門檻推導。
- 不做歷程紀錄、不做統計、不做通知中心推播歷史。
- 不做多台裝置同步、不做任何網路請求。
- 不做 App Store 發佈、公證、Sparkle 自動更新。
- 不做 iOS / iPadOS 版本。

## Decisions

### 採用 Swift + AppKit 選單列 App

使用 Swift 6.4 搭配 AppKit（`NSStatusItem` + `NSPanel`）。`NSStatusItem` 是 macOS 選單列圖示的標準做法，不需要主視窗，App 也不會在 Dock 顯示（`Info.plist` 設 `LSUIElement = true`）。

**替代方案與否決理由：**

| 方案 | 否決理由 |
| --- | --- |
| Tauri（Rust + Web 前端） | 本機沒有安裝 Rust，且對一個只需要選單列圖示加一個小面板的 App 而言，引入 WebView 與 Rust 工具鏈成本不成比例 |
| Electron | 同樣沒有 Node；體積與記憶體負擔對常駐型 App 過重 |
| Python + py2app | 常駐 App 的啟動速度、打包產物大小與登入項註冊穩定性都不如原生 |
| SwiftUI 為主 | 面板只需要一個靜態佈局，AppKit 的 `NSPanel` 對「不搶焦點 + 任意視窗層級」的控制更直接；SwiftUI 在 `NSWindow` 層級控制上仍需退回 AppKit |

### 使用 SwiftPM 搭配打包腳本，不依賴完整 Xcode

專案以 Swift Package Manager 的 executable target 組織，由一支 shell 腳本組出 `BatteryWarning.app`：建立 `Contents/MacOS`、寫入 `Info.plist`、`codesign --force --deep --sign -` 做 ad-hoc 簽章。

**替代方案與否決理由：** 改用 `xcode-select -s /Applications/Xcode.app` 切到完整 Xcode 會得到較正規的 GUI 專案與自動簽章，但需要 `sudo`、需要開啟 Xcode，且使用者並未要求修改系統開發者目錄。SwiftPM 路徑在現有 Command Line Tools 環境下即可完整建置。

**測試需要完整 Xcode 的工具鏈（實作時確認）：** Command Line Tools 只附 `Testing.framework`，沒有 `XCTest.framework`，也沒有 `TestingMacros` 外掛，因此 `swift test` 在 CLT 下無法解析測試框架。解法是在執行測試時以 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 指定完整 Xcode 的工具鏈。這是單一命令的環境變數，**不需要 `sudo`，也不修改任何系統設定**，且 `swift build` 與打包腳本仍然只使用 Command Line Tools。此設定寫在 `Makefile` 的 `test` 目標，使用者以 `make test` 執行即可。

### 提示使用最高層級的 NSPanel，且成為 non-activating panel

使用者需求是「提示訊息優先於所有 app，當下 active 哪個 app 都要顯示在最上面」，因此：

- `window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))` — macOS 視窗層級中最高的一般層級，高於 `.floating`、選單列與彈出選單。
- `styleMask` 包含 `.nonactivatingPanel`，`canBecomeKey = false`、`becomesKeyOnlyIfNeeded = true` — 面板出現時不搶走當下 app 的焦點，使用者可以繼續在原 app 打字。
- `collectionBehavior` 設為 `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` — 在全螢幕 app、跨 Space 切換時仍然可見。

面板內容為靜態文字（電量百分比 + 「請插電充電」）與一個電池圖示，不含任何按鈕。**替代方案**：改用 `UNUserNotificationCenter` 系統通知。否決理由是橫幅約 5 秒會自動消失、需事先授權、專注模式會被靜音、且通知中心會堆疊成一串，都不符合「持續到開始充電才消失」的需求。

### 面板位置釘在滑鼠所在螢幕的右上角

面板顯示在 `NSScreen` 中滑鼠游標所在的那個螢幕的右上角：右緣與上緣各留一段邊距，上緣額外讓開選單列高度（`NSScreen.menuBarVisible` 為 false 時不讓），避免蓋住時鐘與選單列圖示。監聽 `NSScreen` 變更與游標移動，跨螢幕時重新定位。

右上角與 macOS 通知橫幅的預設出現位置重疊。由於面板層級高於通知，實際結果是面板蓋住通知而非被通知遮蔽，提醒永遠可讀；代價是兩者同時出現時視覺上會擠在一起。

**替代方案**：底部中央、置中顯示或跟隨 active app 所在視窗。否決理由是使用者指定右上角；右上角在慣用右手的情況下視線最容易移動到。

### 提醒門檻可由使用者在選單列下拉選單調整

觸發門檻存放於 `UserDefaults`（鍵名 `alertThresholdPercent`），預設值 20。可調範圍 5%–50%，每次調整 5%。

調整介面放在既有的選單列下拉選單內，不另開設定視窗：

```
低電量提醒門檻        20%      ← 唯讀摘要，點擊無動作
   提高門檻  (−)              ← 停用時顯示為灰色
   降低門檻  (+)              ← 已達 5% 下限時停用
```

選單每次打開時重建項目，並依當前門檻設定兩個調整項目的啟用／停用狀態，使用者在按下去之前就能看出還能不能再調。調整後立即寫入 `UserDefaults`、重繪圖示標題、並立刻以新門檻重新評估當前電量。

**替代方案與否決理由：**

| 方案 | 否決理由 |
| --- | --- |
| 獨立設定視窗（Cmd+,） | 為了調整一個數字要多開一個視窗、多點幾次，且需自行維護視窗生命週期。日後若真的有多項設定再抽出來不遲 |
| 用滑桿呈現 | macOS 的選單列下拉選單沒有滑桿控件，需自繪且無法用原生選單鍵盤導覽 |
| 只用 `defaults write` 指令列調整 | 每次要改都得開 Terminal，且寫錯值難以察覺 |
| 子選單列舉固定值（10/15/20/25/30） | 比 −／＋ 多一次點擊，且無法設定 5%–50% 之間的所有值 |

### 解除門檻由觸發門檻推導，不獨立設定

解除門檻固定為「觸發門檻 + 5%」，上限 100%。當觸發門檻為 20%（預設）時，解除門檻即為 25%，與原本的行為一致。

只讓使用者設定一個數字，是因為兩個門檻存在的唯一目的是避免電量在門檻附近來回跳時面板閃爍，這個間隔距離用不着另外讓人操心。

**調整門檻時的即時行為：** 門檻一變動就以「冷啟動」重新評估，不沿用先前的警告狀態。使用者剛剛重新定義了什麼叫做低電量，先前狀態已經沒有參考價值。

這個方向的意義是：門檻只有「低於目前電量」時才會解除面板；門檻「高於目前電量」時面板會維持或出現，因為此時電量仍然低於門檻。舉例而言，電量 15% 時把門檻由 20% 提高到 45%，電量依然低於門檻，面板維持顯示；反之把門檻由 20% 降到 10%，電量已高於門檻，面板立即消失。

不得等待下一次 30 秒輪詢。

**替代方案與否決理由：** 讓兩個門檻各自可調。否決理由是會產生「解除門檻低於觸發門檻」這種無效組合，使用者還得自己維護兩組數字的相對關係。

### 門檻由值型別傳入判斷器，不在判斷器內讀取 UserDefaults

門檻調整帶來一個新的儲存分界點，處理方式如下：

```
UserDefaults ──載入 + 夾邊界──▶ AlertThresholds（值型別）
                                     │
                                     ▼
                        ThresholdEvaluator.isAlerting(...)
                                     │
                    ┌────────────────┴────────────────┐
                    ▼                                 ▼
             AlertPresenter                    StatusItemController
             （面板顯示／隱藏）                 （圖示顏色、標題）
```

`ThresholdEvaluator` 只接受傳入的 `AlertThresholds`，自身不碰 `UserDefaults`。這讓單元測試不需要建立或污染 `UserDefaults`，面板與選單列也必然讀到同一組門檻。

讀取時一律夾邊界：值不在 5–50 範圍內時退回預設值 20，不讓外部寫入的壞值（例如指令列塞入 `-5` 或 `200`）造成面板永不出現或永遠出現。

只有 `UserDefaults` 一種儲存後端，因此**不抽出**儲存 protocol 介面 — 單一後端只是想像中的分界，待真的出現第二種儲存方式再抽象。

### 以 IOKit 事件監聽搭配 30 秒輪詢保險

電池狀態來源為 IOKit：

- `IOPSNotificationCreateRunLoopSource(callback, context)` 建立 run loop source，掛上 `CFRunLoopMode.commonModes`，事件到達時在主執行緒重算狀態。**公開 API 沒有型別過濾參數**（`IOPSNotificationCreateRunLoopSourceMatching` 不在公開 SDK 中），因此所有電源來源的變化都會觸發回呼。依 IOKit 標頭說明，回呼涵蓋「電源被新增、移除或變動」，包含剩餘電量百分比變化。
- `IOPSCopyPowerSourcesInfo` + `IOPSGetPowerSourceDescription` 讀取狀態。**公開 API 沒有 `ExternalPower` 布林欄位**，是否接上外部電源要從 `kIOPSPowerSourceStateKey` 的字串判斷：值不等於 `kIOPSBatteryPowerValue`（即為 `kIOPSACPowerValue`）即代表使用外部電源。電量取 `Current Capacity` / `Max Capacity`，充電旗標取 `kIOPSIsChargingKey`（`"Is Charging"`），有無電池取 `kIOPSIsPresentKey`。
- 桌上型 Mac 只會回報 AC 電源來源且 `Is Present` 為 false，逐一略過後即視為無電池。

macOS 回報的電量是粗略階梯（一次跳數個百分比），且 IOKit 標頭明確指出放電與充電期間通知會相當頻繁，但事件仍不保證涵蓋每一次百分比變動，因此額外以 30 秒 `Timer` 輪詢作為保險。

**替代方案與否決理由：** 輪詢 `pmset -g batt`（子行程，每 30 秒 spawn 一次）程式負擔較高且解析本地化輸出不穩；`ioreg` 的私有 power source 數值在部分机型回報異常。IOKit 公開 API 是唯一穩定且無需私有 API 的來源。

### 內建僅限除錯的狀態覆寫以支援人工驗收

低電量情境無法在實機上重現：`pmset` 只能調整電源來源行為（`pmset -c`、`pmset -b`），無法偽造系統回報的電量百分比；唯一真實的重現方式是實際耗電到門檻以下。因此需要一條不影響正常使用、但足以支撐人工驗收的路徑。

設計如下：

- `BatteryMonitoring` 的狀態來源可被覆寫。啟動時若命令列帶入 `--simulate-battery=<百分比>` 與 `--simulate-external-power=<0|1>`，App 以這些值取代 IOKit 讀取結果，並停用 IOKit 通知與輪詢計時器。
- 覆寫僅在帶入該啟動參數時生效。未帶參數的啟動走完整的 IOKit 路徑，行為與沒有此機制完全相同。
- 覆寫狀態下仍跑同一套 `ThresholdEvaluator` 與同一個呈現層，不另開一條程式路徑，因此人工驗收到的就是正式邏輯。

驗收時以此方式觸發低電量：`<app> --simulate-battery=15 --simulate-external-power=0`，再以 `--simulate-external-power=1` 驗證插電後自動收起。

**替代方案與否決理由：** 實際耗電到 20% 以下才能驗收，代價是每次驗收都要數小時且不可重現；在選單加入隱藏的「測試模式」項目，則正式環境多了一條可被誤觸的狀態路徑。啟動參數在正常使用下不可能出現，是干擾最小的做法。

### 以「已接上電源」而非「充電中」作為解除條件

`ExternalPowerSource == true` 即解除面板，不要求 `IsCharging == true`。當 Mac 插著電但因為已充飽、或使用者啟用了充電最佳化而未在充電時，警告繼續懸掛只會造成困擾 — 使用者已經插電，要解決的問題不存在。

**替代方案與否決理由：** 嚴格以 `IsCharging` 判定，忠于「到開始充電」的字面描述，但會讓已插電卻未充電的使用者持續看到提醒。此為可回退的判定，若使用者之後要求嚴格語意，只需調整單一判定條件。

### 開機啟動使用 SMAppService，失敗時退回 LaunchAgent

註冊流程：

1. 呼叫 `SMAppService.mainApp.register()`（macOS 13+）。優點是使用者可在「系統設定 › 一般 › 登入項目」自行檢視與關閉。
2. 若註冊失敗（ad-hoc 簽章的 App 可能被系統拒絕），自動改寫 `~/Library/LaunchAgents/<bundle-id>.plist`（`RunAtLoad = true`、`ProcessType = Interactive`），以 `launchctl bootstrap gui/$UID` 載入。
3. 選單列選單提供「登入時開啟」開關，兩種方式都以同一個 `UserDefaults` 旗標作為使用者可見的真相來源，啟動時重新讀取並確保與實際狀態一致。

**替代方案與否決理由：** 直接寫 LaunchAgent plist 而不試 `SMAppService`，實作較單純但使用者無從在系統設定中關閉它，且 App 被刪除後會留下孤立的 plist。兩段式作法兼顧可控性與功能保證。

### 選單列圖示與下拉選單

`NSStatusItem` 圖示顯示目前電量百分比；在低於門檻且未接上電源時改為紅色並附「請插電充電」標題。點擊開啟選單：

- 目前電量與狀態摘要（唯讀）
- 「立即檢查」— 強制重算一次狀態
- 分隔線
- 「低電量提醒門檻  20%」（唯讀摘要）＋「提高門檻 (−）」／「降低門檻 (+)」
- 分隔線
- 「開啟電池設定…」— 開啟「系統設定 › 電池」
- 「登入時開啟」勾選選單項目 — 對應上述開機啟動機制
- 「結束 BatteryWarning」

選單列圖示是面板之外的第二個訊號來源：面板會覆蓋其他視窗，選單列則隨時可一眼確認狀態。

### 面板與選單列共用單一狀態機，且共用同一組門檻

`BatteryMonitor` 為唯一狀態來源，定期產出 `BatteryStatus`（`isBatteryPresent`、`percent`、`isOnExternalPower`、`isCharging`）。`AlertPresenter` 與 `StatusItemController` 皆為其觀察者，不各自持有狀態。

兩者也都不自行讀取門檻。門檻由 `AlertThresholds` 值型別在啟動時載入一次，之後由 `ThresholdStore`（封裝 `UserDefaults` 讀寫與夾邊界）持有；調整門檻時 `ThresholdStore` 通知觀察者，兩者都以同一組新門檻重新評估。

這讓「電量回升解除面板」、「圖示復原為正常顏色」與「調整門檻後立即重新評估」不可能出現不一致。

## Implementation Contract

### 使用者可觀察到的行為

1. App 啟動後於選單列出現電量圖示，無 Dock 圖示、無主視窗。
2. 使用者啟用「登入時開啟」並登出重登後，App 自動啟動且不顯示任何啟動視窗。
3. 電量由 21% 降至 20%（預設門檻）且未接上電源時，滑鼠所在螢幕的右上角出現浮動面板，顯示電量百分比與「請插電充電」。
4. 該面板疊加在當下 active app 的所有視窗之上，包含全螢幕 app；出現的瞬間不奪取鍵盤焦點（使用者可繼續在原 app 輸入）。
5. 面板上緣位於選單列下方，不覆蓋時鐘與選單列圖示。
6. 使用者插上電源後，面板在 30 秒內（最遲下一個輪詢週期）自動消失，無需點擊任何按鈕。
7. 使用者未插電但電量回升至解除門檻以上時，面板同樣自動消失；電量再次跌至觸發門檻以下時重新出現。
8. 選單列圖示在面板出現期間同步顯示紅色與電量，面板消失後復原。
9. 點擊選單列圖示可開啟選單並執行上述五個項目。
10. 使用者在選單中調整門檻後，選單內的門檻摘要與圖示標題立即更新，且當下應出現或應消失的面板狀態立刻反映新門檻，不需等待下一次輪詢。
11. 門檻調整後登出重登，設定值仍然保留。
12. 桌上型 Mac（無內建電池）全程不出現面板，選單列顯示「無電池資訊」。

### 介面與資料形狀

```swift
struct BatteryStatus: Equatable {
    var isBatteryPresent: Bool   // false = 桌上型 Mac
    var percent: Int?            // nil = 無法取得
    var isOnExternalPower: Bool
    var isCharging: Bool
}

/// 門檻值型別。解除門檻由觸發門檻推導，呼叫端無法分別設定兩者。
struct AlertThresholds: Equatable {
    static let minAlert = 5
    static let maxAlert = 50
    static let step = 5
    static let hysteresis = 5          // 解除門檻 = 觸發門檻 + hysteresis
    static let `default` = AlertThresholds(alertPercent: 20)

    let alertPercent: Int
    var clearPercent: Int { min(alertPercent + Self.hysteresis, 100) }

    /// 夾邊界：超出範圍時退回預設值。
    init(clamping raw: Int) {
        alertPercent = (Self.minAlert...Self.maxAlert).contains(raw) ? raw : 20
    }
}

protocol BatteryMonitoring: AnyObject {
    var onStatusChange: ((BatteryStatus) -> Void)? { get set }
    func start()
    func stop()
    func refreshNow()   // 「立即檢查」與手動重算使用
}

/// 門檻的唯一持有者。讀寫 UserDefaults 並夾邊界，不把門檻藏進其他元件。
final class ThresholdStore {
    static let defaultsKey = "alertThresholdPercent"
    var onChange: ((AlertThresholds) -> Void)?
    var current: AlertThresholds { get }
    func step(by delta: Int)   // ±5，越界時不改變
}

enum ThresholdEvaluator {
    static func isAlerting(_ status: BatteryStatus, thresholds: AlertThresholds) -> Bool
}
```

`BatteryStatus` 是監聽層與呈現層之間唯一的資料形狀。`ThresholdEvaluator` 為無狀態的純函式，門檻一律由呼叫端傳入，因此單元測試不需要建立或污染 `UserDefaults`。

`BatteryMonitoring` 的狀態來源可注入，因此單元測試能以固定的電源描述陣列驅動，而人工驗收則以啟動參數 `--simulate-battery=<百分比>` 與 `--simulate-external-power=<0|1>` 覆寫狀態來源，讓低電量情境在沒有低電量的機器上也能重現。

### 失敗模式與靜默行為

| 情況 | 行為 |
| --- | --- |
| `IOPSCopyPowerSourcesInfo` 回傳 nil 或讀不到電量 | 視為無電池資訊，選單列顯示「無電池資訊」，不出現面板。不崩潰、不重試轟炸 |
| 桌上型 Mac 無內建電池 | 同上，永久靜默 |
| `SMAppService.mainApp.register()` 回傳錯誤 | 自動改用 LaunchAgent 退路；不向使用者彈錯誤視窗（選擇項會顯示為已啟用） |
| LaunchAgent 寫入或 `launchctl bootstrap` 失敗 | 選單列選單中的「登入時開啟」維持關閉狀態；僅記錄到 `os_log`，不彈窗 |
| 使用者從「系統設定 › 登入項目」手動停用 | 下次啟動時以 `SMAppService.mainApp.status` 為準校正內部旗標，不反過來把項目重新打開 |
| App 執行期間使用者手動結束 | 下次登入依登入項設定恢復 |
| 系統進入睡眠 | 輪詢計時器在喚醒後立即補一次 `refreshNow()`，不累積過期狀態 |
| `UserDefaults` 中的門檻值超出 5–50 範圍或型別不符 | 讀取時夾邊界退回預設值 20，並記錄到 `os_log`；不崩潰、不讓面板永遠停用 |
| 門檻已達 50% 上限時再按「提高門檻」 | 選單項目停用灰色，`step(by:)` 不寫入 `UserDefaults`，不產生無意义的寫入 |
| 面板顯示中使用者按「降低門檻」到目前電量以下 | 面板維持顯示（已是顯示狀態），圖示標題同步更新 |

所有診斷訊息寫入 `os_log`（subsystem 使用 bundle id），不寫入檔案、不顯示對話框。

### 驗收條件

1. `swift build -c release` 在僅有 Command Line Tools 的環境下成功產出可執行檔。
2. 打包腳本產出 `BatteryWarning.app`，`codesign -dv` 顯示有效的 ad-hoc 簽章，`Info.plist` 含 `LSUIElement = true`。
3. 將 App 移入 `/Applications` 後啟動，Dock 無圖示，選單列出現圖示。
4. 以 `--simulate-battery=15 --simulate-external-power=0` 啟動 App，面板在 30 秒內出現在滑鼠所在螢幕的**右上角**、選單列下方，且在當下 active app（全螢幕亦同）之上方可見，同時鍵盤焦點仍留在原 app。
5. 插上電源後面板在 30 秒內消失；拔掉電源且電量低於門檻時重新出現。人工驗收時以 `--simulate-external-power=1` 重啟模擬插電。
6. 在選單中把門檻從 20% 調到 10% 再調回 20%，選單摘要與圖示標題同步更新；在顯示面板的狀態下把門檻調到高於目前電量，面板立即消失。
7. 調整門檻後登出重登，設定值保留且面板仍依新門檻運作。
8. 設定「登入時開啟」後登出重登，App 自動啟動且無啟動視窗。
9. 在無內建電池的 Mac 上，選單列顯示「無電池資訊」且無任何面板。
10. 單元測試涵蓋：預設 20% 觸發、21% 不重複觸發、25% 解除、插電即解除、桌上型 Mac、門檻夾邊界（`-5` 與 `200` 均退回 20）、`clearPercent` 恆大於 `alertPercent`、門檻調整後立即重新評估，共八種情境。

### 範圍界線

**範圍內：** 選單列 App、IOKit 電池監聽、浮動面板（右上角）、選單列選單與門檻調整、`UserDefaults` 門檻持久化、開機啟動註冊與退路、打包腳本、狀態機單元測試。

**範圍外：** 獨立設定視窗、解除門檻的獨立設定、門檻以外的任何使用者設定、通知中心推播、匯出／記錄日誌、auto-update、SwiftUI 重寫、面板大小的使用者調整、任何網路功能。

## Risks / Trade-offs

- **最高層級面板會蓋住全螢幕內容** → 使用者明確要求優先於所有 app，此為必然代價。若使用者之後反悔，僅需將 `window.level` 從 `.screenSaver` 降為 `.statusBar`，代價是全螢幕 app 會蓋住面板。
- **右上角與 macOS 通知橫幅重疊** → 面板層級高於通知，因此提醒永遠可讀，但兩者同時出現時視覺重疊。若干擾，可改為在通知橫幅位置下方讓開約 80pt。
- **門檻調到極低（5%）會讓面板長時間常駐** → 這是使用者主動選擇的結果，非缺陷。若要防呆，可在選單中於 5% 以下加入「不建議」的灰色提示文字而非硬性阻擋。
- **門檻調整後狀態需立即重算，若實作遺漏會出現最多 30 秒的延遲** → 已列入驗收條件第 6 項，調整門檻的當下即需觀察面板是否即時反應。
- **ad-hoc 簽章可能被 `SMAppService` 拒絕** → 已設計 LaunchAgent 退路，功能不打折，僅在使用者看不到「系統設定 › 登入項目」的條目。
- **最高視窗層級可能被未來 macOS 版本限制** → 若 `orderFrontRegardless` 失效，面板會被部分 app 覆蓋。降級到 `.floating` 層級即可修正，不影響其餘設計。
- **30 秒輪詢在長時間運行下有輕微耗電** → 常駐背景 App 的量級為可忽略；若需進一步降低，可在偵測到低電量且已顯示面板時延長至 60 秒。
- **`IsPresent` / `ExternalPowerSource` 欄位在部分硬體與 macOS 版本上回報不穩** → 讀取失敗時一律降級為「無電池資訊」靜默處理，絕不顯示錯誤的百分比或誤判為 0%。
- **未做公證，Gatekeeper 在其他機器上可能阻擋** → 目標為使用者自己的 Mac。若日後要分發，需補上 Developer ID 簽章與 notarization，屬本變更範圍外。

## Migration Plan

首次部署：

1. `swift build -c release`
2. 執行打包腳本產出 `build/BatteryWarning.app`
3. 將 App 複製到 `/Applications`
4. 使用者從選單列選單勾選「登入時開啟」，並視需要調整低電量提醒門檻
5. 登出重登驗證自動啟動與門檻保留

回滾：刪除 `/Applications/BatteryWarning.app` 與 `~/Library/LaunchAgents/<bundle-id>.plist`，執行 `launchctl bootout gui/$UID/<bundle-id>`。若要一併清除門檻設定，再執行 `defaults delete com.local.batterywarning`。無資料遷移。

## Open Questions

- `SMAppService.mainApp.register()` 在 ad-hoc 簽章下是否會成功，須在實機上驗證；若失敗則 LaunchAgent 為主要路徑而非退路。此項需在實作階段實測確認，不影響其餘設計。
- 面板與通知橫幅重疊的實際視覺效果需在實機上確認是否需要額外讓開距離。
- App 名稱與 bundle identifier 尚未定案。暫用 `BatteryWarning` 與 `com.local.batterywarning`，正式發佈前需更換為使用者擁有的反向網域。