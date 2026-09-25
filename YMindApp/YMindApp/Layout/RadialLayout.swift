import CoreGraphics
import Foundation

enum RadialLayout {
    static func layout(
        document: MindMapDocument,
        measure: TextMeasure
    ) -> LayoutSnapshot {
        var frames: [UUID: NodeFrame] = [:]
        var edges: [EdgeGeometry] = []

        func subtreeHeight(_ node: Node, isRoot: Bool) -> BranchMetadata {
            let size = measure.size(for: node, isRoot: isRoot)
            guard !node.collapsed, !node.children.isEmpty else {
                return BranchMetadata(size: size, height: size.height, children: [])
            }

            let childLayouts = node.children.map {
                subtreeHeight($0, isRoot: false)
            }
            let childrenHeight = childLayouts.reduce(0) { $0 + $1.height }
                + LayoutConstants.vGap * CGFloat(childLayouts.count - 1)

            return BranchMetadata(
                size: size,
                height: max(size.height, childrenHeight),
                children: childLayouts
            )
        }

        func edge(
            from parent: NodeFrame,
            to child: NodeFrame,
            side: Side
        ) -> EdgeGeometry {
            let direction: CGFloat = side == .left ? -1 : 1
            let start = CGPoint(
                x: parent.center.x + direction * parent.size.width / 2,
                y: parent.center.y
            )
            let end = CGPoint(
                x: child.center.x - direction * child.size.width / 2,
                y: child.center.y
            )
            let controlX = (start.x + end.x) / 2

            return EdgeGeometry(
                fromId: parent.id,
                toId: child.id,
                side: side,
                points: [
                    start,
                    CGPoint(x: controlX, y: start.y),
                    CGPoint(x: controlX, y: end.y),
                    end,
                ]
            )
        }

        func placeBranch(
            _ node: Node,
            x: CGFloat,
            yCenter: CGFloat,
            side: Side,
            parent: NodeFrame,
            metadata: BranchMetadata
        ) {
            let frame = NodeFrame(
                id: node.id,
                text: node.text,
                center: CGPoint(x: x, y: yCenter),
                size: metadata.size,
                isRoot: false,
                side: side,
                collapsed: node.collapsed,
                hiddenCount: node.collapsed ? countDescendants(node) : 0
            )
            frames[node.id] = frame
            edges.append(edge(from: parent, to: frame, side: side))

            guard !node.collapsed, !metadata.children.isEmpty else {
                return
            }

            let childrenHeight = metadata.children.reduce(0) { $0 + $1.height }
                + LayoutConstants.vGap * CGFloat(metadata.children.count - 1)
            var childY = yCenter - childrenHeight / 2
            let direction: CGFloat = side == .left ? -1 : 1

            for (index, child) in node.children.enumerated() {
                let childMetadata = metadata.children[index]
                let childCenterY = childY + childMetadata.height / 2
                let childX = x + direction * (
                    metadata.size.width / 2
                        + LayoutConstants.hGap
                        + childMetadata.size.width / 2
                )
                placeBranch(
                    child,
                    x: childX,
                    yCenter: childCenterY,
                    side: side,
                    parent: frame,
                    metadata: childMetadata
                )
                childY += childMetadata.height + LayoutConstants.vGap
            }
        }

        let rootMetadata = subtreeHeight(document.root, isRoot: true)
        let rootFrame = NodeFrame(
            id: document.root.id,
            text: document.root.text,
            center: .zero,
            size: rootMetadata.size,
            isRoot: true,
            side: nil,
            collapsed: document.root.collapsed,
            hiddenCount: document.root.collapsed
                ? countDescendants(document.root)
                : 0
        )
        frames[document.root.id] = rootFrame

        guard !document.root.collapsed else {
            return LayoutSnapshot(
                frames: frames,
                edges: edges,
                branchToggles: makeBranchToggles(frames: frames, root: document.root)
            )
        }

        var leftBranches: [(Node, BranchMetadata)] = []
        var rightBranches: [(Node, BranchMetadata)] = []
        for (index, child) in document.root.children.enumerated() {
            let item = (child, rootMetadata.children[index])
            if child.side == .left {
                leftBranches.append(item)
            } else {
                rightBranches.append(item)
            }
        }

        func placeSide(_ branches: [(Node, BranchMetadata)], side: Side) {
            guard !branches.isEmpty else {
                return
            }

            let totalHeight = branches.reduce(0) { $0 + $1.1.height }
                + LayoutConstants.vGap * CGFloat(branches.count - 1)
            var childY = -totalHeight / 2
            let direction: CGFloat = side == .left ? -1 : 1

            for (child, metadata) in branches {
                let yCenter = childY + metadata.height / 2
                let x = direction * (
                    rootFrame.size.width / 2
                        + LayoutConstants.hGap
                        + metadata.size.width / 2
                )
                placeBranch(
                    child,
                    x: x,
                    yCenter: yCenter,
                    side: side,
                    parent: rootFrame,
                    metadata: metadata
                )
                childY += metadata.height + LayoutConstants.vGap
            }
        }

        placeSide(leftBranches, side: .left)
        placeSide(rightBranches, side: .right)
        return LayoutSnapshot(
            frames: frames,
            edges: edges,
            branchToggles: makeBranchToggles(frames: frames, root: document.root)
        )
    }

    private static func makeBranchToggles(
        frames: [UUID: NodeFrame],
        root: Node
    ) -> [BranchToggle] {
        var toggles: [BranchToggle] = []
        var nodesById: [UUID: Node] = [:]

        func index(_ node: Node) {
            nodesById[node.id] = node
            for child in node.children {
                index(child)
            }
        }
        index(root)

        for (id, frame) in frames {
            guard let node = nodesById[id] else { continue }
            appendToggles(for: node, frame: frame, into: &toggles)
        }
        return toggles
    }

    private static func appendToggles(
        for node: Node,
        frame: NodeFrame,
        into toggles: inout [BranchToggle]
    ) {
        guard !node.children.isEmpty else { return }
        if frame.isRoot {
            let hasLeft = node.children.contains { $0.side == .left }
            let hasRight = node.children.contains { $0.side != .left }
            if node.collapsed || hasLeft {
                toggles.append(makeToggle(node: node, frame: frame, side: .left))
            }
            if node.collapsed || hasRight {
                toggles.append(makeToggle(node: node, frame: frame, side: .right))
            }
        } else if let side = frame.side {
            toggles.append(makeToggle(node: node, frame: frame, side: side))
        }
    }

    private static func makeToggle(
        node: Node,
        frame: NodeFrame,
        side: Side
    ) -> BranchToggle {
        let dir: CGFloat = side == .left ? -1 : 1
        return BranchToggle(
            nodeId: node.id,
            side: side,
            center: CGPoint(
                x: frame.center.x + dir * (frame.size.width / 2 + LayoutConstants.branchToggleGap),
                y: frame.center.y
            ),
            collapsed: node.collapsed,
            hiddenCount: node.collapsed ? countDescendants(node) : 0
        )
    }

    private static func countDescendants(_ node: Node) -> Int {
        node.children.reduce(0) {
            $0 + 1 + countDescendants($1)
        }
    }

    private struct BranchMetadata {
        let size: NodeSize
        let height: CGFloat
        let children: [BranchMetadata]
    }
}
