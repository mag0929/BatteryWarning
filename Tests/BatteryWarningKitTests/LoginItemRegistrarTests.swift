import Foundation
import Testing
@testable import BatteryWarningKit

@Suite("開機啟動註冊")
struct LoginItemRegistrarTests {

    final class FakePrimary: SystemLoginItem {
        var isEnabled: Bool
        var registerShouldThrow: Error?
        private(set) var registerCount = 0
        private(set) var unregisterCount = 0

        init(enabled: Bool = false, registerShouldThrow: Error? = nil) {
            self.isEnabled = enabled
            self.registerShouldThrow = registerShouldThrow
        }

        func register() throws {
            registerCount += 1
            if let registerShouldThrow { throw registerShouldThrow }
            isEnabled = true
        }

        func unregister() throws {
            unregisterCount += 1
            isEnabled = false
        }
    }

    struct Rejected: Error {}

    private func makeRegistrar(
        primary: FakePrimary,
        tempDir: URL,
        commands: @escaping (String, [String]) -> Int32 = { _, _ in 0 }
    ) -> LoginItemRegistrar {
        LoginItemRegistrar(
            primary: primary,
            bundleIdentifier: "com.local.batterywarning.test",
            executableURL: URL(fileURLWithPath: "/Applications/Test.app/Contents/MacOS/Test"),
            launchAgentsDirectory: tempDir,
            runCommand: commands
        )
    }

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bw-login-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func testFallsBackToLaunchAgentWhenPrimaryFails() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let primary = FakePrimary(enabled: false, registerShouldThrow: Rejected())
        var ran: [(String, [String])] = []
        let registrar = makeRegistrar(primary: primary, tempDir: dir) { path, args in
            ran.append((path, args))
            return 0
        }

        try registrar.register()

        #expect(primary.registerCount == 1, "主要機制有被嘗試過")
        #expect(
            FileManager.default.fileExists(atPath: registrar.launchAgentURL.path),
            "fallback 的 plist 必須存在"
        )
        #expect(registrar.isRegistered, "登入時啟動仍可透過 fallback 運作")

        // plist 內容
        let data = try Data(contentsOf: registrar.launchAgentURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try #require(plist as? [String: Any])
        #expect(dict["Label"] as? String == "com.local.batterywarning.test")
        #expect(dict["RunAtLoad"] as? Bool == true)
        #expect(dict["ProcessType"] as? String == "Interactive")
        let programArgs = try #require(dict["ProgramArguments"] as? [String])
        #expect(programArgs.count == 1)
        #expect(programArgs[0].hasSuffix("Test"))

        // launchctl bootstrap 有被嘗試過
        #expect(ran.contains { $0.0 == "launchctl" && $0.1.contains("bootstrap") })
    }

    @Test func testPrimarySuccessWritesNoLaunchAgent() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let primary = FakePrimary(enabled: false)
        var ran: [(String, [String])] = []
        let registrar = makeRegistrar(primary: primary, tempDir: dir) { path, args in
            ran.append((path, args))
            return 0
        }

        try registrar.register()

        #expect(primary.isEnabled)
        #expect(!FileManager.default.fileExists(atPath: registrar.launchAgentURL.path))
        #expect(ran.isEmpty, "主要路徑可用時不該呼叫 launchctl")
        #expect(registrar.isRegistered)
    }

    @Test func testUnregisterRemovesBoth() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let primary = FakePrimary(enabled: false, registerShouldThrow: Rejected())
        let registrar = makeRegistrar(primary: primary, tempDir: dir)
        try registrar.register()
        #expect(FileManager.default.fileExists(atPath: registrar.launchAgentURL.path))

        registrar.unregister()

        #expect(primary.unregisterCount == 1)
        #expect(!FileManager.default.fileExists(atPath: registrar.launchAgentURL.path))
        #expect(registrar.isRegistered == false)
    }

    @Test func testIsRegisteredReflectsRealityNotPreference() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 兩個機制都沒有註冊。
        let registrar = makeRegistrar(primary: FakePrimary(enabled: false), tempDir: dir)
        #expect(registrar.isRegistered == false)

        // 只有主要系統註冊時也算已註冊——另一個機制同樣在場。
        let registered = makeRegistrar(primary: FakePrimary(enabled: true), tempDir: dir)
        #expect(registered.isRegistered == true)
    }

    @Test func testFallbackFailurePropagates() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 在 LaunchAgents 該是目錄的位置放了一個一般檔案：寫 plist 不可能成功，
        // 因此 fallback 必須回報失敗，而不是宣稱成功。
        let blocked = dir.appendingPathComponent("LaunchAgents")
        FileManager.default.createFile(atPath: blocked.path, contents: Data("x".utf8))

        let registrar = LoginItemRegistrar(
            primary: FakePrimary(registerShouldThrow: Rejected()),
            bundleIdentifier: "com.local.batterywarning.test",
            executableURL: URL(fileURLWithPath: "/tmp/x"),
            launchAgentsDirectory: blocked,
            runCommand: { _, _ in 0 }
        )

        #expect(throws: LoginItemError.self) {
            try registrar.register()
        }
        #expect(registrar.isRegistered == false, "fallback 失敗不算「已註冊」")
    }
}