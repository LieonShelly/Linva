import SwiftUI

struct MainToolbar: ToolbarContent {
    let hasSelection: Bool
    let isRootSelected: Bool
    let canToggleCollapse: Bool
    let isCollapsed: Bool
    let zoomPercent: Int
    let addChild: () -> Void
    let addSibling: () -> Void
    let toggleCollapse: () -> Void
    let delete: () -> Void
    let zoomOut: () -> Void
    let zoomIn: () -> Void
    let fit: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button(action: addChild) {
                Label("子主题", systemImage: "arrow.turn.down.right")
            }
            .disabled(!hasSelection)
            .help("添加子主题（Tab）")

            Button(action: addSibling) {
                Label("同级主题", systemImage: "plus.rectangle.on.rectangle")
            }
            .disabled(!hasSelection || isRootSelected)
            .help("添加同级主题（Return）")

            Button(action: toggleCollapse) {
                Label(
                    isCollapsed ? "展开" : "折叠",
                    systemImage: isCollapsed
                        ? "rectangle.expand.vertical"
                        : "rectangle.compress.vertical"
                )
            }
            .disabled(!hasSelection || !canToggleCollapse)
            .help(isCollapsed ? "展开子主题" : "折叠子主题")

            Button(role: .destructive, action: delete) {
                Label("删除", systemImage: "trash")
            }
            .disabled(!hasSelection || isRootSelected)
            .help("删除主题（Delete）")
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            Button(action: zoomOut) {
                Label("缩小", systemImage: "minus.magnifyingglass")
            }
            .help("缩小画布")

            Text("\(zoomPercent)%")
                .monospacedDigit()
                .frame(minWidth: 44)
                .accessibilityLabel("缩放比例 \(zoomPercent)%")

            Button(action: zoomIn) {
                Label("放大", systemImage: "plus.magnifyingglass")
            }
            .help("放大画布")

            Button(action: fit) {
                Label("适应画布", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("适应全部内容")
        }
    }
}
