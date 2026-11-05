import Foundation
import Observation

/// Claude Code hands its status line the 5-hour and weekly limits on every update, with no request to
/// Anthropic. Brim's status line saves them to its own file, and this reads them back.
/// ponytail: the feed names no account, so Brim only uses it with one Claude login added. Asking the
/// user which login Claude Code uses would lift that.
enum ClaudeFeed {
    /// Claude Code only updates the file while it's in use, so an older one says nothing about now.
    static let liveWindow: TimeInterval = 10 * 60

    static func directory(home: URL = .homeDirectory) -> URL { home.appending(path: ".brim") }
    static func file(home: URL = .homeDirectory) -> URL { directory(home: home).appending(path: "claude-feed.json") }

    static func liveLines(now: Date, file: URL = file()) -> [MetricLine]? {
        guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              abs(now.timeIntervalSince(modified)) < liveWindow,
              let data = try? Data(contentsOf: file)
        else { return nil }
        let lines = parse(data)
        return lines.isEmpty ? nil : lines
    }

    static func parse(_ data: Data) -> [MetricLine] {
        guard let limits = ProviderParse.jsonObject(data)?["rate_limits"] as? [String: Any] else { return [] }
        return [("five_hour", "Session", MetricPeriod.sessionMs), ("seven_day", "Weekly", MetricPeriod.weekMs)]
            .compactMap { key, label, period in
                guard let window = limits[key] as? [String: Any],
                      let used = ProviderParse.number(window["used_percentage"]), (0...100).contains(used)
                else { return nil }
                return .percent(label, used, resetsAt: ClaudeUsageMapper.resetDate(window["resets_at"]), periodMs: period)
            }
    }

    /// Feed readings over the last full reading, keeping the rows only the API reports.
    static func merge(_ feed: [MetricLine], over lines: [MetricLine]) -> [MetricLine] {
        var merged = lines
        for line in feed {
            if let index = merged.firstIndex(where: { $0.label == line.label }) {
                merged[index] = line
            } else {
                merged.insert(line, at: min(feed.firstIndex(of: line) ?? 0, merged.count))
            }
        }
        return merged
    }
}

/// Turns the feed on and off: Brim's script, plus the `statusLine` entry in Claude Code's settings.
@MainActor
@Observable
final class ClaudeFeedInstaller {
    /// Keeps a reading with limits in place: a new session's first updates carry none.
    static let script = """
    #!/bin/sh
    umask 077
    tmp="$HOME/.brim/.claude-feed.$$"
    cat > "$tmp" || exit 0
    if grep -q '"rate_limits"' "$tmp"; then mv -f "$tmp" "$HOME/.brim/claude-feed.json"; else rm -f "$tmp"; fi

    """

    private let home: URL
    private(set) var isInstalled = false
    private(set) var errorMessage: String?

    init(home: URL = .homeDirectory) {
        self.home = home
        refreshStatus()
    }

    private var scriptURL: URL { ClaudeFeed.directory(home: home).appending(path: "claude-statusline.sh") }
    private var settingsURL: URL { home.appending(path: ".claude/settings.json") }

    func refreshStatus() {
        isInstalled = (try? readSettings())?["statusLine"].map(isOurs) ?? false
    }

    func update(to enabled: Bool) {
        errorMessage = nil
        do {
            var settings = try readSettings()
            if let existing = settings["statusLine"], !isOurs(existing) {
                throw FeedError("Claude Code already has a status line, so Brim left it alone. Remove it to use the feed.")
            }
            if enabled {
                try FileManager.default.createDirectory(at: ClaudeFeed.directory(home: home), withIntermediateDirectories: true)
                try Data(Self.script.utf8).write(to: scriptURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
                settings["statusLine"] = ["type": "command", "command": scriptURL.path]
            } else {
                settings["statusLine"] = nil
                try? FileManager.default.removeItem(at: ClaudeFeed.file(home: home))
            }
            try writeSettings(settings)
        } catch {
            AppLog.error(LogTag.plugin("claude"), "live feed change failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        refreshStatus()
    }

    private func isOurs(_ value: Any) -> Bool {
        (value as? [String: Any])?["command"] as? String == scriptURL.path
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any] else {
            throw FeedError("Claude Code's settings.json isn't a JSON object, so Brim left it alone.")
        }
        return settings
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.appendingPathExtension("brim-backup")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }

    private struct FeedError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
