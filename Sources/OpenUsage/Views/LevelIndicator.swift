import SwiftUI

extension EnvironmentValues {
    /// `ImageRenderer` can't draw AppKit controls, so a share image draws its bars as shapes.
    @Entry var drawsLevelsAsShapes = false
}

/// A limit's level as a thick capsule, with a tick where it would be at an even pace.
struct LevelIndicator: View {
    let fill: Double
    let severity: WidgetData.MeterSeverity
    var paceMark: Double?

    @Environment(\.reduceAnimations) private var reduceAnimations

    private static let height: CGFloat = 7
    private var clamped: Double { min(max(fill, 0), 1) }

    var body: some View {
        Capsule()
            .fill(Theme.meterTrack)
            .overlay(alignment: .leading) {
                if clamped > 0 {
                    GeometryReader { proxy in
                        let color = Theme.severityColor(severity)
                        Capsule()
                            .fill(LinearGradient(colors: [color.opacity(0.82), color], startPoint: .leading, endPoint: .trailing))
                            .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.18)).frame(height: 2).padding(.horizontal, 2).padding(.top, 1) }
                            .frame(width: max(Self.height, (proxy.size.width * clamped).rounded()))
                    }
                }
            }
            .frame(height: Self.height)
            .animation(reduceAnimations ? nil : .smooth(duration: 0.5), value: clamped)
            .overlay {
                if let paceMark {
                    Capsule()
                        .fill(Theme.paceMark)
                        .frame(width: 2, height: 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .visualEffect { content, proxy in content.offset(x: proxy.size.width * paceMark - 1) }
                }
            }
            .accessibilityHidden(true)
    }
}
