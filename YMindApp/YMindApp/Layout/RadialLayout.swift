import CoreGraphics
import Foundation

enum RadialLayout {
    static func layout(
        document: MindMapDocument,
        measure: TextMeasure
    ) -> LayoutSnapshot {
        var frames: [UUID: NodeFrame] = [:]
        var edges: [EdgeGeometry] = []

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
                hiddenCount: node.collapsed ? LayoutSupport.countDescendants(node) : 0,
                fill: node.fill,
                blocks: LayoutSupport.centeredBlocks(from: metadata)
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

        let rootMetadata = LayoutSupport.subtreeHeight(document.root, isRoot: true, measure: measure)
        let rootFrame = NodeFrame(
            id: document.root.id,
            text: document.root.text,
            center: .zero,
            size: rootMetadata.size,
            isRoot: true,
            side: nil,
            collapsed: document.root.collapsed,
            hiddenCount: document.root.collapsed
                ? LayoutSupport.countDescendants(document.root)
                : 0,
            fill: document.root.fill,
            blocks: LayoutSupport.centeredBlocks(from: rootMetadata)
        )
        frames[document.root.id] = rootFrame

        // 此时仅根有 frame：折叠早退只需根（及后代无 frame 会被跳过）的载荷。
        let rootPayloads = LayoutSupport.collectImagePayloads(root: document.root, frames: frames)

        guard !document.root.collapsed else {
            return LayoutSnapshot(
                frames: frames,
                edges: edges,
                branchToggles: makeBranchToggles(frames: frames, root: document.root),
                imagePayloads: rootPayloads
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
        // 所有节点已有 frame：此时收集才覆盖全部非折叠节点的图片块。
        let payloads = LayoutSupport.collectImagePayloads(root: document.root, frames: frames)
        return LayoutSnapshot(
            frames: frames,
            edges: edges,
            branchToggles: makeBranchToggles(frames: frames, root: document.root),
            imagePayloads: payloads
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
                toggles.append(LayoutSupport.makeToggle(node: node, frame: frame, side: .left))
            }
            if node.collapsed || hasRight {
                toggles.append(LayoutSupport.makeToggle(node: node, frame: frame, side: .right))
            }
        } else if let side = frame.side {
            toggles.append(LayoutSupport.makeToggle(node: node, frame: frame, side: side))
        }
    }
}

extension RadialLayout: LayoutEngine {}
