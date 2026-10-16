> **本次 ingest 的變更紀錄（2026-10-15）**
>
> 使用者提供 `StatusIcon.jpeg` 與 `AppIcon.jpeg`，並要求選單列不再顯示任何文字。因此本次更新**取代**以下已存在的決定與工作：
>
> - design.md「選單列與面板共用同一組圖示對應」→ 由「面板依電量選圖示，選單列固定使用單一狀態圖示」取代。
> - design.md「深色背景使用淺色外框變體」中「面板恆為深色」的假設 → 實測更正為面板材質隨系統外觀自適應。
> - 原任務 4.1（已完成）讓選單列顯示隨電量變化的電池圖示與文字。此行為已被取代，保留 `[x]` 記錄不變，改由新的 4.4 補償任務移除文字並改用固定圖示。
> - 原任務 3.3 的敘述含「與選單列顯示同一顆」，已隨上述取代而移除。
>
> 已完成的 1.1、2.1、2.2、3.1、3.2、4.1、4.2、4.3 之描述與來源檔案紀錄一律不變動。

## 1. 圖示資源處理

- [x] 1.1 將 5 個深藍外框圖示裁掉透明邊框並改名，使畫布等於圖案邊框。完成後 `Sources/BatteryWarning/Resources/` 下有 battery-charging.png、battery-25.png、battery-50.png、battery-75.png、battery-100.png，每張畫布為 60×106（裁切前畫布 340×120、圖案 60×106 位於 (140,7)-(200,113)），內部填色維持 #63CA49 / #E91634 / #E71232 / #FFA500 / #89E20B，外框維持 #323456。驗證：以 Python/PIL 逐檔印出 `size` 與 alpha 不透明邊界 `getbbox()`，兩者須相等；再印出填色與外框色值，與上列數值逐一比對相符。

- [x] 1.2 [after: 1.1] 建立 `Sources/BatteryWarning/Resources/Light/` 並放入 5 個淺色外框圖示，命名為 battery-charging-light.png、battery-25-light.png、battery-50-light.png、battery-75-light.png、battery-100-light.png；外框（含電池頂部凸頭）為 #FFFFFF，畫布與 1.1 相同，內部填色與 1.1 完全一致。驗證：以 Python/PIL 逐檔比對 1.1 的對應檔，畫布尺寸相同、內部填色色值相同、外框像素由 #323456 變為 #FFFFFF。**此組素材需由使用者提供，未提供前本任務無法完成**；面板材質實測會隨系統外觀自適應，淺色系統外觀下對比充足，僅深色系統外觀會受影響。

- [x] 1.3 由 `Sources/BatteryWarning/Resources/StatusIcon.jpeg` 產生去背剪影 `status-icon.png`：以反向亮度推得不透明度（實測主體最高亮度 255、背景約 89），輸出黑色 RGB 加 alpha 的 PNG，並標記為樣板圖供系統自動反白；畫布裁切至不透明邊界。對應 design.md「選單列圖示由原始素材去背成剪影」。驗證：產出的 PNG 具備 alpha 通道且四角 alpha 為 0；放入選單列後在淺色與深色系統外觀下各截圖一次，目視確認輪廓清晰、無深灰色方塊殘留。

## 2. 圖示選擇規則（BatteryWarningKit）

- [x] 2.1 在 `BatteryWarningKit` 新增 `BatteryIcon` 型別與選擇函式，輸入 `BatteryStatus` 與系統外觀（淺色／深色），輸出圖示資源名稱；充電中優先於電量分級；無電池時輸出 nil；電量落在分級範圍外時取最近的分級。面板與選單列共用同一個選擇函式，不得各自實作一份規則——對應 design.md「圖示選擇規則放進 BatteryWarningKit」與「選單列與面板共用同一組圖示對應」，並維持 `MenuBarDisplay.swift` 既有的分層理由（不 import AppKit，規則可被直接測試）。驗證：`swift build` 通過，且 `BatteryIcon.swift` 不含任何 `import AppKit`；`git diff --stat` 顯示本任務只新增 `BatteryIcon.swift`，未改動 `BatteryStatus` 的欄位，對應 design.md「介面與資料形狀」中該欄位維持不變的約束。

- [x] 2.2 [after: 2.1] 新增 `Tests/BatteryWarningKitTests/BatteryIconTests.swift`，滿足 spec「Battery icon reflects battery level and charging state」的每一個場景與例子表：0% 與 25% → 最低階圖示、26% 與 50% → 第二階、51% 與 75% → 第三階、76% 與 100% → 第四階、充電中 → 充電圖示、無電池 → nil、超出範圍 → 最近分級、淺色與深色外觀各自對應到正確的變體檔名。驗證：`swift test --filter BatteryIconTests` 全數通過；沿用 `MenuBarDisplayTests.swift` 的 `@Suite` / `@Test` / `#expect` 寫法，並以 `// Scenario: <場景名稱>` 註解對應 spec 場景。

## 3. 警告面板

- [x] 3.1 修正面板內容更新時無法取得電量標籤的缺陷，使面板顯示當下電量百分比並在電量變化時更新，滿足 spec「Alert panel reports the current battery level」。對應 design.md「修正面板電量數字從未顯示的缺陷」——改為持有標籤的直接參考，取代目前走訪容器直接子視圖並轉型為 `NSTextField` 的作法。驗證：以 `--simulate-battery 15 --simulate-external-power 0` 啟動，面板顯示 `15%`；改以 `--simulate-battery 12 --simulate-external-power 0` 啟動，顯示 `12%`。

- [x] 3.2 [after: 3.1] 將面板版面改為 300×100 固定寬度，內容維持兩行：圖示 44pt、電量數字 34pt semibold 等寬數字、說明文字 15pt，整組置中且兩側留白對稱。對應 design.md「面板維持兩行資訊，只放大版面」與「面板寬度固定 300pt，不隨文字收縮」。驗證：實測面板 frame 為 300×100；分別以 `--simulate-battery 5` 與 `--simulate-battery 100` 啟動，量測圖示加文字整組的水平中心與面板中心一致。

- [x] 3.3 [after: 3.2] 面板改為載入 `Sources/BatteryWarning/Resources/` 的自製電池圖示（對應 design.md「圖示以裁切後的畫布載入」與「圖示尺寸由使用面指定」），圖示高度 64pt 且維持素材長寬比 60:106 不壓扁，並依當下電量與充電狀態更換。圖示變體依系統外觀選擇：淺色用深藍外框、深色用 `Resources/Light/` 淺色外框。資源檔缺失時退回 SF Symbol `battery.25` 而非留空，電量超出範圍時套用最近分級，兩者皆落實 design.md「失敗模式與靜默行為」。滿足 spec「Alert panel renders a battery icon for the observed level」的每個場景與例子表。驗證：以 `--simulate-battery 15` 與 `--simulate-battery 45` 啟動，面板圖示不同且分別為 1 格與 2 格；暫時移走對應的 `Resources/Light/` 檔案後啟動，面板退回 `battery.25` 且不崩潰，放回後恢復自製圖示。

- [x] 3.4 [after: 3.3] 在面板「請插電充電」前加上 SF Symbol 警告標記，形成「警告標記 + 文字」的水平堆疊。對應 design.md「面板的充電提示前加上警告標記」，並滿足 spec「Charging prompt is preceded by a warning marker」。驗證：實作前先於執行期確認所用符號名稱存在（`NSImage(systemSymbolName:)` 對不存在的名稱回傳 nil 且不報錯）；啟動後面板可見標記位於提示文字左側。

## 4. 選單列與下拉選單

- [x] 4.1 選單列在電量文字旁顯示電池圖示，依電量與充電狀態更換，淺色系統外觀使用深藍外框變體、深色系統外觀使用 `Light/` 變體；無電池時不顯示圖示。既有文字語意不得改變——低電量時仍顯示「請插電充電」且仍為紅色。滿足 spec「Battery icon reflects battery level and charging state」，且不修改該條既有的警告色與充電提示要求。驗證：以 `--simulate-battery 15`、`45`、`80` 分別搭配 `--simulate-external-power 0` 啟動，圖示依序為不同顆；`swift test` 全數通過以確認 `MenuBarDisplayTests` 的文字斷言未受影響。**注意**：模擬參數無法產生充電狀態（`SimulationOptions.simulatedStatus` 固定回傳 `isCharging: false`），充電圖示與系統外觀切換以 2.2 的單元測試驗證。

- [x] 4.2 [after: 4.1] 修正下拉選單中「提高門檻」與「降低門檻」的符號方向，標題改為「提高門檻 (+)」「降低門檻 (−)」，與 `AlertThresholds.stepping(by:)` 的實際行為一致（提高使門檻數值上升）。對應 design.md「修正提高／降低門檻的符號」，且不動 `battery-alert` 規格中門檻調整的步進值 5 與範圍 5–50。驗證：門檻 20 時開啟選單按「提高門檻」，摘要列顯示 25%；再按「降低門檻」，顯示 15%。

- [x] 4.3 [after: 4.2] 下拉選單每一項加上 SF Symbol 圖示，包含唯讀的狀態摘要列；項目順序與分隔線配置維持不變。對應 design.md「下拉選單每項加上 SF Symbol 圖示」。驗證：開啟選單逐項目視確認皆有圖示，且狀態摘要列文字仍為「電量 X% · <電源狀態>」。

- [x] 4.4 [after: 4.1, 1.3] 選單列改為只顯示固定的 `status-icon` 剪影，不顯示任何文字，也不隨電量變化。對應 design.md「面板依電量選圖示，選單列固定使用單一狀態圖示」，並滿足 spec「Menu bar always reports current battery status」（改寫後）的每一個場景。本任務取代 4.1 所建立的「隨電量變化的電池圖示 + 文字」行為。驗證：以 `--simulate-battery 15`、`45`、`80` 分別搭配 `--simulate-external-power 0` 啟動，選單列圖示三者完全相同且無任何文字；系統切換深淺兩種外觀時圖示均清晰可見。

- [x] 4.5 [after: 4.4] `MenuBarDisplayBuilder` 改為回傳空標題與中性樣式，選單列因此不渲染任何文字；`chargingPrompt` 與 `noBatteryText` 的顯示責任改由下拉選單的狀態摘要列承擔。對應 design.md「介面與資料形狀」中 `MenuBarDisplay` 的變更，並滿足 spec「Battery level is reported when the menu opens」與「Machines without a battery are handled silently」的「Desktop Mac with no battery」場景。驗證：`swift test` 全數通過；`MenuBarDisplayTests` 中斷言選單列含充電提示或百分比的案例改為斷言標題為空字串；實機開啟下拉選單，摘要列仍顯示「電量 X% · <電源狀態>」，無電池時顯示「無電池資訊」。

## 5. 打包

- [x] 5.1 [after: 1.3] 更新 `scripts/build-app.sh`：將 `Resources/` 與 `Resources/Light/` 複製到 `build/BatteryWarning.app/Contents/Resources/`（程式端以 `Bundle.main` 載入），並由 `Resources/AppIcon.jpeg` 產生 `.icns` 寫入 App bundle。App 圖示素材實測圓角之外為不透明白色（角落平均亮度 255），產生 `.icns` 前須先把圓角方塊以外轉為透明，否則 Finder 會顯示白色方框。對應 design.md「打包沿用 build-app.sh，不動 Package.swift」與「App 圖示由原始素材產生 .icns」。圖示產生失敗時腳本不應中斷，仍輸出可執行但無圖示的 App 並記錄警告。驗證：執行 `scripts/build-app.sh` 後，`ls build/BatteryWarning.app/Contents/Resources/` 可看到電池圖示、`status-icon.png` 與 `Light/` 子資料夾，且 bundle 內存在 `.icns`；`git diff Package.swift` 為空。

## 6. 驗收

- [x] 6.1 [after: 3.4, 4.5, 5.1] 依 design.md「使用者可觀察到的行為」逐條實測並記錄結果，依 design.md「驗收條件」確認 12 條全部通過，並確認「範圍界線」列出的項目確實未被實作（未新增 `BatteryStatus` 欄位、未實作動畫、未修改已封存的 `2026-10-14-add-battery-warning-app/`、未改變面板視窗層級與位置追蹤、選單列不顯示電量）。驗證：逐條記錄實測結果，且執行 `spectra analyze polish-interfaces` 確認無 Critical 與 Warning。

## 7. Review 修正（`$spectra-review polish-interfaces` 產出）

- [x] 7.1 修正面板可見期間電量數字停在舊值的缺陷。`AlertCoordinator` 目前只在狀態轉換時呼叫 `presentAlert`，面板出現後數值就不再更新，違反本次新增的規格場景「Panel follows a change in the observed level」。既有測試 `testPresentingOnlyOnTransitions` 與 `testRaisingThresholdAboveCurrentLevelKeepsPanel` 刻意斷言「只在轉換時 present」，因此不可改動呼叫條件，改為在 `AlertPresenting` 新增只更新內容的 `refreshAlertContent(for:)`，由協調器在「仍在提醒但狀態有變」時呼叫。驗證：新增測試斷言電量從 15% 變 12% 時 `refreshAlertContent` 被呼叫且 `presentAlert` 不再被呼叫；既有兩個測試仍通過。

- [x] 7.2 清除選單列改為純圖示後留下的痕跡：修正 `StatusItemController` 類別註解（仍宣稱呈現電量與提醒狀態）、移除從未被讀取的 `alerting` 屬性、讓固定的狀態列圖示只設定一次而非每次狀態更新都重新解碼 PNG。驗證：`grep` 確認 `alerting` 無殘留、`swift test` 全數通過。

- [x] 7.3 整理 `BatteryIconLoader`：移除只會產生 `<base>-light-light` 的 fallback 候選、抽出重複的等比縮放邏輯供兩處共用、改由實際載入的影像尺寸決定面板圖示的長寬比而非硬寫 `60.0 / 106.0`。驗證：`swift test` 全數通過，且以兩種外觀實際啟動確認面板圖示比例正確。
