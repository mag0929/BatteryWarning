.PHONY: build app test clean

# swift build works with the Command Line Tools alone, but the test target
# needs XCTest / Testing macro plugins, which only ship inside a full Xcode
# toolchain. Prefer it via DEVELOPER_DIR when present: this is a per-command
# environment variable, so it needs no sudo and changes no system setting.
XCODE_TOOLCHAIN := /Applications/Xcode.app/Contents/Developer
ifeq ($(wildcard $(XCODE_TOOLCHAIN)),)
TEST_ENV :=
else
TEST_ENV := DEVELOPER_DIR=$(XCODE_TOOLCHAIN)
endif

build:
	swift build -c release

app:
	./scripts/build-app.sh release

test:
	$(TEST_ENV) swift test

clean:
	rm -rf .build build