import Foundation

@MainActor
protocol TelemetrySink: AnyObject {
    func capture(_ event: String, _ properties: [String: Any])
    func flush()
}

/// Brim collects nothing. The recorder upstream calls stays in place so upstream merges stay simple.
@MainActor
final class NoTelemetrySink: TelemetrySink {
    func capture(_ event: String, _ properties: [String: Any]) {}
    func flush() {}
}
