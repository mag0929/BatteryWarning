## Summary

重新設計 App 的三個使用者可見畫面（警告面板、選單列項目、下拉選單），修正兩個在檢視過程中發現的既有缺陷，為 App 與選單列提供自製圖示，並為面板顯示內容新增規格條文。

## Motivation

實際使用後回報介面不夠顯眼。在檢視畫面呈現方式的過程中，同時發現兩個與外觀無關的缺陷：

**1. 警告面板的電量百分比從未顯示過。** `AlertPanelController` 在更新內容時，於面板容器的直接子視圖中尋找文字欄並轉型為 `NSTextField`，但兩個標籤實際是被加入 `NSStackView` 內的，搜尋結果永遠為空。面板自釋出以來一直只顯示圖示與「請插電充電」，本應顯示數字的位置是空白的。這是提醒功能最關鍵的資訊，卻一直是空的。

**2. 下拉選單「提高門檻」與「降低門檻」的符號方向相反。** `AlertThresholds.stepping(by:)` 的實作是 `alertPercent + delta`，提高門檻呼叫的是 `+5`，因此門檻數值上升；但選單標題寫成「提高門檻 (−)」「降低門檻 (+)」。介面顯示的方向與實際行為相反。

外觀方面的問題：

- 面板固定 260×76，內容靠左排列，右側留下約 150pt 空白，整體看起來鬆散而非一個主體。
- 面板圖示固定為 SF Symbol `battery.25`，不隨電量變動；面板出現時的電量可從 5% 到 49%（門檻最高可調至 50），因此固定圖示與實際電量無關。
- 選單列只有文字百分比，沒有圖示。
- 下拉選單每一項都沒有圖示。

選單列的呈現方式在使用者看過選單列圖示後決定改變：選單列只保留一個固定的 App 狀態圖示，不再顯示任何文字。電量與提醒狀態改由面板與選單本身呈現，選單列只負責讓使用者隨時找到 App 並開啟選單。此變更推翻既有規格中「選單列顯示電量並帶充電提示」的要求，因此規格需一併修改。

使用者另外提供了 App 圖示與選單列圖示的原始素材，以及一組自製電池圖示（充電中／25%／50%／75%／100%）。

## Proposed Solution

- 修正面板內容更新的標籤尋找方式，讓電量百分比實際顯示並隨電量更新。
- 面板放大為 300×100，內容整組置中，圖示 64pt、電量數字 40pt semibold 等寬數字、說明文字 18pt。
- 面板改用使用者提供的自製圖示，圖示選擇規則以純函式形式置於 `BatteryWarningKit`，面板與選單共用同一份規則。
- 在「請插電充電」前加上警告標記，讓提示讀起來是警語而非建議。
- 選單列改為只顯示一個固定的 App 狀態圖示，不顯示任何文字。
- 由 `StatusIcon` 原始素材產生去背的剪影版本供選單列使用，該版本為樣板圖，會隨系統淺色／深色外觀自動反白。
- 以 `AppIcon` 原始素材產生 `.icns` 並寫入 App bundle。
- 下拉選單每一項加上 SF Symbol 圖示。
- 修正提高／降低門檻的符號方向，使選單標題與實際行為一致。
- 修改 `battery-alert` 中「Menu bar always reports current battery status」與「Machines without a battery are handled silently」兩條既有需求，使選單列不再負擔顯示文字的責任。

## Alternatives Considered

- **面板改為淺色背景**：面板材質 `.hudWindow` 實測在淺色系統外觀下已渲染為淺色，深藍外框對比足夠，無需變更材質。
- **以電量環取代數字**：低電量時「差多少」是使用者當下最需要的資訊，電量環的視覺衝擊不如直接顯示數字。
- **執行時掃描 alpha 通道裁切圖示透明邊框**：可行且不需改動原始素材，但每次啟動都需像素掃描，且裁切邏輯會與圖示選擇規則混在 AppKit 層。離線裁切一次可讓載入路徑保持單純。
- **使用 `Package.swift` 的 `resources:` 機制打包圖示**：會產生資源 bundle，但打包腳本只複製單一執行檔，bundle 會被遺留，腳本仍需修改。沿用既有腳本只多一行複製。
- **選單列保留文字，只替換圖示**：可完全不必動規格，但使用者明確表示不要在選單列顯示任何文字。

## Impact

- Affected specs: battery-alert（修改 2 條既有需求、重新命名 1 條、新增 2 條）
- Affected code:
  - Modified:
    - `Sources/BatteryWarning/AlertPanelController.swift`
    - `Sources/BatteryWarning/StatusItemController.swift`
    - `scripts/build-app.sh`
  - New:
    - `Sources/BatteryWarningKit/BatteryIcon.swift`
    - `Sources/BatteryWarning/BatteryIconLoader.swift`
    - `Tests/BatteryWarningKitTests/BatteryIconTests.swift`
    - `Sources/BatteryWarning/Resources/battery-charging.png`
    - `Sources/BatteryWarning/Resources/battery-25.png`
    - `Sources/BatteryWarning/Resources/battery-50.png`
    - `Sources/BatteryWarning/Resources/battery-75.png`
    - `Sources/BatteryWarning/Resources/battery-100.png`
    - `Sources/BatteryWarning/Resources/Light/battery-charging-light.png`
    - `Sources/BatteryWarning/Resources/Light/battery-25-light.png`
    - `Sources/BatteryWarning/Resources/Light/battery-50-light.png`
    - `Sources/BatteryWarning/Resources/Light/battery-75-light.png`
    - `Sources/BatteryWarning/Resources/Light/battery-100-light.png`
    - `Sources/BatteryWarning/Resources/status-icon.png`
  - Removed: none
