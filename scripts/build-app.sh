#!/bin/bash
# 從 SwiftPM 的建置產物組出 BatteryWarning.app。
# 只依賴 Command Line Tools：swift build + codesign（ad-hoc 簽章）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="BatteryWarning"
BUNDLE_ID="com.local.batterywarning"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product "$APP_NAME"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "error: built executable not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

# 複製資源。`Package.swift` 刻意沒有宣告任何 resources，因此圖示在這裡複製，
# 而不是從 SwiftPM 的 resource bundle 進來。
RES_SRC="$ROOT/Resources"
if [[ -d "$RES_SRC" ]]; then
    # AppIcon.png 是下面產生 .icns 的建置輸入，不是 App 在執行期會載入的東西，
    # 因此不放進 bundle。
    find "$RES_SRC" -maxdepth 1 -name '*.png' ! -name 'AppIcon.png' \
        -exec cp {} "$APP_DIR/Contents/Resources/" \;
    # 淺色外框的變體放在 Light/ 子目錄，目錄結構必須原樣保留，
    # `BatteryIconLoader` 是靠 subdirectory 找到它們的。
    [[ -d "$RES_SRC/Light" ]] && cp -R "$RES_SRC/Light" "$APP_DIR/Contents/Resources/"
fi

# 由已去背裁切的正方形來源產生 AppIcon.icns。
# 只用 macOS 內建工具（sips + iconutil），因此只裝 Command Line Tools 也能運作。
# 這一步失敗絕對不能讓一個可用的 App 消失，所以全部路徑都是警告而非中止。
build_icon() {
    local src="$RES_SRC/AppIcon.png" out="$APP_DIR/Contents/Resources/AppIcon.icns"
    if [[ ! -f "$src" ]]; then
        echo "warning: AppIcon.png not found, building without an app icon" >&2
        return 0
    fi
    local set="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$set"; mkdir -p "$set"
    local name size
    # .iconset 要求的十個尺寸，1x 與 2x 都要，缺一個 iconutil 就會拒絕。
    for spec in "icon_16x16:16" "icon_16x16@2x:32" "icon_32x32:32" \
                "icon_32x32@2x:64" "icon_128x128:128" "icon_128x128@2x:256" \
                "icon_256x256:256" "icon_256x256@2x:512" "icon_512x512:512" \
                "icon_512x512@2x:1024"; do
        name="${spec%%:*}"; size="${spec##*:}"
        sips -z "$size" "$size" "$src" --out "$set/$name.png" >/dev/null 2>&1 || {
            echo "warning: sips failed at $size px, building without an app icon" >&2
            rm -rf "$set"; return 0
        }
    done
    if iconutil -c icns "$set" -o "$out" 2>/dev/null; then
        rm -rf "$set"
        echo "    AppIcon.icns written"
    else
        echo "warning: iconutil failed, building without an app icon" >&2
        rm -rf "$set"
    fi
}
build_icon

# Info.plist 在這裡產生而不是版控：bundle 識別碼與 App 名稱都來自上方變數，
# 少一份需要同步的檔案。
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_TW</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <!-- 指向 Contents/Resources/AppIcon.icns（不帶副檔名）。 -->
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- 只有選單列：沒有 Dock 圖示，沒有主視窗。 -->
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# ad-hoc 簽章。App 沒有憑證也沒有公證，這是發到本機時唯一可行的做法，
# 足以讓 Gatekeeper 在本機執行時放行。
echo "==> codesign (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP_DIR"

echo "==> done: $APP_DIR"