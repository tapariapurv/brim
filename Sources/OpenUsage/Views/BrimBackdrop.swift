import SwiftUI

enum BackdropStyle: String, CaseIterable {
    case liquid, aurora, sunset, none

    static let key = "backdropStyle"

    var label: String {
        switch self {
        case .liquid: "Liquid Fill"
        case .aurora: "Aurora"
        case .sunset: "Sunset"
        case .none: "None"
        }
    }
}

/// What the panel's glass sits on. Motion is slow and ambient, and stops while the panel is hidden or
/// when Reduce Motion is on. Liquid Fill rises with the most-used limit, cool to warm.
struct BrimBackdrop: View {
    @AppStorage(BackdropStyle.key) private var style = BackdropStyle.liquid
    @Environment(WidgetDataStore.self) private var dataStore
    @Environment(PopoverState.self) private var popover
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var level: Double {
        dataStore.snapshots.values.flatMap(\.lines).reduce(0) { highest, line in
            guard case .progress(_, let used, let limit, _, _, _) = line, limit > 0 else { return highest }
            return max(highest, min(used / limit, 1))
        }
    }

    var body: some View {
        switch style {
        case .liquid: timeline { LiquidFill(level: level, time: $0) }
        case .aurora: timeline { Aurora(time: $0).opacity(0.55) }
        case .sunset: Sunset().opacity(0.5)
        case .none: Color.clear
        }
    }

    private func timeline(@ViewBuilder content: @escaping (Double) -> some View) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion || !popover.popoverShown)) { context in
            content(context.date.timeIntervalSinceReferenceDate)
        }
    }
}

private struct LiquidFill: View {
    let level: Double
    let time: Double

    var body: some View {
        let color = Color.teal.mix(with: .orange, by: max(0, level - 0.35) / 0.65)
        ZStack {
            Wave(level: level, phase: time * 0.5, amplitude: 9).fill(color.opacity(0.07))
            Wave(level: level, phase: -time * 0.35 + 2, amplitude: 6).fill(color.opacity(0.11))
        }
        .animation(.smooth(duration: 0.8), value: level)
    }
}

private struct Wave: Shape {
    /// Empty limits still show a little liquid, so the panel never reads as a blank glass.
    var level: Double
    var phase: Double
    var amplitude: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let surface = rect.maxY - rect.height * (0.08 + level * 0.84)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for x in stride(from: rect.minX, through: rect.maxX, by: 4) {
            path.addLine(to: CGPoint(x: x, y: surface + sin(x / rect.width * 2 * .pi * 1.3 + phase) * amplitude))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct Aurora: View {
    let time: Double

    var body: some View {
        let drift = Float(sin(time * 0.25)) * 0.22
        let sway = Float(cos(time * 0.18)) * 0.18
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5 + sway, 0], [1, 0],
                [0, 0.5 + drift], [0.5 + drift, 0.5 - sway], [1, 0.5 - drift],
                [0, 1], [0.5 - sway, 1], [1, 1],
            ],
            colors: [
                .indigo, .purple, .teal,
                .teal, .mint, .indigo,
                .purple, .pink, .blue,
            ]
        )
    }
}

private struct Sunset: View {
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [[0, 0], [0.5, 0], [1, 0], [0, 0.45], [0.6, 0.55], [1, 0.4], [0, 1], [0.45, 1], [1, 1]],
            colors: [.indigo, .purple, .pink, .pink, .orange, .red, .orange, .yellow, .orange]
        )
    }
}
