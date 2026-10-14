## 1. 專案骨架與打包流程

- [x] 1.1 建立 SwiftPM executable target 與打包腳本，讓 `swift build -c release` 與打包腳本都能產出可執行的 App，全程不需要完整 Xcode 或 `sudo`。對應 design.md 決定「採用 Swift + AppKit 選單列 App」與「使用 SwiftPM 搭配打包腳本，不依賴完整 Xcode」。驗證：`swift build -c release` 成功；打包腳本產出 `build/BatteryWarning.app`，`codesign -dv build/BatteryWarning.app` 顯示有效的 ad-hoc 簽章。

- [x] 1.2 讓 App 以 `LSUIElement` 啟動並建立 `NSStatusItem`，實作需求「App runs without a Dock presence or main window」：啟動後只有選單列項目，Dock 無圖示、不開任何主視窗或對話框。對應 design.md 決定「採用 Swift + AppKit 選單列 App」。驗證：`plutil -p build/BatteryWarning.app/Contents/Info.plist` 中 `LSUIElement` 為 `1`；實機啟動後 Dock 無圖示且未開啟任何視窗。

## 2. 電池監看

- [x] 2.1 實作 `BatteryStatus` 值型別與 `BatteryMonitoring`，用 IOKit 電源來源查詢搭配 run loop 變更通知（公開 API 為 `IOPSNotificationCreateRunLoopSource(callback, context)`，無型別過濾），加上 30 秒輪詢與睡眠喚醒後的立即補讀，滿足需求「Continuous battery state monitoring」。同時讓狀態來源可注入，並加入僅在帶入 `--simulate-battery=<百分比>`、`--simulate-external-power=<0|1>` 時生效的覆寫路徑（覆寫時停用 IOKit 通知與輪詢，但沿用同一套判斷與呈現邏輯）。對應 design.md 決定「以 IOKit 事件監聽搭配 30 秒輪詢保險」與「內建僅限除錯的狀態覆寫以支援人工驗收」。驗證：`make test` 中 `testReadsCurrentCapacityAndPowerFlags`（注入固定電源描述陣列）與 `testRefreshesAfterWake` 通過；`build/BatteryWarning.app/Contents/MacOS/BatteryWarning --simulate-battery=15 --simulate-external-power=0` 啟動後選單列顯示 15%。

- [x] 2.2 讓讀不到電池或無內建電池的狀態全程靜默，滿足需求「Machines without a battery are handled silently」與「Diagnostic failures are silent to the user」：無電池時永不啟動提醒、選單列顯示無電池資訊，讀取失敗只寫入系統日誌、不彈任何對話框、不崩潰。驗證：`make test` 中 `testAbsentBatteryNeverActivatesAlert` 與 `testReadFailureIsNotSurfaced` 通過；實機上確認讀取失敗情境未出現任何對話框。

## 3. 門檻狀態機

- [x] 3.1 實作 `AlertThresholds` 值型別與純函式 `ThresholdEvaluator`，讓觸發門檻、解除門檻（觸發 + 5 個百分點、預設 20）與「接上電源即解除、不要求真的在充電」集中在一處，滿足需求「Alert activation uses a clear threshold above the trigger threshold」與「External power connection clears the alert regardless of charging state」。對應 design.md 決定「門檻由值型別傳入判斷器，不在判斷器內讀取 UserDefaults」、「解除門檻由觸發門檻推導，不獨立設定」、「以「已接上電源」而非「充電中」作為解除條件」。驗證：`make test` 中 `testDefaultThresholdTransitions`（覆蓋 design.md 對照表的 6 組轉移）、`testHysteresisBandKeepsAlertActive`（19→21 不解除）、`testExternalPowerWithoutChargingClearsAlert` 通過，且判斷器不需建立 `UserDefaults` 即可測試。

- [x] 3.2 實作 `ThresholdStore`（封裝 `UserDefaults` 讀寫、5–50 範圍夾邊界、型別不符時退回預設 20、越界時不寫入），滿足需求「Alert threshold is persisted across app restarts」。驗證：`make test` 中 `testOutOfRangeStoredValueFallsBackToDefault`（分別餵入 200 與 -5）、`testNonIntegerStoredValueFallsBackToDefault`、`testStepAtBoundsDoesNotWrite` 通過；實機上調到 30 後結束 App 重開，選單摘要顯示 30。

## 4. 提醒面板

- [x] 4.1 實作最高層級的 `NSPanel`（`.nonactivatingPanel`、`canBecomeKey = false`、`.screenSaver` 視窗層級、`canJoinAllSpaces` + `fullScreenAuxiliary`），讓面板壓過所有 app 且不搶走鍵盤焦點，滿足需求「Alert panel is presented above all applications」。對應 design.md 決定「提示使用最高層級的 NSPanel，且成為 non-activating panel」。驗證：以 `--simulate-battery=15` 啟動後在全螢幕 app 內可見面板；在前台 App 的文字欄持續輸入，文字仍出現在該欄位且該 App 仍是鍵盤焦點擁有者。

- [x] 4.2 讓面板定位在滑鼠所在螢幕的右上角、上緣避開選單列高度，滿足需求「Alert panel follows the display under the pointer」。對應 design.md 決定「面板位置釘在滑鼠所在螢幕的右上角」。驗證：雙螢幕環境下以 `--simulate-battery=15` 啟動並把游標移到第二台，面板出現在第二台且未覆蓋該螢幕的時鐘；面板顯示期間把游標移到另一台，面板跟著移動。

- [x] 4.3 讓面板隨門檻變化自動出現與消失，不需任何使用者操作，滿足需求「Alert panel is dismissed automatically without user interaction」。門檻一變動即以冷啟動重新評估，不沿用先前的警告狀態。驗證：以 `--simulate-battery=15 --simulate-external-power=0` 啟動時面板出現；改以 `--simulate-external-power=1` 啟動時面板不出現；面板顯示期間於選單把門檻由 20% 降到 10%（低於目前電量 15%），面板立即消失（不需等待 30 秒輪詢）；面板隱藏期間把門檻調回 20%（高於目前電量），面板立即出現。

## 5. 選單列

- [x] 5.1 讓 `NSStatusItem` 全程顯示目前電量、提醒期間轉為警示色並附充電提示，且面板與選單列讀同一組門檻、同一個狀態機，滿足需求「Menu bar always reports current battery status」。對應 design.md 決定「面板與選單列共用單一狀態機，且共用同一組門檻」。驗證：以 `--simulate-battery=15 --simulate-external-power=0` 啟動時圖示顯示 15% 且轉為警示色，與面板同時出現；改以 `--simulate-external-power=1` 啟動時圖示與面板在同一次更新中復原。

- [x] 5.2 實作下拉選單（電量摘要、立即檢查、開啟系統電池設定、結束）與門檻調整項目（摘要列 + 提高／降低各 5%、選單開啟時依上下限停用對應項目），滿足需求「User can adjust the alert threshold from the menu bar menu」。對應 design.md 決定「提醒門檻可由使用者在選單列下拉選單調整」與「選單列圖示與下拉選單」。驗證：從選單把門檻由 20 調到 25 再調到 15，摘要列與圖示標題同步更新；門檻為 50 時「提高門檻」呈灰色且按下後設定值仍為 50；門檻為 5 時「降低門檻」呈灰色。

## 6. 開機啟動

- [x] 6.1 實作登入項目註冊：先呼叫 `SMAppService.mainApp.register()`，失敗時自動改寫 `~/Library/LaunchAgents/<bundle-id>.plist` 並以 `launchctl bootstrap` 載入，滿足需求「Login item registration falls back when the primary mechanism is rejected」。對應 design.md 決定「開機啟動使用 SMAppService，失敗時退回 LaunchAgent」。驗證：`make test` 中 `testFallsBackToLaunchAgentWhenPrimaryFails`（注入失敗的註冊結果）確認 plist 被寫入且仍回報啟用；實機上登出重登後 App 自動啟動且無啟動視窗。

- [x] 6.2 實作選單列的「登入時開啟」開關、啟動時以實際註冊狀態校正內部旗標、以及失敗只寫日誌不彈窗，滿足需求「User controls launch at login from the menu bar menu」、「App starts automatically after login when enabled」、「Actual registration state is the source of truth at startup」與「Registration failures are reported only through the toggle and the system log」。驗證：`make test` 中 `testReconcileRespectsExternalDisable`（實際已停用但內部為啟用時，校正後為停用且不重新註冊）通過；實機上到「系統設定 › 一般 › 登入項目」停用後重開 App，選單項目呈未勾選；兩種註冊方式都失敗時選單維持未勾選且無對話框。

## 7. 整合驗收

- [x] 7.1 依 design.md 的 Implementation Contract 逐節確認實作與規格一致，涵蓋「使用者可觀察到的行為」、「介面與資料形狀」、「失敗模式與靜默行為」與「範圍界線」四節（低電量情境以 `--simulate-battery` 系列啟動參數重現）。驗證：逐項記錄 design.md 驗收條件第 3 至第 10 條的實測結果，並確認「範圍界線」列出的範圍外項目確實未被實作；執行 `spectra analyze add-battery-warning-app` 確認無 Critical 與 Warning。
