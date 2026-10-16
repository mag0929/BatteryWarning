import AppKit

// 只有選單列的 App。Info.plist 已帶 LSUIElement=true；
// 這裡再明確設定一次 accessory 政策，即使直接執行裸執行檔也能擋掉 Dock 圖示。
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// delegate 必須由這裡保留：NSApplication 只存弱參考，
// 放掉就會被釋放，App 會變成沒有事件迴圈處理的狀態。
let delegate = AppDelegate()
app.delegate = delegate
app.run()