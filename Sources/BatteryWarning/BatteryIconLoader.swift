import AppKit
import BatteryWarningKit

/// 從 App bundle 裡載入電池圖示，並依各個使用面縮放成它需要的尺寸。
///
/// PNG 是 60×106 像素。直接載入時 `NSImage` 會把這個尺寸當成點數回報，
/// 而選單列按鈕只有 22pt 高，根本畫不下。因此每個呼叫端都要說出自己需要的高度，
/// 長寬比則由這裡統一維持。
enum BatteryIconLoader {
    /// 選單列按鈕約 22pt 高；留一點空間給選單列本身的上下留白。
    static let menuBarHeight: CGFloat = 18
    /// 警示面板的圖示高度。固定值，面板寬度也是固定的，兩者一起決定版面。
    static let panelHeight: CGFloat = 64

    /// 代表 `status` 的圖示；沒有電池可顯示時回傳 nil。
    ///
    /// `BatteryIcon` 已經幫 `appearance` 接上變體後綴，所以這裡唯一要試的另一個
    /// 名稱是相反顏色的外框：面板還停在淺色外框時，深藍外框雖然對比不足，
    /// 還是比整個圖示消失好。兩個檔案都不存在才退回系統符號。
    static func image(
        for status: BatteryStatus,
        appearance: SystemAppearance,
        height: CGFloat
    ) -> NSImage? {
        guard let name = BatteryIcon.iconName(for: status, appearance: appearance) else {
            return nil
        }
        // 相反變體的名稱要靠字串推導：去掉或補上 "-light" 後綴。
        // 這個推導必須與 `BatteryIcon.resourceName` 的規則一致。
        let opposite = appearance == .dark
            ? name.replacingOccurrences(of: "-light", with: "")
            : "\(name)-light"
        return image(named: name, height: height)
            ?? image(named: opposite, height: height)
            ?? scaledFallback(to: height)
    }

    /// 取指定名稱的圖示並縮放到 `height` 點高。
    ///
    /// 依序找 bundle 根目錄與 `Light/` 子目錄：檔名相同、外框顏色不同，
    /// 靠目錄區分而不是在名稱裡塞更多字。
    static func image(named name: String, height: CGFloat) -> NSImage? {
        for directory in [nil, "Light"] {
            guard let url = Bundle.main.url(
                forResource: name,
                withExtension: "png",
                subdirectory: directory
            ), let image = NSImage(contentsOf: url) else { continue }
            return sized(image, to: height)
        }
        return nil
    }

    /// 選單列用的固定狀態圖示。
    ///
    /// 標記為 template image，系統會依當下外觀自動反白，因此單一檔案在淺色與
    /// 深色選單列上都看得清楚——這是選單列圖示不需要第二個變體的原因。
    static func statusIcon(height: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: "status-icon",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            return scaledFallback(to: height)
        }
        let sized = sized(image, to: height)
        sized.isTemplate = true
        return sized
    }

    /// 縮放到指定高度並維持素材自己的長寬比，讓呼叫端不必知道原始尺寸。
    ///
    /// 這裡刻意不設 `image.size.width`：直接改寫寬度會讓 NSImageView 依寬度回推高度，
    /// 高度又被設回來，比例就在這個來回之間被抹平。
    ///
    /// 先複製再改尺寸：`size` 是就地改寫的，而本函式有可能收到共用的 `static let`
    /// （`fallback` 就是）。直接縮放會永久改掉那個共用物件的尺寸，讓之後所有
    /// 使用者拿到一個已經被改壞的圖示。複製的成本對這幾張小 PNG 而言可以忽略。
    private static func sized(_ image: NSImage, to height: CGFloat) -> NSImage {
        let resized = (image.copy() as? NSImage) ?? image
        resized.size = NSSize(
            width: height * resized.size.width / resized.size.height,
            height: height
        )
        return resized
    }

    /// SF Symbol 退路，縮放到呼叫端要求的高度。
    ///
    /// 縮放是必要的：SF Symbol `battery.25` 是 22×11 點，若不縮放就直接交給
    /// 面板，面板會在 40pt 的電量數字旁邊放一個 11pt 的小點。
    private static func scaledFallback(to height: CGFloat) -> NSImage? {
        guard let fallback else { return nil }
        return sized(fallback, to: height)
    }

    /// 沒有任何素材時使用的退路。`NSImage(systemSymbolName:)` 遇到不認識的名稱
    /// 會回傳 `nil` 且不作任何回報，所以沒有這一層的話圖示會靜默消失，
    /// 而不是明確地失敗。
    ///
    /// 這是共用的 `static let`，必須透過 `sizedFallback(to:)` 使用。
    /// 直接把它交出去會拿到 22×11 的原始尺寸，而且在深色面板上幾乎看不見。
    static let fallback = NSImage(
        systemSymbolName: "battery.25",
        accessibilityDescription: "電量"
    )
}