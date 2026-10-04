import CoreGraphics
import Foundation

/// 逻辑图（总分树）布局：根在最左、每一层子节点垂直排列在父节点右侧、递归向右展开。
/// 与 `RadialLayout` 结构同构（LayoutSupport.subtreeHeight 测高 → 递归排布）。
enum LogicLayout {
    static func layout(document: MindMapDocument, measure: TextMeasure) -> LayoutSnapshot {
        var frames: [UUID: NodeFrame] = [:]
        var edges: [EdgeGeometry] = []

        func edge(from parent: NodeFrame, to child: NodeFrame) -> EdgeGeometry {
            let start = CGPoint(x: parent.rect.maxX, y: parent.center.y)
            let end = CGPoint(x: child.rect.minX, y: child.center.y)
            return EdgeGeometry(
                fromId: parent.id,
                toId: child.id,
                side: .right,
                points: [start, CGPoint(x: end.x, y: start.y), CGPoint(x: end.x, y: end.y), end]
            )
        }

        func placeBranch(
            _ node: Node,
            x: CGFloat,
            yCenter: CGFloat,
            parent: NodeFrame,
            metadata: BranchMetadata
        ) {
            let frame = NodeFrame(
                id: node.id,
                text: node.text,
                center: CGPoint(x: x, y: yCenter),
                size: metadata.size,
                isRoot: false,
                side: .right,
                collapsed: node.collapsed,
                hiddenCount: node.collapsed ? LayoutSupport.countDescendants(node) : 0,
                fill: node.fill,
                blocks: LayoutSupport.centeredBlocks(from: metadata)
            )
            frames[node.id] = frame
            edges.append(edge(from: parent, to: frame))

            guard !node.collapsed, !metadata.children.isEmpty else { return }

            let childrenHeight = metadata.children.reduce(0) { $0 + $1.height }
                + LayoutConstants.vGap * CGFloat(metadata.children.count - 1)
            var childY = yCenter - childrenHeight / 2
            for (index, child) in node.children.enumerated() {
                let childMetadata = metadata.children[index]
                let childCenterY = childY + childMetadata.height / 2
                let childX = frame.rect.maxX + LayoutConstants.hGap + childMetadata.size.width / 2
                placeBranch(child, x: childX, yCenter: childCenterY, parent: frame, metadata: childMetadata)
                childY += childMetadata.height + LayoutConstants.vGap
            }
        }

        let rootCollapsed = document.root.collapsedLeft && document.root.collapsedRight
        // 全折叠时只测根自身（早退只画根，避免根框被整树高撑大）。
        var layoutRoot = document.root
        if rootCollapsed { layoutRoot.children = [] }
        let rootMetadata = LayoutSupport.subtreeHeight(layoutRoot, isRoot: true, measure: measure)
        let rootFrame = NodeFrame(
            id: document.root.id,
            text: document.root.text,
            center: CGPoint(x: LayoutConstants.rootPadX + rootMetadata.size.width / 2, y: 0),
            size: rootMetadata.size,
            isRoot: true,
            side: nil,
            collapsed: rootCollapsed,
            hiddenCount: rootCollapsed
                ? LayoutSupport.countDescendants(document.root)
                : 0,
            fill: document.root.fill,
            blocks: LayoutSupport.centeredBlocks(from: rootMetadata)
        )
        frames[document.root.id] = rootFrame

        // 根折叠早退：此时仅根有 frame，只收集根的载荷（与 RadialLayout 一致）。
        let rootPayloads = LayoutSupport.collectImagePayloads(root: document.root, frames: frames)

        guard !rootCollapsed else {
            return LayoutSnapshot(
                frames: frames,
                edges: edges,
                branchToggles: makeBranchToggles(frames: frames, root: document.root),
                imagePayloads: rootPayloads
            )
        }

        let childrenHeight = rootMetadata.children.reduce(0) { $0 + $1.height }
            + LayoutConstants.vGap * CGFloat(rootMetadata.children.count - 1)
        var childY = rootFrame.center.y - childrenHeight / 2
        for (index, child) in document.root.children.enumerated() {
            let childMetadata = rootMetadata.children[index]
            let childCenterY = childY + childMetadata.height / 2
            let childX = rootFrame.rect.maxX + LayoutConstants.hGap + childMetadata.size.width / 2
            placeBranch(child, x: childX, yCenter: childCenterY, parent: rootFrame, metadata: childMetadata)
            childY += childMetadata.height + LayoutConstants.vGap
        }

        // 所有节点已有 frame 后再收集全部图片载荷（避免丢非根图片；与 RadialLayout 一致）。
        let payloads = LayoutSupport.collectImagePayloads(root: document.root, frames: frames)
        return LayoutSnapshot(
            frames: frames,
            edges: edges,
            branchToggles: makeBranchToggles(frames: frames, root: document.root),
            imagePayloads: payloads
        )
    }

    private static func makeBranchToggles(frames: [UUID: NodeFrame], root: Node) -> [BranchToggle] {
        var toggles: [BranchToggle] = []
        var nodesById: [UUID: Node] = [:]
        func index(_ node: Node) {
            nodesById[node.id] = node
            for child in node.children { index(child) }
        }
        index(root)
        for (id, frame) in frames {
            guard let node = nodesById[id], !node.children.isEmpty else { continue }
            if frame.isRoot {
                // 逻辑图根无左右侧折叠概念：根折叠 = 左右两侧同时折叠的聚合态。
                let rootCollapsed = node.collapsedLeft && node.collapsedRight
                toggles.append(LayoutSupport.makeToggle(
                    node: node,
                    frame: frame,
                    side: .right,
                    collapsed: rootCollapsed,
                    hiddenCount: rootCollapsed ? LayoutSupport.countDescendants(node) : 0
                ))
            } else {
                toggles.append(LayoutSupport.makeToggle(node: node, frame: frame, side: .right))
            }
        }
        // 按 nodeId 确定性排序：frames 字典遍历序随机，须保证 LayoutSnapshot Equatable 确定（仿 MetalRenderer.orderedFrames）。
        return toggles.sorted { $0.nodeId.uuidString < $1.nodeId.uuidString }
    }
}

extension LogicLayout: LayoutEngine {}
