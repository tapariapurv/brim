import XCTest
@testable import OpenUsage

@MainActor
final class ClaudeFeedTests: XCTestCase {
    private let sample = #"{"model":{},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":2000000000},"seven_day":{"used_percentage":18.5,"resets_at":2000000000}}}"#

    private func tempHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appending(path: ".claude"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return home
    }

    func testParsesLimitsAndRejectsBadValues() {
        let lines = ClaudeFeed.parse(Data(sample.utf8))
        XCTAssertEqual(lines.map(\.label), ["Session", "Weekly"])
        XCTAssertTrue(ClaudeFeed.parse(Data(#"{"rate_limits":{"five_hour":{"used_percentage":900}}}"#.utf8)).isEmpty)
        XCTAssertTrue(ClaudeFeed.parse(Data("{}".utf8)).isEmpty)
    }

    func testMergeReplacesFeedRowsAndKeepsApiOnlyRows() {
        let merged = ClaudeFeed.merge(
            [.percent("Session", 42)],
            over: [.percent("Session", 1), .percent("Sonnet", 7)]
        )
        XCTAssertEqual(merged, [.percent("Session", 42), .percent("Sonnet", 7)])
    }

    func testAStaleFileIsNotLive() throws {
        let file = try tempHome().appending(path: "feed.json")
        try Data(sample.utf8).write(to: file)
        XCTAssertNotNil(ClaudeFeed.liveLines(now: Date(), file: file))
        XCTAssertNil(ClaudeFeed.liveLines(now: Date().addingTimeInterval(ClaudeFeed.liveWindow + 1), file: file))
    }

    func testBudgetSpacesReadsAndCapsTheHour() async throws {
        let sessions = ClaudeSessions()
        let session = sessions.session(for: "a")
        var now = Date()
        XCTAssertFalse(session.readIsHeld(forced: false, at: now))
        for _ in 0..<ClaudeSession.hourlyBudget {
            XCTAssertFalse(session.readIsHeld(forced: true, at: now))
            _ = try await session.send(at: now) { HTTPResponse(statusCode: 200, headers: [:], body: Data()) }
            now += ClaudeSession.manualSpacing - 1
            XCTAssertTrue(session.readIsHeld(forced: true, at: now), "a press inside a minute keeps the last reading")
            now += 1
        }
        XCTAssertTrue(session.readIsHeld(forced: true, at: now), "the hour's budget is spent")
        XCTAssertFalse(session.readIsHeld(forced: true, at: now + 3600))
    }

    func testInstallKeepsOtherSettingsAndUninstallRemovesOnlyOurs() throws {
        let home = try tempHome()
        let settings = home.appending(path: ".claude/settings.json")
        try Data(#"{"theme":"dark"}"#.utf8).write(to: settings)
        let installer = ClaudeFeedInstaller(home: home)
        installer.update(to: true)
        XCTAssertTrue(installer.isInstalled)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        XCTAssertEqual(json["theme"] as? String, "dark")
        installer.update(to: false)
        XCTAssertFalse(installer.isInstalled)
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        XCTAssertNil(json["statusLine"])
        XCTAssertEqual(json["theme"] as? String, "dark")
    }

    func testRefusesToReplaceSomeoneElsesStatusLine() throws {
        let home = try tempHome()
        let settings = home.appending(path: ".claude/settings.json")
        try Data(#"{"statusLine":{"type":"command","command":"mine.sh"}}"#.utf8).write(to: settings)
        let installer = ClaudeFeedInstaller(home: home)
        installer.update(to: true)
        XCTAssertFalse(installer.isInstalled)
        XCTAssertNotNil(installer.errorMessage)
        XCTAssertTrue(try String(contentsOf: settings, encoding: .utf8).contains("mine.sh"))
    }
}
