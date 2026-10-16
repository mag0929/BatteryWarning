## Context

App 已可正常運作，本變更不新增功能，只處理三個使用者可見畫面的視覺與兩個既有缺陷。

本次討論中實測確認的現況（非假設）：

| 項目 | 現況 | 證據 |
| --- | --- | --- |
| 警告面板的電量數字 | **從未顯示過** | `AlertPanelController.updateContent` 在 `container.subviews` 中尋找文字欄，但兩個 `NSTextField` 實際放在 `NSStackView` 內，`compactMap { $0 as? NSTextField }` 永遠得到空陣列 |
| 面板圖示 | 固定 `battery.25`，不隨電量變 | `AlertPanelController.swift:117` |
| 面板版面 | 固定 260×76、內容靠左，數字位置留白約 150pt | `AlertPanelController.swift:21,137-149` |
| 提高／降低門檻的符號 | **(+)/(−) 寫反** | `AlertThresholds.stepping(by:)` 計算 `alertPercent + delta`；`raiseThreshold` 傳 `+5`、`lowerThreshold` 傳 `-5`，但標題寫成「提高門檻 (−)」「降低門檻 (+)」 |
| 選單列圖示 | 無圖示，只有文字百分比 | `StatusItemController.render()` 只設定 `attributedTitle` |
| 圖示資源打包 | `BatteryWarning` target 未宣告任何 `resources:`；`build-app.sh` 只複製執行檔 | `Package.swift:21-25`、`build-app.sh:27` |
| `Contents/Resources` | 打包腳本已建立此目錄，目前為空 | `build-app.sh:26` |

自製圖示（使用者提供，5 檔）實測結果：

| 檔案 | 內容 | 填色 | 畫布 | 圖案範圍 |
| --- | --- | --- | --- | --- |
| `Code_Generated_Image_0.png` | 綠色閃電（充電中） | `#63CA49` | 340×120 | (140,7)-(200,113) = 60×106 |
| `Code_Generated_Image_1.png` | 紅 1 格 | `#E91634` | 340×120 | 同上 |
| `Code_Generated_Image_2.png` | 紅 2 格 | `#E71232` | 340×120 | 同上 |
| `Code_Generated_Image_3.png` | 橘 3 格 | `#FFA500` | 340×120 | 同上 |
| `Code_Generated_Image_4.png` | 綠 4 格 | `#89E20B` | 340×120 | 同上 |

外框（包含頂部凸頭）統一為 `#323456` 深藍，約 1734 像素／檔。

約束：

- 面板為 `.hudWindow` 深色材質，恆為深色背景。
- 選單列背景隨系統外觀（淺色／深色）變動。
- 圖示解析度足夠：圖案 106px 高，面板 44pt、選單列 18pt，在 Retina 上皆不需補 @2x。
- 封存的 `2026-10-14-add-battery-warning-app/design.md:91-92,191` 記錄了同樣寫反的 (+)/(−)，屬歷史紀錄，本次不回頭修改。

## Goals / Non-Goals

**Goals:**

- 警告面板實際顯示目前電量百分比。
- 警告面板放大並重新排版，在多 App 並存時能被一眼看見。
- 警告面板在「請插電充電」前加上警告標記。
- 下拉選單每一項加上 SF Symbol 圖示。
- App bundle 使用使用者提供的 App 圖示。
- 選單列只顯示一個固定的 App 狀態圖示，不顯示任何文字。**此項取代先前「選單列在電量文字旁加上圖示、文字語意全部保留」的決定**，因為使用者明確要求選單列不出現任何文字。
- 為 `battery-alert` 修改 2 條既有需求（選單列呈現方式、無電池時的報告位置），並新增面板顯示內容與圖示相關需求。

**Non-Goals:**

- 不新增或修改 `start-at-login` 能力。
- 不新增任何使用者設定（面板透明度、圖示選擇、動畫開關等一律不做）。
- 不做出現／消失動畫、彈跳、呼吸燈效。
- 不顯示預估剩餘時間。`IOKitBatteryStatusReader` 目前只讀取 `kIOPS*` 系列欄位，未讀取剩餘時間；新增該欄位會動到 `BatteryStatus` 這個「傳給每個呈現層的單一資料形狀」與其測試，屬功能擴充而非美化。
- 不讓面板寬度跟著文字內容收縮。
- 不修改已封存的 design.md。
- 不使用 `Package.swift` 的 `resources:` 機制。
- 選單列不顯示電量。選單列只負責讓使用者找到 App，電量改由面板與選單本身呈現。

## Decisions

### 面板維持兩行資訊，只放大版面

面板內容維持「大數字 +『請插電充電』」兩行，版面改為：

```
┌────────────────────────────────────┐  300×100 固定
│                                    │
│     🪫        34%                   │
│               請插電充電             │
│                                    │
└────────────────────────────────────┘
   圖示 44pt · 數字 34pt semibold 等寬數字 · 說明 15pt medium · 整組置中
```

數字使用 `.monospacedDigitSystemFont`，確保電量變化時字寬不跳動。

**替代方案與否決理由：** 曾考慮改用大電量環取代數字，以視覺化取代文字。否決原因是低電量時「差多少」是使用者當下最需要知道的資訊，電量環的視覺衝擊反而不如直接顯示數字。

### 面板寬度固定 300pt，不隨文字收縮

面板在低電量期間持續存在（規格規定不能手動關閉）。若寬度跟著文字收縮，電量從 9% 變 10% 就會讓面板左右跳動，反而持續吸引目光。固定寬度讓數字變化只改動中央的數字本身。

固定寬度的代價是短數字（例如 `5%`）兩側留白較多，但整組置中後留白對稱，視覺上成立。

### 修正面板電量數字從未顯示的缺陷

`updateContent` 目前透過走訪 `container.subviews` 並轉型為 `NSTextField` 來尋找標籤，但標籤被加入的是 `NSStackView`，不是容器直接子視圖。

修正方向是持有標籤的直接參考，不走訪視圖樹。

**替代方案與否決理由：** 曾考慮遞迴走訪整棵視圖樹以符合現有寫法。否決原因是遞迴走訪只是讓搜尋「碰巧成功」，代價是每次更新都掃描視圖層級，且未來若在其他層加入文字欄可能取到錯誤對象。直接持有參考更符合 `AlertPanelController` 檔頭註解已宣稱的意圖（「Reach the labels later without walking the view tree」）。

### 圖示選擇規則放進 BatteryWarningKit

「某個電量該用哪一顆圖示」是純函式，與 AppKit 無關。沿用既有分層理由（把呈現規則放在可被直接測試的地方），放入 `BatteryWarningKit`，AppKit 層只負責把圖示畫出來。

這讓電量分級規則可以直接被單元測試覆蓋。

### 面板依電量選圖示，選單列固定使用單一狀態圖示

**本決定取代先前的「選單列與面板共用同一組圖示對應」。**

五個電量狀態只用在**面板**：

| 條件 | 圖示 |
| --- | --- |
| 充電中 | `battery-charging` |
| 電量 0–25% | `battery-25` |
| 電量 26–50% | `battery-50` |
| 電量 51–75% | `battery-75` |
| 電量 76–100% | `battery-100` |

面板並非永遠只顯示最低階圖示。門檻可調至 `AlertThresholds.maxAlert = 50`，因此門檻設為 50%、電量 45% 時面板會出現，此時應顯示 `battery-50` 而非 `battery-25`。

**選單列不使用這組圖示，也不再顯示任何文字。** 選單列固定顯示一個 App 狀態圖示，電量與提醒狀態改由面板與下拉選單呈現。

**替代方案與否決理由：** 曾考慮選單列維持「圖示 + 電量百分比」。否決原因是使用者明確表示不要在選單列顯示任何文字。代價是使用者無法從選單列一眼看到電量，必須點開選單，這一點已寫入規格。

### 選單列圖示由原始素材去背成剪影

`StatusIcon.jpeg` 實測為 2048×2048、**完全沒有透明**的方形圖：

```
四角 2x2: [88,90,89] [89,89,89] [89,87,88] [90,89,87]
角落平均亮度=89   中心亮度=253
```

四角與邊緣都是均勻的深灰，若直接當圖示會在選單列呈現一個深灰色方塊。

素材主體是淺色的電池造型、背景是深灰漸層，因此以「反向亮度」推得透明度：主體越亮的地方不透明度越高，背景的深灰落到接近 0。產出黑色剪影並標記為樣板圖（template），macOS 會依系統淺色／深色外觀自動反白。

**替代方案與否決理由：** 曾考慮完整去背、保留 3D 漸層外觀。否決原因是選單列圖示只有 18pt（@2x 為 36px），這種帶漸層與高光的細節在此尺寸會糊成一團；剪影版本則清晰可辨。

### 圖示以裁切後的畫布載入

原始檔案的畫布是 340×120，圖案只有 60×106，左右各留 140px 透明邊框。若直接把整張畫布交給 `NSImageView` 並限制為 44×44，AppKit 會把整張畫布縮放到 44×44，圖案實際只剩約 7.8×13.8pt，幾乎不可見。

因此圖示在放入資源目錄前先裁掉透明邊框，使畫布等於圖案範圍。

**替代方案與否決理由：** 曾考慮在執行時掃描 alpha 通道計算不透明邊界並裁切。可行且不需改動原始素材，但每次啟動都要對 5 張圖做像素掃描，且裁切邏輯會進入 AppKit 層、與圖示選擇規則混在一起。離線裁切一次可讓載入路徑保持單純。

### 圖示尺寸由使用面指定，不由素材決定

裁切後的素材是 60×106 像素。`NSImage(contentsOf:)` 會把像素尺寸當成點尺寸回報，因此圖片載入後是 **60×106 點**。實測結果：

```
name=battery-25  app=light  std=true
size=(60.0, 106.0)          ← 圖示高度
btn=(0.0, 0.0, 114.0, 22.0) ← 選單列按鈕只有 22pt 高
```

選單列按鈕比圖示矮 4.8 倍，`NSStatusBarButton` 完全畫不出這張圖，而且不報任何錯誤。

因此由 `BatteryIconLoader` 統一載入並縮放：呼叫端指定需要的高度（選單列 18pt、面板 44pt），載入時依素材長寬比換算寬度後寫回 `NSImage.size`。長寬比恆定，不會失真。

此決定同時解決了「面板要 44pt、選單列要 18pt」這兩個尺寸需求，避免載入邏輯在 `AlertPanelController` 與 `StatusItemController` 各寫一份。

**替代方案與否決理由：** 曾考慮把圖示轉為 template image 讓系統自動縮放。否決原因是 template image 會失去紅／橘／綠的分級顏色，而顏色正是這組圖示要表達的訊息。

### 選單圖示的符號名稱必須在執行期確認

`NSImage(systemSymbolName:)` 對系統不認識的名稱回傳 `nil` 且不報錯，選單項會無聲地變成沒有圖示。實測 `power.d.square` 在 macOS 26.7 上不存在（推測的常見命名並非真實符號）。

因此本次使用的 7 個符號（`bolt.horizontal`、`arrow.clockwise`、`percent`、`plus`、`minus`、`power`、`gearshape`、`arrow.right.square`）全部先在執行期確認存在後才寫入程式碼。若日後新增符號，同樣必須先驗證。

### 深色背景使用淺色外框變體

外框 `#323456` 為深藍，在深色背景上對比過低。

**實測更正：** 面板材質 `.hudWindow` 並非恆為深色。實機截圖確認它會跟著系統外觀走，淺色系統外觀下渲染為淺灰卡片，此時深藍外框對比充足，不需要淺色外框變體。只有切到深色系統外觀時面板才變暗。

因此提供兩組圖示，填色完全不變，僅外框色不同：

| 變體 | 外框色 | 用於 |
| --- | --- | --- |
| 深藍外框 | `#323456` | 面板與選單列，淺色系統外觀 |
| 淺色外框 | `#FFFFFF` | 面板與選單列，深色系統外觀 |

**替代方案與否決理由：**

- *改用淺色面板材質*：否決。面板材質已隨系統外觀自適應，實測在淺色外觀下已達到足夠對比。
- *圖示後加淺色圓角底片*：否決。不需新素材且兩種底色皆可擋住，但視覺上多一層，設計較重。
- *把圖示轉為 template image 以自動反相*：否決。使用者指定的紅／橘／綠分級是這組圖示的設計重點，template image 會失去顏色。

### 面板的充電提示前加上警告標記

「請插電充電」前加一個 SF Symbol 警告三角形，讓提示讀起來是警語而非建議。

採用 SF Symbol 而非自製素材，原因是警告標記不需要隨電量變化，且系統符號在深淺兩種外觀下都會自動調整顏色。

**符號名稱必須先在執行期驗證存在**，理由同「選單圖示的符號名稱必須在執行期確認」。

### App 圖示由原始素材產生 .icns

`AppIcon.jpeg` 實測為 2048×2048 的 JPEG：

```
四角 2x2: [254,254,252] [254,255,255]
角落平均亮度=255   中心亮度=23
```

圖案是深色圓角方塊，但圓角之外是**白色**而非透明。macOS 的 App 圖示在圓角外必須是透明，否則 Finder 會顯示一個白色方框。

因此先把圓角方塊以外的部分轉為透明，再輸出 `.icns` 寫入 App bundle 的 `Resources/`。`.icns` 由打包腳本產生，不進版控。

App 設為 `LSUIElement`，不出現在 Dock 與選單列之外的位置，但 App 圖示仍會出現在 Finder、Get Info 與「登入項目」設定中。

### 打包沿用 build-app.sh，不動 Package.swift

圖示複製到 `build/BatteryWarning.app/Contents/Resources/`，程式以 `Bundle.main` 讀取。

**替代方案與否決理由：** 使用 `Package.swift` 的 `resources:` 會產生 `BatteryWarning_BatteryWarning.bundle`，但 `build-app.sh:27` 只複製單一執行檔，該 bundle 會被遺留在 bin 目錄而 App 找不到資源，仍須修改腳本。直接沿用既有腳本只多一行複製，改動面最小。

### 修正提高／降低門檻的符號

`AlertThresholds.stepping(by:)` 的實作為 `alertPercent + delta`，正數使門檻數值上升。`StatusItemController.raiseThreshold` 傳入 `+AlertThresholds.step`、`lowerThreshold` 傳入 `-AlertThresholds.step`，因此：

- 提高門檻 → 數值上升 → 標題應為「提高門檻 (+）」
- 降低門檻 → 數值下降 → 標題應為「降低門檻 (−)」

現況 `StatusItemController.swift:100,109` 兩者寫反。

`spec.md:142` 僅規定選單須提供提高與降低項目，未綁死標題文字，因此此修正不需變更規格。

### 下拉選單每項加上 SF Symbol 圖示

選單項目加上 SF Symbol 圖示，狀態摘要列亦同。選單列圖示尺寸小，SF Symbols 正是為此尺寸設計。

下拉選單維持現有項目順序與分隔線配置，不做重新分組。

## Implementation Contract

### 使用者可觀察到的行為

- 警告面板顯示的百分比與當下實際電量一致，且隨電量變化更新。
- 警告面板為 300×100，圖示與文字整組置中，兩側留白對稱。
- 警告面板的圖示依當下電量與充電狀態更換。
- 警告面板的「請插電充電」前有警告標記。
- 警告面板圖示在面板背景上清晰可見。
- 選單列只顯示一個固定的 App 狀態圖示，**不顯示任何文字**，且不隨電量變化。
- 選單列圖示為樣板圖，在淺色與深色系統外觀下都清晰可見。
- 下拉選單每一項皆有圖示；狀態摘要列仍顯示「電量 X% · <電源狀態>」。
- 「提高門檻」標題顯示 (+)，「降低門檻」標題顯示 (−)。
- 無電池的桌上型 Mac：不出現面板、選單列仍顯示狀態圖示、下拉選單摘要列顯示「無電池資訊」。
- App 在 Finder 與「登入項目」設定中顯示使用者提供的圖示。

### 介面與資料形狀

新增於 `BatteryWarningKit`：

- 圖示資源名稱列舉（`battery-charging` / `battery-25` / `battery-50` / `battery-75` / `battery-100`，各含深藍與淺色兩個變體）。
- 由 `BatteryStatus` 推導圖示資源名稱的純函式，含電量分級與充電狀態優先順序。此函式為本變更主要的可測試單元。
- 深藍外框與淺色外框的變體選擇規則。

新增於 App 層：

- `BatteryIconLoader`：由資源名稱載入圖片並依指定高度縮放，選單列用剪影樣板圖、面板用電池圖示。

`BatteryStatus` 的欄位不變（維持 `isBatteryPresent`、`percent`、`isOnExternalPower`、`isCharging`），本次不新增資料來源。

`MenuBarDisplay` 與 `MenuBarDisplayBuilder` **刪除**，取而代之的是 `MenuSummaryText`。

實作時發現：選單列不再顯示文字後，`MenuBarDisplay` 唯一剩下的用途就是回傳一個常數空字串，成為死碼。因此刪除它與其測試，並把原本寫在 `StatusItemController.summaryText()` 裡（下拉選單摘要列用的）摘要文字規則移到 `BatteryWarningKit` 的 `MenuSummaryText`，附上單元測試。

這與本文件第一條決定「呈現規則放在 `BatteryWarningKit` 才測得到」一致，也讓規格的「Battery level is reported when the menu opens」有測試覆蓋——否則該規則只存在於無法測試的 App 層。

**本項取代 design.md 早先記載的「`MenuBarDisplay` 改為回傳空標題與中性樣式」。**

`AlertPanelController` 變更：

- 面板尺寸改為 300×100。
- 圖示改為載入使用者提供的圖示檔，不再使用 SF Symbol `battery.25`。
- 圖示尺寸 28pt → 64pt，維持素材長寬比 60:106 不壓扁。
- 百分比字級 22pt → 40pt，維持 semibold 等寬數字。
- 說明字級 13pt → 18pt。
- 圖示與文字間距 10pt → 18pt。
- 內容改為整組置中。
- 移除 `contentTintColor = .systemRed`：自製圖示為彩色圖而非 template image，tint 不生效，且圖示本身的紅／橘／綠即為分級訊號。
- 說明文字改為由「警告標記 + 文字」組成的水平堆疊。

`StatusItemController` 變更：

- `button.attributedTitle` 改為空字串。
- `button.image` 改為固定的 `status-icon` 剪影。
- 選單摘要列保留完整的電量與電源狀態文字。

資源檔案：

- `Sources/BatteryWarning/Resources/`：深藍外框 5 檔，已裁切透明邊框並改名為 `battery-charging.png`、`battery-25.png`、`battery-50.png`、`battery-75.png`、`battery-100.png`。
- `Sources/BatteryWarning/Resources/Light/`：淺色外框 5 檔，檔名為上述名稱加 `-light`，置於子資料夾。
- `Sources/BatteryWarning/Resources/status-icon.png`：由 `StatusIcon.jpeg` 去背產生的黑色剪影樣板圖。

### 失敗模式與靜默行為

- 圖示資源檔缺失：退回 SF Symbol `battery.25`，不以空白佔位。`NSImage(systemSymbolName:)` 在名稱不存在時回傳 `nil` 且不報錯，若不處理會導致圖示靜默消失。
- `status-icon.png` 缺失：退回空圖示，不影響文字以外的行為；選單列仍可點開。
- 電量超出已知範圍或為 `nil`：套用最接近的分級，不崩潰、不留空。
- 系統外觀無法判定：預設使用深藍外框變體，並在下一次狀態更新時重新判斷。
- 淺色外框變體尚未提供：面板仍可運作，但外框在深色系統外觀下對比不足；此情況需在實作階段驗證並回報，不得默默略過。
- App 圖示產生失敗：打包腳本不應中斷，仍輸出可執行但無圖示的 App，並記錄警告。

### 驗收條件

1. 以 `--simulate-battery 15 --simulate-external-power 0` 啟動，面板顯示 `15%`，而非空白。
2. 同條件下測量面板為 300×100，圖示與文字整組置中。
3. 以 `--simulate-battery 45` 搭配門檻 50 啟動，面板顯示 `battery-50` 對應圖示（紅 2 格），而非最低階圖示。
4. 面板的「請插電充電」前可見警告標記。
5. 面板材質在淺色系統外觀下渲染為淺色，電池圖示的深藍外框清晰可見；切至深色外觀後外框轉為白色且仍可見。
6. 選單列只顯示一個圖示且無任何文字；切換 `--simulate-battery` 於 15 / 45 / 80 時圖示不變。
7. 選單列圖示在淺色與深色系統外觀下都清晰可見。
8. 開啟下拉選單，每一項皆顯示圖示，摘要列仍顯示「電量 X% · <電源狀態>」。
9. 下拉選單「提高門檻」顯示 (+)，「降低門檻」顯示 (−)；從 20% 按「提高」後摘要列變 25%，按「降低」後變 15%。
10. 圖示檔案在 App bundle 中存在：`ls build/BatteryWarning.app/Contents/Resources/` 可看到電池圖示、`status-icon.png` 與 `Light/` 子資料夾，且 `build/BatteryWarning.app/Contents/Resources/` 或 bundle 根目錄存在 `.icns`。
11. `git diff Package.swift` 為空。
12. 執行 `spectra analyze polish-interfaces` 確認無 Critical 與 Warning。

### 範圍界線

- 只修改 `battery-alert` 中的「選單列呈現方式」與「無電池時的報告位置」兩條既有需求；其餘條文（面板層級、面板位置追蹤、自動消失、門檻調整與持久化、診斷失敗靜默）一律不動。
- 不修改 `start-at-login/spec.md`。
- 不修改 `Package.swift`。
- 不新增 `BatteryStatus` 欄位、不新增 IOKit 讀取。
- 不實作任何顯示動畫。
- 不修改已封存的 `2026-10-14-add-battery-warning-app/` 底下任何檔案。
- 不改變面板的視窗層級、位置追蹤邏輯、鍵盤焦點行為。
- 不改變門檻調整的步進值（仍為 5）與範圍（仍為 5–50）。
- 不讓面板寬度跟著內容收縮。
- 選單列不顯示電量，也不因電量改變而改變外觀。

## Risks / Trade-offs

- **選單列不再顯示電量，是本次最大的功能損失。** 使用者必須點開選單才能知道目前電量。既有規格的「Menu bar always reports current battery status」已一併修改以反映此決定。這是使用者明確要求的取捨。
- **選單列需執行時判斷系統外觀。** 樣板圖由系統自動反白，面板與選單列的電池圖示則需執行時選擇變體；外觀變更沒有可直接訂閱的通知，實際上需在下一次狀態更新時才會反映。
- **剪影圖示與自製 3D 圖示風格不一致。** 選單列是扁平剪影，面板是帶漸層的 3D 電池。兩者來自不同素材這是使用者指定的取捨。
- **淺色外框圖示是深色系統外觀下的前提。** 在該組圖示提供之前，切到深色外觀時面板與選單列的電池圖示對比不足。
- **固定寬度面板在短數字時留白較多。** 已知並接受的取捨，理由見「面板寬度固定 300pt」一節。
- **圖示分級閾值由 25% 跳至 100%。** 電量 50% 與 51% 會從紅 2 格跳到橘 3 格。使用者在門檻附近調整門檻時可能觀察到圖示跳變，屬可接受的粗略分級。

## Migration Plan

1. 將 5 個圖示檔裁切透明邊框並改名，置於 `Resources/`。
2. 由 `StatusIcon.jpeg` 產生去背剪影 `status-icon.png`。
3. 取得 5 個淺色外框圖示，置於 `Resources/Light/`，並驗證填色未被更動。
4. 在 `BatteryWarningKit` 加入圖示名稱列舉與選擇純函式，補上對應單元測試。
5. 新增 `BatteryIconLoader`，面板與選單列共用載入與縮放。
6. 修正 `AlertPanelController` 的標籤尋找方式、尺寸、字級、版面與警告標記。
7. `StatusItemController` 改為只顯示固定圖示，並修正選單標題符號。
8. 選單摘要列保留完整的電量與電源狀態文字。
9. 更新 `build-app.sh`：複製資源、由 `AppIcon.jpeg` 產生 `.icns`。
10. 依驗收條件逐項實測。

圖示檔名變更不影響既有使用者設定（`UserDefaults` 中僅有門檻值），無資料遷移需求。

## Open Questions

- ~~五個圖示檔與狀態的對應關係~~ **已由使用者確認。** 以程式計算各檔的填色區塊數與色值後比對，結果與暫定假設一致：

  | 檔案 | 填色格數 | 色值 | 資源名稱 | 嚴重度 |
  | --- | --- | --- | --- | --- |
  | `Code_Generated_Image_0.png` | 1（閃電） | `#61C849` | `battery-charging` | 充電中 |
  | `Code_Generated_Image_1.png` | 1 | `#F0263B` | `battery-25` | 低 |
  | `Code_Generated_Image_2.png` | 2 | `#FE494A` | `battery-50` | 中低 |
  | `Code_Generated_Image_3.png` | 3 | `#FFA100` | `battery-75` | 中 |
  | `Code_Generated_Image_4.png` | 4 | `#9AE502` | `battery-100` | 高 |

  使用者明確指定 2 格紅色代表 50% 且屬「中低」，不併入「低」。分級邊界取「該格數所對應的百分比含在內」的形式，即 `0–25` / `26–50` / `51–75` / `76–100`，與 `specs/battery-alert/spec.md` 的例子表一致。

  「低 / 中低 / 中 / 高」這四個嚴重度目前僅體現在圖示素材本身的格數與顏色，不另驅動任何文字顏色。若日後希望文字顏色也區分這四級，那是另一項變更。
- ~~`.hudWindow` 材質深淺需實機確認~~ **已確認。** 實機截圖顯示它會跟著系統外觀走：淺色外觀下渲染為淺灰卡片，深藍外框對比充足；深色外觀下才需要淺色外框變體。
- 淺色外框的最終色值尚未決定。設計值為 `#FFFFFF`，若實機顯示過亮可改為 `#F2F2F7`。
- `status-icon.png` 剪影的去背閾值尚未實測。素材主體與背景的亮度差距足夠大（主體最高 255、背景約 89），預期可清楚分離，但實際效果須在產出後目視確認。