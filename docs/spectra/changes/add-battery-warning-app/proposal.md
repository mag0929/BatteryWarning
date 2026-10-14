## Why

macOS 內建的低電量警告只在電量剩 10% 時出現一次橫幅，橫幅約 5 秒就自動消失，也沒有開機自動啟動的常駐監看。使用者實際上常常在完全沒注意到警告的情況下繼續工作到自動關機，因此需要一個常駐在背景、自己會主動提醒的 App。

## What Changes

- 新增一個常駐 macOS 選單列的原生 App（Swift + AppKit），開機後自動在背景啟動，不需要使用者手動開啟。
- 新增低電量監看：當電量降到門檻以下且未接上電源時，自動顯示提醒面板。
- 提醒面板以最高視窗層級顯示在滑鼠所在螢幕的右上角，壓過當下 active app 的所有視窗（含全螢幕 app），且不會搶走鍵盤焦點。
- 面板持續顯示直到使用者接上電源（或電量回升到解除門檻以上），全程不需點擊任何按鈕。
- 新增門檻設定：使用者可在選單列下拉選單內直接調整低電量提醒門檻（5%–50%，每次 5%），設定值持久化保存。
- 新增選單列狀態顯示與下拉選單（目前電量摘要、立即檢查、開啟系統電池設定、開機啟動開關、結束 App）。
- 新增開機啟動註冊：優先使用系統提供的登入項目機制，失敗時自動退回 LaunchAgent，使用者可在「系統設定 › 一般 › 登入項目」自行檢視與關閉。
- 新增打包流程：以 SwiftPM 建置並產出可直接安裝的 `.app`。

## Capabilities

### New Capabilities

- `battery-alert`: 電量監看與低電量提醒 — 包含門檻判定、右上角浮動面板的顯示與自動收起、面板必須壓過所有 app 且不搶焦點的行為、選單列電量狀態顯示、門檻的調整與持久化、無電池裝置上不提示的行為。
- `start-at-login`: 開機自動啟動 — 包含登入後自動啟動且不顯示任何啟動視窗、使用者可在選單列開關控制、系統登入項目機制失敗時的自動退路。

### Modified Capabilities

無。本次是本專案的第一個能力，沒有任何既有規格的行為需要變更。

## Impact

- **新增專案結構**：Swift Package Manager 套件（`Package.swift` 與 `Sources/` 測試目標），以及產出 `.app` 的打包腳本。目前儲存庫除 `docs/` 外沒有任何程式碼。
- **新增 App 骨架**：`NSApplication` 啟動流程、`NSStatusItem` 選單列項目、`Info.plist`（需含 `LSUIElement = true` 使 App 不出現在 Dock）。
- **新增系統 API 使用**：IOKit 電源來源查詢與變更通知（`IOPSCopyPowerSourcesInfo`、`IOPSNotificationCreateRunLoopSource`）、`SMAppService` 登入項目註冊、`launchctl` 作為註冊失敗時的退路。
- **新增持久化**：`UserDefaults` 用於保存低電量提醒門檻；選單列選單是唯一的寫入入口。
- **檔案系統副作用**：註冊退路會寫入 `~/Library/LaunchAgents/<bundle-id>.plist`。
- **建置環境限制**：本機僅有 Command Line Tools（`xcode-select -p` 指向 `/Library/Developer/CommandLineTools`），`xcodebuild` 不可用；未安裝 Rust 與 Node。建置流程不得依賴完整 Xcode 或需要 `sudo` 的設定變更。
- **無既有程式碼需修改**，亦無對外 API 或既有使用者的行為受影響。
