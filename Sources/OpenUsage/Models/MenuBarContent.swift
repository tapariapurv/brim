import Foundation

struct MenuBarContent: Equatable {
    struct Item: Equatable, Identifiable {
        let id: String
        let provider: Provider
        let label: String
        let shortLabel: String
        let value: String
    }

    let items: [Item]
    var overflow = 0
    var updateAvailable = false

    var isEmpty: Bool { items.isEmpty }

    var accessibilityText: String {
        let shown = items.map { "\($0.provider.fullName) \($0.label) \($0.value)" }
        let more = overflow > 0 ? ["\(overflow) more"] : []
        let update = updateAvailable ? ["Update available"] : []
        return (shown + more + update).joined(separator: "; ")
    }
}

@MainActor
enum MenuBarContentBuilder {
    private static let genericWords: Set<String> = ["models", "bot", "usage"]

    static func build(board: PriorityBoard, limit: MenuBarLimit) -> MenuBarContent {
        guard limit != .iconOnly else { return MenuBarContent(items: []) }
        let shown = board.attention.prefix(limit.count).map { item in
            let label = item.data.title
            return MenuBarContent.Item(
                id: item.id,
                provider: item.provider,
                label: label,
                shortLabel: shortLabel(label),
                value: item.data.menuBarValue
            )
        }
        return MenuBarContent(items: shown, overflow: board.attention.count - shown.count)
    }

    static let sessionTitle = "Session"

    /// A session limit always shows: the first account's leads the strip when nothing else put one there.
    static func includingSession(_ content: MenuBarContent, accounts: [DashboardAccount]) -> MenuBarContent {
        guard !content.items.contains(where: { $0.label == sessionTitle }) else { return content }
        for account in accounts {
            guard let line = account.lines.first(where: { $0.isVisible && $0.data.title == sessionTitle }) else { continue }
            let item = MenuBarContent.Item(id: line.id, provider: account.provider, label: sessionTitle, shortLabel: sessionTitle, value: line.data.menuBarValue)
            return MenuBarContent(items: [item] + content.items, overflow: content.overflow, updateAvailable: content.updateAvailable)
        }
        return content
    }

    /// The user's own choice of metrics, shown whatever their level. Ones with no reading are left out.
    static func build(accounts: [DashboardAccount], chosen ids: [String]) -> MenuBarContent {
        let lines = accounts.flatMap { account in account.lines.map { (account.provider, $0) } }
        return MenuBarContent(items: ids.compactMap { id in
            guard let (provider, line) = lines.first(where: { $0.1.id == id }), line.isVisible else { return nil }
            let label = line.data.title
            return MenuBarContent.Item(id: id, provider: provider, label: label, shortLabel: shortLabel(label), value: line.data.menuBarValue)
        })
    }

    static func shortLabel(_ label: String) -> String {
        var words = label.split(separator: " ")
        guard words.count > 1, let last = words.last, genericWords.contains(last.lowercased()) else { return label }
        words.removeLast()
        return words.joined(separator: " ")
    }
}
