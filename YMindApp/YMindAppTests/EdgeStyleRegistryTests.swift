import CoreGraphics
import Foundation
import Testing
@testable import YMindApp

@Suite("EdgeStyleRegistry")
struct EdgeStyleRegistryTests {
    /// 每个 EdgeStyle case 都必须解析出一个真实 Provider（非 EmptyProvider 占位）。
    @Test func everyStyle_resolvesToAProvider() {
        for style in EdgeStyle.allCases {
            let provider = EdgeStyleRegistry.provider(for: style)
            #expect(type(of: provider) != EmptyProvider.self)
        }
    }

    /// 有效排布判定：brace 强制逻辑树（true），elbow/curve 沿用文档布局（false）。
    @Test func requiresLogicArrangement_elbowAndCurveFalse_braceTrue() {
        #expect(EdgeStyleRegistry.provider(for: .elbow).requiresLogicArrangement == false)
        #expect(EdgeStyleRegistry.provider(for: .curve).requiresLogicArrangement == false)
        #expect(EdgeStyleRegistry.provider(for: .brace).requiresLogicArrangement == true)
    }
}

@Suite("ElbowProvider")
struct ElbowProviderTests {
    private func connectors(_ doc: MindMapDocument) -> [ConnectorGeometry] {
        // 排布按文档布局取（logic 测试用 LogicLayout，其余 radial）。
        let frames: [UUID: NodeFrame] = doc.layout == .logic
            ? LogicLayout.place(document: doc, measure: TextMeasure()).frames
            : RadialLayout.place(document: doc, measure: TextMeasure()).frames
        return ElbowProvider().connectors(document: doc, frames: frames, root: doc.root, measure: TextMeasure())
    }

    /// 单根无子 → 无连线。
    @Test func singleRoot_producesNoConnectors() {
        #expect(connectors(MindMapDocument.blank()).isEmpty)
    }

    /// 右子：从父右缘水平出 → 中点竖折 → 子左缘水平进（4 点正交折线）。
    @Test func rightChild_producesMidpointElbow() throws {
        var doc = MindMapDocument.blank()
        let child = Node(text: "子", side: .right)
        doc.root.children = [child]
        let frames = RadialLayout.place(document: doc, measure: TextMeasure()).frames
        let root = try #require(frames[doc.root.id])
        let cf = try #require(frames[child.id])

        let connector = try #require(connectors(doc).first)
        #expect(connector.id == child.id)
        #expect(connector.marker == nil)
        #expect(connector.path.count == 4)

        let start = CGPoint(x: root.rect.maxX, y: root.center.y)
        let end = CGPoint(x: cf.rect.minX, y: cf.center.y)
        let mx = (start.x + end.x) / 2
        #expect(connector.path[0] == start)
        #expect(connector.path[1] == CGPoint(x: mx, y: start.y))
        #expect(connector.path[2] == CGPoint(x: mx, y: end.y))
        #expect(connector.path[3] == end)
    }

    /// 左子：父左缘出、子右缘进，方向相反。
    @Test func leftChild_usesOppositeDirection() throws {
        var doc = MindMapDocument.blank()
        let child = Node(text: "L", side: .left)
        doc.root.children = [child]
        let frames = RadialLayout.place(document: doc, measure: TextMeasure()).frames
        let root = try #require(frames[doc.root.id])
        let cf = try #require(frames[child.id])

        let connector = try #require(connectors(doc).first)
        #expect(connector.path[0] == CGPoint(x: root.rect.minX, y: root.center.y))
        #expect(connector.path[3] == CGPoint(x: cf.rect.maxX, y: cf.center.y))
    }

    /// 两级：每个父子对一条线；方向随子 frame.side（孙继承父 side，模型侧可为 nil）。
    @Test func twoLevels_producesOneConnectorPerParentChildPair() throws {
        var doc = MindMapDocument.blank()
        let grandchild = Node(text: "孙")
        let child = Node(text: "子", side: .left, children: [grandchild])
        doc.root.children = [child]
        let frames = RadialLayout.place(document: doc, measure: TextMeasure()).frames
        let cf = try #require(frames[child.id])
        let gf = try #require(frames[grandchild.id])

        let all = connectors(doc)
        #expect(all.count == 2)
        let grandConnector = try #require(all.last)
        #expect(grandConnector.id == grandchild.id)
        // 子 → 孙：孙 frame.side 继承 .left。
        #expect(grandConnector.path[0] == CGPoint(x: cf.rect.minX, y: cf.center.y))
        #expect(grandConnector.path[3] == CGPoint(x: gf.rect.maxX, y: gf.center.y))
    }

    /// 逻辑图排布下（父左子右，frame.side 全 .right）同样按中点折线。
    @Test func logicArrangement_rightSideElbow() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let a = Node(text: "章")
        doc.root.children = [a]
        let frames = LogicLayout.place(document: doc, measure: TextMeasure()).frames
        let root = try #require(frames[doc.root.id])
        let af = try #require(frames[a.id])

        let connector = try #require(connectors(doc).first)
        #expect(connector.path[0] == CGPoint(x: root.rect.maxX, y: root.center.y))
        #expect(connector.path[3] == CGPoint(x: af.rect.minX, y: af.center.y))
        let mx = (root.rect.maxX + af.rect.minX) / 2
        #expect(connector.path[1].x == mx)
        #expect(connector.path[2].x == mx)
    }
}

@Suite("CurveProvider")
struct CurveProviderTests {
    /// 三次贝塞尔参数式（测试端独立计算，校验采样点落在 spec 控制点定义的曲线上）。
    private func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p1.x,
            y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p1.y
        )
    }

    private func assertCurve(
        from: CGPoint, to: CGPoint,
        c1: CGPoint, c2: CGPoint,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let path = LayoutSupport.edgePoints(from: from, to: to, style: .curve)
        #expect(path.count == 21)
        #expect(path.first == from)
        #expect(path.last == to)
        // 采样点（1/20、19/20）落在该控制点定义的曲线上 → 锁定控制点公式与采样。
        #expect(path[1] == cubic(from, c1, c2, to, 1.0 / 20.0))
        #expect(path[19] == cubic(from, c1, c2, to, 19.0 / 20.0))
        // 首采样点 x 已向 c1 方向移动（水平主导边首段切向水平，x 单调推进）。
        #expect(path[1].x != from.x)
    }

    /// 水平主导边（|dx|>=|dy|）：水平切向控制点、k=clamp(|dx|·0.4, 18, 56)。
    @Test func horizontalEdge_usesHorizontalTangents() {
        let from = CGPoint(x: 100, y: 50)
        let to = CGPoint(x: 300, y: 60)
        let k = max(18, min(56, abs(200) * 0.4))  // 80 → 56
        assertCurve(from: from, to: to,
                    c1: CGPoint(x: 100 + k, y: 50),
                    c2: CGPoint(x: 300 - k, y: 60))
    }

    /// 水平主导但反向（dx<0）：dir 取反。
    @Test func horizontalEdge_backwards_controlPointsFlip() {
        let from = CGPoint(x: 300, y: 50)
        let to = CGPoint(x: 100, y: 60)
        let k = max(18, min(56, abs(200) * 0.4))
        assertCurve(from: from, to: to,
                    c1: CGPoint(x: 300 - k, y: 50),
                    c2: CGPoint(x: 100 + k, y: 60))
    }

    /// 垂直主导边（|dy|>|dx|）：垂直切向控制点。
    @Test func verticalEdge_usesVerticalTangents() {
        let from = CGPoint(x: 100, y: 50)
        let to = CGPoint(x: 105, y: 300)
        let k = max(18, min(56, abs(250) * 0.4))  // 100 → 56
        assertCurve(from: from, to: to,
                    c1: CGPoint(x: 100, y: 50 + k),
                    c2: CGPoint(x: 105, y: 300 - k))
    }

    /// 斜边（|dx|==|dy|）按水平主导处理（>=）。
    @Test func diagonalEdge_horizontalDominant() {
        let from = CGPoint(x: 100, y: 100)
        let to = CGPoint(x: 300, y: 300)
        let k = max(18, min(56, abs(200) * 0.4))
        assertCurve(from: from, to: to,
                    c1: CGPoint(x: 100 + k, y: 100),
                    c2: CGPoint(x: 300 - k, y: 300))
    }

    /// k 下限 18：极短水平边。
    @Test func shortEdge_kClampedToMinimum() {
        let from = CGPoint(x: 100, y: 50)
        let to = CGPoint(x: 120, y: 50)
        let k = max(18, min(56, abs(20) * 0.4))  // 8 → 18
        assertCurve(from: from, to: to,
                    c1: CGPoint(x: 100 + k, y: 50),
                    c2: CGPoint(x: 120 - k, y: 50))
    }

    /// 每边产一个曲线 Connector（frame.side 决定方向），21 点采样。
    @Test func perEdge_producesSampledCurves() throws {
        var doc = MindMapDocument.blank()
        let child = Node(text: "子", side: .right)
        doc.root.children = [child]
        let frames = RadialLayout.place(document: doc, measure: TextMeasure()).frames
        let connectors = CurveProvider().connectors(
            document: doc, frames: frames, root: doc.root, measure: TextMeasure()
        )
        #expect(connectors.count == 1)
        let c = try #require(connectors.first)
        #expect(c.id == child.id)
        #expect(c.marker == nil)
        #expect(c.path.count == 21)
    }
}

@Suite("BraceProvider")
struct BraceProviderTests {
    /// 构造一个根 + 两子（多子）文档并取逻辑排布 frames（brace 强制逻辑树）。
    private func multiChildDoc() -> (doc: MindMapDocument, frames: [UUID: NodeFrame]) {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.root.children = [Node(text: "章一"), Node(text: "章二")]
        let frames = LogicLayout.place(document: doc, measure: TextMeasure()).frames
        return (doc, frames)
    }

    private func braceConnectors(_ doc: MindMapDocument, frames: [UUID: NodeFrame]) -> [ConnectorGeometry] {
        BraceProvider().connectors(document: doc, frames: frames, root: doc.root, measure: TextMeasure())
    }

    /// 多子：yTop=首子 center.y、yBottom=末子 center.y、嘴 yMid=(yTop+yBottom)/2=父 center.y。
    /// 根括号带圆圈 → xTip=mouthX+15。
    @Test func multiChild_mouthAlignsToParentCenter() throws {
        let (doc, frames) = multiChildDoc()
        let root = try #require(frames[doc.root.id])
        let a = try #require(frames[doc.root.children[0].id])
        let b = try #require(frames[doc.root.children[1].id])

        let connectors = braceConnectors(doc, frames: frames)
        #expect(connectors.count == 1)  // 仅根有子
        let c = try #require(connectors.first)
        #expect(c.id == doc.root.id)

        let yTop = a.center.y
        let yBottom = b.center.y
        let yMid = (yTop + yBottom) / 2
        #expect(yMid == root.center.y)  // 等高等子：嘴对准父

        let mouthX = root.rect.maxX
        let w: CGFloat = 56  // 主括号
        let xTip = mouthX + 15  // 根带圆圈
        let xStem = mouthX + w * 0.54
        let xRight = mouthX + w - 8
        let r = min(16, (yBottom - yTop) / 4, xRight - xStem, xStem - xTip)

        // path 首段 = 父→嘴 短直线。
        #expect(c.path.first == CGPoint(x: mouthX, y: yMid))
        #expect(c.path.contains(CGPoint(x: xTip, y: yMid)))
        #expect(c.path.contains(CGPoint(x: xRight, y: yTop)))
        #expect(c.path.contains(CGPoint(x: xRight, y: yBottom)))
        #expect(c.path.contains(CGPoint(x: xStem, y: yMid - r)))
        #expect(c.path.contains(CGPoint(x: xStem, y: yMid + r)))
        // 根带圆圈标记。
        let marker = try #require(c.marker)
        #expect(marker.kind == .circle)
        #expect(marker.radius == 4.5)
        #expect(marker.center == CGPoint(x: xTip - 4.5 - 1, y: yMid))
    }

    /// 单子：span=max(子高·0.85, 28)，yTop=cy−span/2、yBottom=cy+span/2。
    @Test func singleChild_minSpanOpensAroundChild() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        let chapter = Node(text: "章")
        doc.root.children = [chapter]
        let frames = LogicLayout.place(document: doc, measure: TextMeasure()).frames
        let root = try #require(frames[doc.root.id])
        let cf = try #require(frames[chapter.id])

        let c = try #require(braceConnectors(doc, frames: frames).first)
        let span = max(cf.size.height * 0.85, 28)
        let yTop = cf.center.y - span / 2
        let yBottom = cf.center.y + span / 2
        let yMid = (yTop + yBottom) / 2
        #expect(yMid == root.center.y)
        // 根带圆圈 → xTip=mouthX+15。
        #expect(c.path.contains(CGPoint(x: root.rect.maxX + 15, y: yMid)))
        #expect(c.path.contains(CGPoint(x: root.rect.maxX + 56 - 8, y: yTop)))
        #expect(c.path.contains(CGPoint(x: root.rect.maxX + 56 - 8, y: yBottom)))
    }

    /// 每个有子的父一个 Connector；子级括号宽度 34、无圆圈。
    @Test func nestedBraces_onePerParentWithChildren() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        let grand = Node(text: "节")
        let chapter = Node(text: "章", children: [grand])
        doc.root.children = [chapter]
        let frames = LogicLayout.place(document: doc, measure: TextMeasure()).frames
        let chapterFrame = try #require(frames[chapter.id])
        let grandFrame = try #require(frames[grand.id])

        let connectors = braceConnectors(doc, frames: frames)
        #expect(connectors.count == 2)  // 根→[章]、章→[节]
        // 根括号：主宽度 56 + 根圆圈标记。
        let rootBrace = try #require(connectors.first { $0.id == doc.root.id })
        let marker = try #require(rootBrace.marker)
        #expect(marker.kind == .circle)
        #expect(marker.radius == 4.5)
        // 子括号：宽度 34、无圆圈；单子按最小跨度张开。
        let childBrace = try #require(connectors.first { $0.id == chapter.id })
        #expect(childBrace.marker == nil)
        let mouthX = chapterFrame.rect.maxX
        let span = max(grandFrame.size.height * 0.85, 28)
        #expect(childBrace.path.contains(CGPoint(x: mouthX + 34 - 8, y: grandFrame.center.y - span / 2)))
        #expect(childBrace.path.contains(CGPoint(x: mouthX + 34 - 8, y: grandFrame.center.y + span / 2)))
    }
}
