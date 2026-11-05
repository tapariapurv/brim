import XCTest
@testable import OpenUsage

final class LocalUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = .gmt; return c }
    private var stamp: String { ISO8601DateFormatter().string(from: now) }

    func testClaudeCountsARepeatedMessageOnceAndSplitsCacheTiers() throws {
        let line = #"{"type":"assistant","timestamp":"\#(stamp)","requestId":"r","message":{"id":"m","model":"claude-x-20250101","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":30,"cache_creation_input_tokens":40,"cache_creation":{"ephemeral_1h_input_tokens":15}}}}"#
        let file = LocalUsageReader.parseClaude(Data("\(line)\n\(line)\n".utf8), modified: now, size: 0)
        let entry = try XCTUnwrap(file.keyed["m:r"])
        XCTAssertEqual(file.keyed.count, 1)
        XCTAssertEqual([entry.cacheWrite, entry.cacheWrite1h], [25, 15])
    }

    func testCodexTakesCachedOutOfInputSkipsRepeatsAndKeepsLimits() throws {
        let turn = #"{"type":"turn_context","payload":{"model":"gpt-x"}}"#
        let count = #"{"timestamp":"\#(stamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100},"last_token_usage":{"input_tokens":50,"cached_input_tokens":20,"output_tokens":5}},"rate_limits":{"limit_id":"codex","primary":{"used_percent":11,"window_minutes":43200,"resets_at":1900000000},"secondary":null}}}"#
        let file = LocalUsageReader.parseCodex(Data("\(turn)\n\(count)\n\(count)\n".utf8), modified: now, size: 0)
        XCTAssertEqual(file.unkeyed.count, 1)
        XCTAssertEqual(file.unkeyed[0].model, "gpt-x")
        XCTAssertEqual([file.unkeyed[0].input, file.unkeyed[0].cacheRead], [30, 20])
        XCTAssertEqual(LocalUsageReader.line(try XCTUnwrap(file.limits?.values.first)).label, "Monthly")
    }

    func testCostUsesEachRateAndLeavesUnlistedModelsUnpriced() {
        let prices = LocalUsageReader.parsePrices(Data(#"{"claude-x":{"input_cost_per_token":1,"output_cost_per_token":2,"cache_read_input_token_cost":0.1,"cache_creation_input_token_cost":3,"cache_creation_input_token_cost_above_1hr":4},"other":{"input_cost_per_token":1,"output_cost_per_token":1},"claude-bad":{"input_cost_per_token":"x"}}"#.utf8))
        XCTAssertEqual(Array(prices.keys), ["claude-x"])
        let priced = LocalUsageReader.Entry(at: now, model: "claude-x-20250101", input: 1, cacheRead: 10, cacheWrite: 1, cacheWrite1h: 1, output: 1)
        let unpriced = LocalUsageReader.Entry(at: now, model: "mystery", input: 100)
        let days = LocalUsageReader.aggregate([priced, unpriced], since: .distantPast, prices: prices, calendar: utc)
        let totals = days[utc.startOfDay(for: now)]?.totals
        XCTAssertEqual(totals?[.tokens], 114)
        XCTAssertEqual(try XCTUnwrap(totals?[.estimatedSpend]), 11, accuracy: 0.001)
    }

    func testEstimatesStayOutWhenTheLogsCoverOnlyPartOfTheReportedTokens() {
        let start = utc.startOfDay(for: now)
        func day(_ tokens: Double, spend: Double? = nil) -> [Date: UsageDay] {
            var totals = UsageTotals(values: [.tokens: tokens])
            totals.values[.estimatedSpend] = spend
            return [start: UsageDay(totals: totals)]
        }
        let reported = UsageHistory(calendar: utc, asOf: now, days: day(1000))
        XCTAssertNil(LocalUsageReader.merge(day(100, spend: 1), into: reported).days[start]?.totals[.estimatedSpend])
        XCTAssertEqual(LocalUsageReader.merge(day(950, spend: 1), into: reported).days[start]?.totals[.estimatedSpend], 1)
        XCTAssertEqual(LocalUsageReader.merge(day(5, spend: 1), into: UsageHistory(calendar: utc, asOf: now)).days[start]?.totals[.tokens], 5)
    }

    func testOnlyProvidersWithLogsAndNoSignInGetALocalCard() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appending(path: ".codex/sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: ".claude/projects"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        let signedIn = Account(kind: .claude, label: "Me")
        let local = LocalUsageReader.accounts(besides: [signedIn], home: home)
        XCTAssertEqual(local.map(\.kind), [.codex])
        XCTAssertTrue(LocalUsageReader.isLocal(local[0]))
        XCTAssertFalse(LocalUsageReader.isLocal(signedIn))
    }

    /// Measures the real logs on this Mac when asked: BRIM_MEASURE_LOGS=1.
    func testRealLogs() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BRIM_MEASURE_LOGS"] != nil)
        let reader = LocalUsageReader()
        for kind in LocalUsageReader.kinds {
            let start = Date()
            let days = await reader.days(kind, count: 30, now: Date(), calendar: .current)
            let total = days.values.reduce(UsageTotals()) { UsageTotals(values: $0.values.merging($1.totals.values, uniquingKeysWith: +)) }
            print("BRIM \(kind): \(Date().timeIntervalSince(start))s days=\(days.count) tokens=\(total[.tokens] ?? 0) est=\(total[.estimatedSpend] ?? 0)")
        }
        print("BRIM codex limits", await reader.limitLines(.codex, now: Date()))
    }
}
