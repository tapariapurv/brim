import Foundation

@MainActor
protocol ProviderRuntime: AnyObject {
    var provider: Provider { get }
    var widgetDescriptors: [WidgetDescriptor] { get }

    func refresh() async -> Result<ProviderSnapshot, RefreshFailure>
    func forgetHourlyReads()
    func restore(_ snapshot: ProviderSnapshot)
    func refreshHourlyReads(of snapshot: ProviderSnapshot) async -> ProviderSnapshot?
    /// New readings are available without asking the provider, so a backoff need not hold them.
    var hasLiveLocalData: Bool { get }
    /// Asking the provider now would spend its request budget for too little: keep the last reading.
    func holdsRead(forced: Bool) -> Bool
    var rereadsHourlyOnManualRefresh: Bool { get }
}

extension ProviderRuntime {
    func forgetHourlyReads() {}
    func restore(_ snapshot: ProviderSnapshot) {}
    func refreshHourlyReads(of snapshot: ProviderSnapshot) async -> ProviderSnapshot? { nil }
    var hasLiveLocalData: Bool { false }
    func holdsRead(forced: Bool) -> Bool { false }
    var rereadsHourlyOnManualRefresh: Bool { true }
}

struct ProviderUsage: Equatable, Sendable {
    var plan: String?
    var lines: [MetricLine]
    var notice: String?
    var history: UsageHistory?
    /// Row titles this reading renames, keyed by line label.
    var lineTitles: [String: String] = [:]
}

extension MetricLine {
    static func percent(_ label: String, _ used: Double, resetsAt: Date? = nil, periodMs: Int? = nil) -> MetricLine {
        .progress(label: label, used: used, limit: 100, format: .percent, resetsAt: resetsAt, periodDurationMs: periodMs)
    }
}

func loadOffMainActor<T: Sendable>(_ load: @escaping @Sendable () throws -> T) async throws -> T {
    try await Task.detached(priority: .utility, operation: load).value
}
