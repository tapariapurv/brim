import Foundation

/// Reads what Claude Code and Codex log on this Mac: tokens by model, plus Codex's limits and the Claude
/// Code Live Feed. It backs an account that isn't signed in, stands in when a signed-in read fails, and
/// prices tokens at the public API rates in LiteLLM's table. Those costs are estimates, labelled as such.
actor LocalUsageReader {
    static let enabledKey = "useLocalUsage"
    static let kinds: [ProviderKind] = [.claude, .codex]
    static let pricesURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    private static let pricesMaxAge: TimeInterval = 24 * 60 * 60

    struct Entry: Equatable, Sendable {
        var at: Date
        var model: String
        var input = 0.0
        var cacheRead = 0.0
        var cacheWrite = 0.0
        var cacheWrite1h = 0.0
        var output = 0.0
        var tokens: Double { input + cacheRead + cacheWrite + cacheWrite1h + output }
    }

    struct Price: Codable, Equatable, Sendable {
        var input: Double
        var output: Double
        var cacheRead: Double?
        var cacheWrite: Double?
        var cacheWrite1h: Double?

        func cost(of entry: Entry) -> Double {
            entry.input * input + entry.output * output
                + entry.cacheRead * (cacheRead ?? input)
                + entry.cacheWrite * (cacheWrite ?? input)
                + entry.cacheWrite1h * (cacheWrite1h ?? cacheWrite ?? input)
        }
    }

    struct CodexLimit: Equatable, Sendable {
        var usedPercent: Double
        var windowMinutes: Int
        var resetsAt: Date?
    }

    struct ScannedFile: Sendable {
        var modified: Date
        var size: Int
        /// Keyed so a resumed session that repeats a message counts it once.
        var keyed: [String: Entry] = [:]
        var unkeyed: [Entry] = []
        var limits: (at: Date, values: [CodexLimit])?
    }

    private let home: URL
    private let http: any HTTPClient
    private var scanned: [String: ScannedFile] = [:]
    private var prices: [String: Price] = [:]
    private var pricesReadAt: Date?

    init(home: URL = .homeDirectory, http: any HTTPClient = URLSessionHTTPClient()) {
        self.home = home
        self.http = http
    }

    private static func logRoot(_ kind: ProviderKind, home: URL) -> URL? {
        switch kind {
        case .claude: home.appending(path: ".claude/projects")
        case .codex: home.appending(path: ".codex/sessions")
        default: nil
        }
    }

    /// Stable, so a local account keeps its layout and hidden metrics across launches.
    private static func accountID(_ kind: ProviderKind) -> UUID? {
        switch kind {
        case .claude: UUID(uuidString: "B1000000-0000-4000-8000-000000000001")
        case .codex: UUID(uuidString: "B1000000-0000-4000-8000-000000000002")
        default: nil
        }
    }

    static func isLocal(_ account: Account) -> Bool { account.id == accountID(account.kind) }

    /// A signed-in account reads better than the logs, so logs only get their own card without one.
    nonisolated static func accounts(besides signedIn: [Account], home: URL = .homeDirectory) -> [Account] {
        kinds.compactMap { kind in
            guard !signedIn.contains(where: { $0.kind == kind }), let id = accountID(kind), let root = logRoot(kind, home: home),
                  FileManager.default.fileExists(atPath: root.path)
            else { return nil }
            return Account(id: id, kind: kind, label: "Local", addedAt: .distantPast)
        }
    }

    // MARK: - Reading

    func limitLines(_ kind: ProviderKind, now: Date) -> [MetricLine] {
        switch kind {
        case .claude:
            guard let data = try? Data(contentsOf: ClaudeFeed.file(home: home)) else { return [] }
            return ClaudeFeed.parse(data).filter { line in
                guard case .progress(_, _, _, _, let resetsAt, _) = line, let resetsAt else { return true }
                return resetsAt > now
            }
        case .codex:
            scan(.codex, days: 31, now: now)
            let root = Self.logRoot(.codex, home: home)?.path ?? ""
            let newest = scanned.filter { $0.key.hasPrefix(root) }.values.compactMap(\.limits).max { $0.at < $1.at }
            return (newest?.values ?? []).filter { ($0.resetsAt ?? .distantFuture) > now }.map(Self.line)
        default:
            return []
        }
    }

    static func line(_ limit: CodexLimit) -> MetricLine {
        let label = limit.windowMinutes <= 6 * 60 ? "Session" : limit.windowMinutes <= 7 * 24 * 60 ? "Weekly" : "Monthly"
        return .percent(label, limit.usedPercent, resetsAt: limit.resetsAt, periodMs: limit.windowMinutes * 60_000)
    }

    /// Tokens and estimated cost by day. Tokens from a model the table doesn't list are counted but not priced.
    func days(_ kind: ProviderKind, count: Int, now: Date, calendar: Calendar) async -> [Date: UsageDay] {
        await refreshPrices(now: now)
        scan(kind, days: count + 1, now: now)
        let root = Self.logRoot(kind, home: home)?.path ?? ""
        let files = scanned.filter { $0.key.hasPrefix(root) }.values
        var keyed: [String: Entry] = [:]
        for file in files { keyed.merge(file.keyed) { _, newer in newer } }
        let earliest = calendar.date(byAdding: .day, value: 1 - count, to: calendar.startOfDay(for: now)) ?? now
        return Self.aggregate(Array(keyed.values) + files.flatMap(\.unkeyed), since: earliest, prices: prices, calendar: calendar)
    }

    static func aggregate(_ entries: [Entry], since earliest: Date, prices: [String: Price], calendar: Calendar) -> [Date: UsageDay] {
        var days: [Date: UsageDay] = [:]
        for entry in entries where entry.at >= earliest {
            let start = calendar.startOfDay(for: entry.at)
            var totals = days[start]?.totals ?? UsageTotals()
            totals.values[.tokens, default: 0] += entry.tokens
            totals.values[.inputTokens, default: 0] += entry.input
            totals.values[.cacheReadTokens, default: 0] += entry.cacheRead
            totals.values[.cacheWriteTokens, default: 0] += entry.cacheWrite + entry.cacheWrite1h
            totals.values[.outputTokens, default: 0] += entry.output
            if let price = price(for: entry.model, in: prices) {
                totals.values[.estimatedSpend, default: 0] += price.cost(of: entry)
            }
            days[start] = UsageDay(totals: totals)
        }
        return days
    }

    static func price(for model: String, in prices: [String: Price]) -> Price? {
        if let price = prices[model] { return price }
        // "claude-haiku-4-5-20251001" is listed without its date.
        let undated = model.replacing(/-\d{8}$/, with: "")
        return prices[undated]
    }

    // MARK: - Prices

    private var pricesFile: URL { ClaudeFeed.directory(home: home).appending(path: "model-prices.json") }

    private func refreshPrices(now: Date) async {
        if let pricesReadAt, now.timeIntervalSince(pricesReadAt) < Self.pricesMaxAge { return }
        pricesReadAt = now
        let saved = (try? Data(contentsOf: pricesFile)).flatMap { try? JSONDecoder().decode([String: Price].self, from: $0) }
        let modified = (try? pricesFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let saved { prices = saved }
        if saved != nil, let modified, now.timeIntervalSince(modified) < Self.pricesMaxAge { return }
        do {
            let response = try await http.send(HTTPRequest(method: "GET", url: Self.pricesURL, timeout: 30))
            let fresh = (200..<300).contains(response.statusCode) ? Self.parsePrices(response.body) : [:]
            guard !fresh.isEmpty else {
                AppLog.warn(LogTag.plugin("local"), "price table unavailable (\(response.statusCode)); keeping the last one")
                return
            }
            prices = fresh
            try FileManager.default.createDirectory(at: pricesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(fresh).write(to: pricesFile, options: .atomic)
        } catch {
            AppLog.warn(LogTag.plugin("local"), "price table failed: \(error.localizedDescription)")
        }
    }

    static func parsePrices(_ data: Data) -> [String: Price] {
        guard let table = ProviderParse.jsonObject(data) else { return [:] }
        var prices: [String: Price] = [:]
        for (model, value) in table where model.hasPrefix("claude-") || model.hasPrefix("gpt-") || model.hasPrefix("codex-") {
            guard let row = value as? [String: Any],
                  let input = ProviderParse.number(row["input_cost_per_token"]), input >= 0,
                  let output = ProviderParse.number(row["output_cost_per_token"]), output >= 0
            else { continue }
            prices[model] = Price(
                input: input,
                output: output,
                cacheRead: ProviderParse.number(row["cache_read_input_token_cost"]),
                cacheWrite: ProviderParse.number(row["cache_creation_input_token_cost"]),
                cacheWrite1h: ProviderParse.number(row["cache_creation_input_token_cost_above_1hr"])
            )
        }
        return prices
    }

    // MARK: - Logs

    /// Only files that changed since the last pass are read again.
    /// ponytail: the first pass reads every log from the span and holds its entries in memory. Persist
    /// them if that ever gets slow enough to notice.
    private func scan(_ kind: ProviderKind, days: Int, now: Date) {
        guard let root = Self.logRoot(kind, home: home),
              let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        else { return }
        let oldest = now.addingTimeInterval(-TimeInterval(days + 1) * 86_400)
        var seen = Set<String>()
        for case let url as URL in files where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate, modified >= oldest
            else { continue }
            seen.insert(url.path)
            let size = values.fileSize ?? 0
            if let known = scanned[url.path], known.modified == modified, known.size == size { continue }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            scanned[url.path] = kind == .claude
                ? Self.parseClaude(data, modified: modified, size: size)
                : Self.parseCodex(data, modified: modified, size: size)
        }
        for path in scanned.keys where path.hasPrefix(root.path) && !seen.contains(path) { scanned[path] = nil }
    }

    private static func forEachLine(in data: Data, containing needles: [String], _ body: ([String: Any]) -> Void) {
        let patterns = needles.map { Data($0.utf8) }
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[start..<end]
            if patterns.contains(where: { line.range(of: $0) != nil }), let object = ProviderParse.jsonObject(Data(line)) {
                body(object)
            }
            start = end < data.endIndex ? data.index(after: end) : data.endIndex
        }
    }

    static func parseClaude(_ data: Data, modified: Date, size: Int) -> ScannedFile {
        var file = ScannedFile(modified: modified, size: size)
        forEachLine(in: data, containing: [#""usage""#]) { object in
            guard object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let id = message["id"] as? String,
                  let model = message["model"] as? String, model != "<synthetic>",
                  let at = ClaudeUsageMapper.resetDate(object["timestamp"])
            else { return }
            let tiers = usage["cache_creation"] as? [String: Any]
            let hour = ProviderParse.number(tiers?["ephemeral_1h_input_tokens"]) ?? 0
            let created = ProviderParse.number(usage["cache_creation_input_tokens"]) ?? 0
            file.keyed["\(id):\(object["requestId"] as? String ?? "")"] = Entry(
                at: at,
                model: model,
                input: ProviderParse.number(usage["input_tokens"]) ?? 0,
                cacheRead: ProviderParse.number(usage["cache_read_input_tokens"]) ?? 0,
                cacheWrite: max(0, created - hour),
                cacheWrite1h: hour,
                output: ProviderParse.number(usage["output_tokens"]) ?? 0
            )
        }
        return file
    }

    static func parseCodex(_ data: Data, modified: Date, size: Int) -> ScannedFile {
        var file = ScannedFile(modified: modified, size: size)
        var model: String?
        var lastTotal = -1.0
        forEachLine(in: data, containing: [#""token_count""#, #""turn_context""#]) { object in
            guard let payload = object["payload"] as? [String: Any] else { return }
            if object["type"] as? String == "turn_context" {
                model = payload["model"] as? String ?? model
                return
            }
            guard payload["type"] as? String == "token_count",
                  let at = ClaudeUsageMapper.resetDate(object["timestamp"])
            else { return }
            if let info = payload["info"] as? [String: Any],
               let last = info["last_token_usage"] as? [String: Any],
               let total = ProviderParse.number((info["total_token_usage"] as? [String: Any])?["total_tokens"]),
               total != lastTotal {
                lastTotal = total
                // Codex counts cached tokens inside input, and reasoning inside output.
                let input = ProviderParse.number(last["input_tokens"]) ?? 0
                let cached = ProviderParse.number(last["cached_input_tokens"]) ?? 0
                file.unkeyed.append(Entry(
                    at: at,
                    model: model ?? "",
                    input: max(0, input - cached),
                    cacheRead: cached,
                    output: ProviderParse.number(last["output_tokens"]) ?? 0
                ))
            }
            if let limits = payload["rate_limits"] as? [String: Any], (limits["limit_id"] as? String ?? "codex") == "codex" {
                let values = ["primary", "secondary"].compactMap { key -> CodexLimit? in
                    guard let window = limits[key] as? [String: Any],
                          let used = ProviderParse.number(window["used_percent"]), (0...100).contains(used),
                          let minutes = ProviderParse.number(window["window_minutes"]), minutes > 0
                    else { return nil }
                    return CodexLimit(usedPercent: used, windowMinutes: Int(minutes), resetsAt: ClaudeUsageMapper.resetDate(window["resets_at"]))
                }
                if !values.isEmpty { file.limits = (at, values) }
            }
        }
        return file
    }
}
