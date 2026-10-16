# BatteryWarning

macOS 選單列低電量提醒 App。常駐在背景，電量低於門檻且沒插電時，用壓過所有 App 的浮動面板提醒你充電 — 並一直留著，直到你插上電源。

## 為什麼需要它

macOS 內建的低電量警告只在剩 10% 時出現一次橫幅，約 5 秒就消失，也沒有開機自動啟動的常駐監看。實際上常常在完全沒注意到的情況下繼續工作到自動關機。

這個 App 的做法：

| 你原本的痛點 | 這個 App 怎麼處理 |
| --- | --- |
| 橫幅 5 秒就消失 | 面板持續顯示，不需點任何按鈕 |
| 只在 10% 才提醒 | 預設 20% 就提醒，門檻可自己調 |
| 可能被其他視窗蓋掉 | 視窗層級設到最高，壓過全螢幕 App |
| 提醒時打斷工作 | 不搶走鍵盤焦點，你可以繼續在原 App 打字 |
| 要自己開啟 | 開機自動啟動 |
| 20% 附近反覆閃爍 | 觸發與解除門檻分開（預設 20% / 25%） |

## 需求

- macOS 13 或以上
- **建置**：只需要 Command Line Tools（`xcode-select --install`）
- **測試**：需要完整 Xcode。原因見下方〈關於測試工具鏈〉

## 安裝

```bash
git clone https://github.com/mag0929/BatteryWarning.git
cd BatteryWarning
make install                     # 建置並複製到 /Applications
```

想裝到別的位置：`make install DEST_DIR="$HOME/Applications"`。

（`~` 必須寫成 `$HOME`。Makefile 的路徑有加引號，引號內的 `~` 不會展開，直接寫 `~/Applications` 會建出一個名為 `~` 的目錄。）

只想產出 bundle、不安裝：`make app`，產物在 `build/BatteryWarning.app`。

不確定已經裝的那份是不是舊的，跑 `make check` 比對內容雜湊。

App 啟動後只會在選單列出現一個狀態圖示，**沒有 Dock 圖示、不開任何視窗**。

開機自動啟動預設是關閉的。在選單列選單裡勾選「登入時開啟」。

## 使用

### 選單列

選單列只顯示**一個固定的狀態圖示**：不顯示任何文字，也不隨電量或提醒狀態變化。點開選單才看得到電量。

選單第一行是狀態摘要：

| 狀態 | 摘要列顯示 |
| --- | --- |
| 未接電源 | `電量 63% · 使用電池` |
| 充電中 | `電量 63% · 充電中` |
| 已接電源但沒在充 | `電量 100% · 已接電源` |
| 無電池（桌上型 Mac） | `無電池資訊` |

其餘項目：

- **立即檢查** — 強制重算一次
- **低電量提醒門檻 20%** — 目前門檻（唯讀）
- **提高門檻 (+)** / **降低門檻 (−)** — 5% 到 50%，每次 5%
- **登入時開啟** — 開機自動啟動開關
- 開啟系統的電池設定
- 結束 App

### 警示面板

電量低於門檻且未接電源時，面板出現在游標所在螢幕的右上角，壓過所有 App 包括全螢幕。接上電源就自動收起。

面板固定 300×100，一直顯示到解除為止，不需點任何按鈕：

- 左側是電池圖示，依電量分四級（0–25% 一格、26–50% 兩格、51–75% 三格、76–100% 四格），充電中顯示閃電
- 右側固定兩行：40pt 的電量百分比（等寬數字，變動時不會跳動），下方是紅色三角形加「請插電充電」
- 面板可見期間電量會持續更新，不會停在剛出現時的數字
- 拖曳游標到另一台螢幕，面板會跟著過去

## 測試

### 除錯參數：不用真的等到沒電

在機器沒有低電量的情況下重現提醒：

```bash
pkill -f "BatteryWarning.app/Contents/MacOS"     # 先結束，否則新參數不會生效

# 低電量、未插電 → 面板出現
open -a /Applications/BatteryWarning.app --args \
  --simulate-battery=15 --simulate-external-power=0

# 低電量、已插電 → 不提醒（「接上電源就解除」）
open -a /Applications/BatteryWarning.app --args \
  --simulate-battery=15 --simulate-external-power=1

# 正常電量 → 不提醒
open -a /Applications/BatteryWarning.app --args \
  --simulate-battery=63 --simulate-external-power=0
```

這個參數走的是**同一套判斷與呈現邏輯**，只是把 IOKit 讀到的電量換成你指定的值。不帶參數啟動時完全走真實路徑，模擬機制不會生效。

`--simulate-battery` 和 `--simulate-external-power` 兩個參數必須同時給。

兩個參數都是**啟動時讀取一次**，執行中改變參數不會生效，要重新啟動。模擬狀態也無法表示「充電中」，所以充電圖示只能靠單元測試驗證。

### 單元測試

```bash
make test
```

62 個測試、9 個測試組，涵蓋門檻狀態機、參數持久化、IOKit 狀態解析、登入註冊、圖示分級規則、選單摘要文字。

### 直接改門檻設定測試

門檻存在 `UserDefaults`，可以繞過選單直接設值：

```bash
defaults write com.local.batterywarning alertThresholdPercent -int 30
defaults read com.local.batterywarning
defaults delete com.local.batterywarning          # 測完復原
```

超出 5–50 範圍的值會被夾回預設 20，不會讓 App 失效。

## 專案結構

```
Sources/
├── BatteryWarningKit/          核心邏輯，不含視窗程式碼
│   ├── BatteryStatus.swift             電池狀態值型別
│   ├── IOKitBatteryStatusReader.swift  IOKit 電源查詢
│   ├── BatteryMonitor.swift            變更通知 + 30 秒輪詢
│   ├── AlertThresholds.swift           門檻值型別（解除門檻由觸發門檻推導）
│   ├── ThresholdEvaluator.swift        純函式告警判定
│   ├── ThresholdStore.swift            UserDefaults 讀寫與夾邊界
│   ├── AlertCoordinator.swift          面板與下拉選單共用的單一狀態機
│   ├── BatteryIcon.swift               電量分級與圖示名稱選擇（不含 AppKit）
│   ├── MenuSummaryText.swift           下拉選單摘要文字（不含 AppKit）
│   ├── LoginItemRegistrar.swift        SMAppService + LaunchAgent 退路
│   ├── LoginItemController.swift       登入開關與狀態校正
│   └── SimulationOptions.swift         --simulate-* 參數解析
└── BatteryWarning/             AppKit 介面
    ├── main.swift                       進入點
    ├── AppDelegate.swift                組裝各元件
    ├── StatusItemController.swift       選單列圖示與下拉選單
    ├── BatteryIconLoader.swift          從 bundle 載入圖示並縮放
    ├── AlertPanelController.swift       浮動面板

Resources/                     圖示素材（深藍外框與 Light/ 淺色外框、App 圖示）
                               刻意放在 Sources/ 之外，否則 SwiftPM 會把它們
                               當成 target 的未處理來源而每次建置報警告

Tests/BatteryWarningKitTests/     62 個單元測試
scripts/build-app.sh              組出 .app 並做 ad-hoc 簽章
scripts/check-install.sh          比對已安裝的 App 與 build/，判斷是否需重裝
docs/spectra/specs/               這個 App 應該怎樣運作（永久紀錄）
docs/spectra/changes/archive/     已完成變更的歷史紀錄
```

**分層原則**：`BatteryWarningKit` 不建立任何視窗，所以核心邏輯可以直接單元測試，不需要視窗伺服器。呈現層只負責把狀態畫出來。

## 開發指令

| 指令 | 作用 |
| --- | --- |
| `make build` | Release 建置 |
| `make app` | 組出 `build/BatteryWarning.app`（含 ad-hoc 簽章） |
| `make install` | `make app` 後複製到 `/Applications`（`DEST_DIR=...` 可改位置） |
| `make check` | 比對已安裝的 App 與 `build/`，判斷是否需要重裝 |
| `make test` | 跑單元測試 |
| `make clean` | 清掉 `.build/` 與 `build/` |

`make install` 在需要時會自動改用 `sudo` 刪除舊副本，並把擁有者還給你，因此只有第一次或舊副本屬於 `root` 時才會提示密碼。

### 關於測試工具鏈

`swift build` 與打包只需要 Command Line Tools。但 Command Line Tools **沒有附 `XCTest.framework`，也沒有 `TestingMacros` 外掛**，所以 `swift test` 在 CLT 下會解析失敗。

`Makefile` 的 `test` 目標會自動加上：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

這是單一命令的環境變數，**不需要 `sudo`，也不修改任何系統設定**。直接打 `swift test` 會失敗，請用 `make test`。

## 設計說明

這個 App 用 [Spectra](https://github.com/kaochenlong/spectra-app) 做規格驅動開發（SDD）。`docs/spectra/specs/` 記錄的是「這個 App 應該怎樣運作」，共 2 份規格、19 條需求、58 個情境。每次改動都走同一個迴圈：

```
$spectra-discuss  想清楚要改什麼
$spectra-propose  產生變更計畫與規格增修
$spectra-apply    照 tasks.md 實作
$spectra-verify   驗收實作是否符合規格
$spectra-archive  封存，規格合併回 specs/
```

完成的變更連同當時的提案、設計與任務清單一起移入 `docs/spectra/changes/archive/`，保留為歷史紀錄。

## 已知限制

- **只建置了 arm64 版本**，在 Intel Mac 上尚未測試。
- **未做公證（notarization）**，從其他機器下載會被 Gatekeeper 阻擋，需右鍵「打開」或 `xattr -d com.apple.quarantine`。
- **bundle identifier 是 `com.local.batterywarning`**，正式發佈前需換成自有網域。
- **面板會蓋住全螢幕內容**。這是「優先於所有 App」的必然代價。要改成全螢幕時自動讓路，把 `AlertPanelController.swift` 的視窗層級從 `.screenSaver` 降到 `.statusBar`。
- **右上角會與 macOS 通知橫幅重疊**。面板層級較高所以不會被遮住，但視覺上會擠在一起。
- 30 秒輪詢在長時間運行下有輕微耗電，常駐背景的量級可忽略。
- **SF Symbols 的名稱失效時會靜默降級**。`NSImage(systemSymbolName:)` 遇到不認識的名稱會回傳 `nil` 且不作任何回報，因此系統換代把某個符號改名後，App 少掉的是那個圖示而不是報錯：
  - 選單列的七個項目圖示（`StatusItemController.symbol(_:)`）
  - 面板「請插電充電」前的紅色警告三角形（`AlertPanelController`）
  - 找不到自製電池圖示時的退路符號（`BatteryIconLoader.fallback`）

  Apple 至今未移除過任何 SF Symbol，此風險目前只在系統更新後才可能浮現。三處的程式碼註解都有記錄；若要實質保護，可在 DEBUG 版加上啟動時斷言，而非新增測試 target。

## License

尚未授權。