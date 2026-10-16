.PHONY: build app install test clean

# swift build 只靠 Command Line Tools 就能跑，但測試 target 需要 XCTest 與
# Testing 的巨集外掛，它們只隨完整的 Xcode toolchain 出貨。存在時用
# DEVELOPER_DIR 優先選它：這是單一指令的環境變數，不需要 sudo，
# 也不會改動任何系統設定。
XCODE_TOOLCHAIN := /Applications/Xcode.app/Contents/Developer
ifeq ($(wildcard $(XCODE_TOOLCHAIN)),)
TEST_ENV :=
else
TEST_ENV := DEVELOPER_DIR=$(XCODE_TOOLCHAIN)
endif

# `make install` 要把 App 裝到哪裡。覆寫方式：`make install DEST_DIR=...`。
DEST_DIR ?= /Applications
APP_NAME := BatteryWarning

# 只用來建立 DEST_DIR。父目錄可寫並不代表裡面既有的副本刪得掉——舊的安裝
# 可能是 root 擁有的——所以刪除那一步直接試再升級，這裡不去猜。
SUDO := $(shell d="$(DEST_DIR)"; while [ ! -d "$$d" ] && [ "$$d" != / ]; do d=$${d%/*}; done; test -w "$$d" 2>/dev/null || echo sudo)

build:
	swift build -c release

app:
	./scripts/build-app.sh release

# 把組好的 bundle 複製到 DEST_DIR，讓安裝出去的那份永遠不會和 build/ 漂移。
# 先建置，再只針對需要的那一步提權。
install: app
	@# 先關掉正在執行的那份：覆寫一個正在執行的 bundle 會得到
	@# 「busy」而不是更新。
	@if pgrep -f "$(DEST_DIR)/$(APP_NAME).app" >/dev/null 2>&1; then \
		echo "==> quitting any running $(APP_NAME) first"; \
		pkill -f "$(DEST_DIR)/$(APP_NAME).app" || true; \
		sleep 1; \
	fi
	$(SUDO) mkdir -p "$(DEST_DIR)"
	@# 先不用 sudo 試；真的失敗（多半是舊副本屬於 root）才升級。
	@rm -rf "$(DEST_DIR)/$(APP_NAME).app" 2>/dev/null || { \
		echo "==> removing the old copy needs root; retrying with sudo"; \
		sudo rm -rf "$(DEST_DIR)/$(APP_NAME).app"; \
	}
	@# 複製一定要帶上 $(SUDO)。mkdir 若是以 sudo 建立（或 DEST_DIR 存在但
	@# 不可寫），目錄就屬於 root，不提權的 cp 必定 Permission denied。
	$(SUDO) cp -R build/$(APP_NAME).app "$(DEST_DIR)/$(APP_NAME).app"
	@# 但 sudo 複製會讓 bundle 變成 root 擁有，下次安裝還得再要一次密碼。
	@# 因此把擁有者還給呼叫者；$(SUDO) 為空時這只是把檔案改給自己（no-op）。
	@# 改擁有者不影響 ad-hoc 簽章——簽章比對的是內容，不是擁有者。
	$(SUDO) chown -R "$$(id -un)" "$(DEST_DIR)/$(APP_NAME).app" 2>/dev/null || true
	@# Finder 依路徑與 mtime 快取 App 圖示；touch 一下 bundle，
	@# 換了圖示之後它才會重新讀取 AppIcon.icns。
	touch "$(DEST_DIR)/$(APP_NAME).app"
	@# 把擁有者印出來，讓「下次還需不需要 sudo」這件事看得見。
	@echo "==> installed to $(DEST_DIR)/$(APP_NAME).app (owned by $$(id -un))"

test:
	$(TEST_ENV) swift test

clean:
	rm -rf .build build