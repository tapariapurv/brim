import SwiftUI

struct DashboardContentView: View {
    @Environment(LayoutStore.self) private var layout
    @Environment(PopoverState.self) private var popover
    let reorderSpaceName: String

    @Binding var reorderLift: ReorderLift?
    @Binding var scrollPosition: ScrollPosition

    /// Half the space on each side of the content: it and the bar beside it each hold this much.
    static let barGap: CGFloat = 7

    var body: some View {
        PopoverScrollView {
            widgetContent
            .padding(.horizontal, PanelMetrics.margin)
            .padding(.vertical, Self.barGap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollPosition($scrollPosition)
        .onChange(of: popover.dashboardTab) { scrollPosition.scrollTo(edge: .top) }
    }

    @ViewBuilder
    private var widgetContent: some View {
        if layout.registry.providers.isEmpty {
            EmptyDashboardView { popover.isAddingAccount = true }
        } else if layout.displayGroups.isEmpty {
            Text("Every metric is hidden. Turn them back on in Accounts.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
        } else {
            switch popover.dashboardTab {
            case .priority:
                PriorityDashboardView()
            case .allUsage:
                WidgetGroupedListView(
                    reorderSpaceName: reorderSpaceName,
                    reorderLift: $reorderLift
                )
            }
        }
    }
}
