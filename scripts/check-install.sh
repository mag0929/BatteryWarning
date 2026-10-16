#!/bin/bash
# 比較已安裝的 .app 與 build/ 組出來的那一份，判斷是否需要重新 make install。
#
# 判斷依據是內容雜湊，不是版本號——build-app.sh 把 CFBundleShortVersionString
# 寫死成 1.0.0，拿它比對會永遠顯示「相同」。
#
# 結束狀態：
#   0  兩份內容一致，不需要重新安裝
#   1  內容不一致，需要 make install
#   2  build/ 不存在，必須先 make app（make install 會自動做）
#   3  用法錯誤
#
# 可用環境變數：
#   DEST_DIR        已安裝的 App 所在目錄（預設 /Applications）
#   BUILD_DIR       建置產物目錄（預設專案底下的 build）
#   QUIET=1         只輸出結論，不列明細
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BatteryWarning"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
DEST_DIR="${DEST_DIR:-/Applications}"
BUILT="$BUILD_DIR/$APP_NAME.app"
INSTALLED="$DEST_DIR/$APP_NAME.app"
QUIET="${QUIET:-1}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -f "$ROOT/scripts/build-app.sh" ] || {
    echo "錯誤：在 $ROOT 找不到 scripts/build-app.sh，請在專案根目錄下執行" >&2
    exit 3
}

# 逐檔產生「雜湊<兩個空白>相對路徑」清單並依路徑排序。
# 略過 .DS_Store 與 AppleDouble 檔（._*），否則只是用 Finder 看過一眼
# 就會被誤判為不一致。
manifest() {
    (
        cd "$1" || exit 1
        find . -type f ! -name '.DS_Store' ! -name '._*' -print \
        | LC_ALL=C sort \
        | while IFS= read -r f; do
            printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "${f#./}"
        done
    )
}

# 以路徑為鍵比對兩份清單。
#   $1 base manifest（走訪時先讀入，作為比對基準）
#   $2 other manifest（被逐筆走訪的那一份）
#   $3 other 那一側的稱呼，用來標示「只有它有」的檔案
#   $4 是否輸出 changed（單向比對用，避免同一個檔案報兩次）
#
# 輸出：changed（兩邊都有但雜湊不同）、only-<第三參數>（只有被走訪那側有）
classify() {
    awk -v other="$3" -v emit_changed="$4" '
        NR == FNR { hash[$2] = $1; next }
        { key = substr($0, 67)
          if (key in hash) { if (emit_changed == "1" && hash[key] != $1) print "changed\t" key }
          else               { print "only-" other "\t" key } }
    ' "$1" "$2"
}

if [ "$QUIET" != "1" ]; then
    echo "比較已安裝的 App 與建置產物"
    echo "  來源：$BUILT"
    echo "  目標：$INSTALLED"
    echo
fi

if [ ! -d "$BUILT" ]; then
    echo "需要 make install —— build/ 不存在，這支腳本沒有可比對的產物"
    [ "$QUIET" != "1" ] && echo "  make install 會先建置再複製；只想要 bundle 就跑 make app"
    exit 2
fi

if [ ! -d "$INSTALLED" ]; then
    echo "需要 make install —— $INSTALLED 尚未安裝"
    exit 1
fi

manifest "$BUILT"     > "$TMP/built"
manifest "$INSTALLED" > "$TMP/installed"

# 以 build/ 為基準走訪已安裝那份 → 報 changed 與 only-installed
# 以已安裝為基準走訪 build/ → 只報 only-built
classify "$TMP/built"     "$TMP/installed" installed 1 > "$TMP/fwd"
classify "$TMP/installed" "$TMP/built"     built     0 > "$TMP/rev"

file_count=$(wc -l < "$TMP/built" | tr -d ' ')

if [ -s "$TMP/fwd" ] || [ -s "$TMP/rev" ]; then
    echo "需要 make install —— 兩份內容不一致（共 $file_count 個檔案）"
    if [ "$QUIET" != "1" ]; then
        # 三種標籤各自唯一，因此兩份比對結果可以一起餵進來讀，不必記住哪個在哪個檔案
        awk -F'\t' '$1=="changed"{print "  內容不同：" $2}' "$TMP/fwd" "$TMP/rev"
        awk -F'\t' '$1=="only-built"{print "  已安裝的那份缺少：" $2}' "$TMP/fwd" "$TMP/rev"
        awk -F'\t' '$1=="only-installed"{print "  build/ 已無、已安裝仍留著：" $2}' "$TMP/fwd" "$TMP/rev"
        echo
        echo "  執行：make install"
    fi
    exit 1
fi

# 內容一致。原始碼可能仍比 build/ 新——那需要真的重建才能知道產物會不會變，
# 因此只當提示，不構成重新安裝的理由。
built_binary="$BUILT/Contents/MacOS/$APP_NAME"
newer=""
if [ -f "$built_binary" ]; then
    newer="$(find "$ROOT/Sources" "$ROOT/scripts" "$ROOT/Package.swift" \
        -type f -newer "$built_binary" 2>/dev/null | sed "s|^$ROOT/||" | LC_ALL=C sort)"
fi

echo "不需要 make install —— 兩份內容一致（共 $file_count 個檔案）"
if [ -n "$newer" ] && [ "$QUIET" != "1" ]; then
    echo
    echo "但有 $(printf '%s\n' "$newer" | wc -l | tr -d ' ') 個檔案比 build/ 新，可能只是註解或腳本改動，"
    echo "重建後產物未必會變。想確認可先跑 make app，再回來執行本腳本比對："
    printf '%s\n' "$newer" | sed 's/^/    /'
fi
exit 0