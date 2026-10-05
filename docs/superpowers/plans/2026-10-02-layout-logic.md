# 新增布局类型（逻辑图·总分树 + 布局切换器）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让同一棵树能在「辐射」与「逻辑图（总分树）」间无损、瞬时切换，布局随 `.linva` 持久化，逻辑图下 side 操作降级置灰，PNG 按当前布局导出。

**Architecture:** 新增 `LogicLayout`（总分树，根左、层向右、L 形边），与 `RadialLayout` 共享 `LayoutSupport` 辅助；`LayoutPipeline.relayout` 按 `document.layout` 分派引擎（删引擎注入）。`MindMapDocument` 增 `layout: LayoutKind`（Codec v5），`setLayout` 命令入命令栈，`DocumentSession` 暴露 `layout` 并在布局变化时经 `markDirtyAndRelayout` 统一触发自动 fit。Render/命中/选中/折叠零改动（只消费 `LayoutSnapshot`）。

**Tech Stack:** Swift 6, SwiftUI, Metal, `swift-testing`（`Testing`/`#expect`）。

**Spec:** `docs/superpowers/specs/2026-10-02-linva-layout-logic-design.md`（决策 D1–D5，实现以 spec 为准）。

## Global Constraints

- `MindMapDocument.currentVersion = 5`（硬校验，迁移链 v1–v4 保留，末尾追加 v4→v5）。
- `LayoutKind: String, Codable, Sendable, Equatable, Hashable { case radial, logic }`。
- `Layout/` 层白名单 `Foundation AppKit CoreGraphics CoreText`——`LayoutSupport.swift`/`LogicLayout.swift` 只允许 `import CoreGraphics`/`import Foundation`。
- 改树必走命令栈：`setLayout` 必须 `commandBus.execute`，`MindMapModel.setLayout` 返回旧值供 Undo；no-op（kind 相同）返回 `nil` 不入栈。
- `sanitize` 重建文档必须保留 `layout`，否则逻辑图文档消毒后被重置为辐射。
- 逻辑图 `NodeFrame.side` 统一 `.right`；**模型层 `Node.side` 不动**。
- 间距复用 `LayoutConstants.hGap/vGap`（56/16）；根左缘贴 `LayoutConstants.rootPadX`。
- ⌥L 循环切换（`keyboardShortcut("l", modifiers: .option)`）。
- 自动 fit：`DocumentSession.markDirtyAndRelayout()` 统一触发（工具栏切换与 ⌘Z/⌘⇧Z 往返全覆盖），不在 `setLayout` 单独 bump。
- 文档/代码注释中文优先（专有名词/标识符可英文）。

---

## File Structure

- **Create** `LinvaApp/LinvaApp/Layout/LayoutSupport.swift` — 共享测高/块/toggle/载荷辅助 + `BranchMetadata`。
- **Create** `LinvaApp/LinvaApp/Layout/LogicLayout.swift` — 总分树引擎（`extension LogicLayout: LayoutEngine {}`）。
- **Create** `LinvaAppTests/LogicLayoutTests.swift` — LogicLayout 单测。
- **Modify** `LinvaApp/LinvaApp/Model/MindMapDocument.swift` — `LayoutKind` + `layout` 字段 + `currentVersion = 5` + 自定义 `init(from:)`。
- **Modify** `LinvaApp/LinvaApp/Model/LinvaCodec.swift` — v4→v5 迁移 + sanitize 保留 layout。
- **Modify** `LinvaApp/LinvaApp/Layout/RadialLayout.swift` — 改用 `LayoutSupport` 共享辅助（行为不变）。
- **Modify** `LinvaApp/LinvaApp/Session/LayoutPipeline.swift` — 按 `document.layout` 分派，删引擎注入。
- **Modify** `LinvaApp/LinvaApp/Commands/MindMapCommand.swift` — 增 `setLayout(kind:)`。
- **Modify** `LinvaApp/LinvaApp/Model/MindMapModel.swift` — 增 `setLayout(_:) -> LayoutKind?`。
- **Modify** `LinvaApp/LinvaApp/Commands/CommandBus.swift` — `applyForward` 增 `.setLayout` 分支。
- **Modify** `LinvaApp/LinvaApp/Session/DocumentSession.swift` — `layout` 属性、`setLayout(_:)`、`canSetSide` 降级、`fitVersion`/`appliedLayoutForFit`。
- **Modify** `LinvaApp/LinvaApp/Render/CanvasMetalView.swift` — `CanvasMTKView.appliedFitVersion` + `updateNSView` 观察 `fitVersion`。
- **Modify** `LinvaApp/LinvaApp/Session/DropIntent.swift` — 逻辑图下侧向意图禁用。
- **Modify** `LinvaApp/LinvaApp/App/MainToolbar.swift` — 布局 `Picker(.menu)`。
- **Modify** `LinvaApp/LinvaApp/ContentView.swift` — 传 `layout`/`setLayout` 给 MainToolbar。
- **Modify** `LinvaApp/LinvaApp/LinvaAppApp.swift` — `DocumentCommands` 增 ⌥L 切换。
- **Modify** `LinvaApp/LinvaApp/Render/PNGExporter.swift` — 按 `layout` 分派产快照。
- **Modify** `LinvaAppTests/CodecTests.swift`、`LayoutPipelineTests.swift`、`CommandBusTests.swift`、`DocumentSessionTests.swift`、`DropIntentTests.swift`、`PNGExporterTests.swift`。
- **Modify** `docs/架构现状.md`；`.agents/skills/linva-codec-version/SKILL.md`、`linva-layout-snapshot/SKILL.md`、`linva-command/SKILL.md`。

任务顺序（强依赖链）：1 Codec → 2 LayoutSupport → 3 LogicLayout → 4 Pipeline 分派 → 5 命令 → 6 Session/Canvas → 7 DropIntent → 8 UI → 9 PNG → 10 文档/验证。

---

## Task 1: Codec v5 — LayoutKind + layout 字段 + 迁移 + sanitize 保留

**Files:**
- Modify: `LinvaApp/LinvaApp/Model/MindMapDocument.swift`
- Modify: `LinvaApp/LinvaApp/Model/LinvaCodec.swift`
- Test: `LinvaAppTests/CodecTests.swift`

**Interfaces:**
- Consumes: 既有 `MindMapDocument`/`Node` Codable。
- Produces: `LayoutKind`（`case radial/logic`）、`MindMapDocument.layout: LayoutKind`、`MindMapDocument.currentVersion == 5`。

- [ ] **Step 1: 先把既有断言升到 5，再写失败测试**

`LinvaAppTests/CodecTests.swift` 里 8 处 `#expect(...version == 4)`（`migratesV1ToV2`、`unknownFillToken_decodesAsNil`、`imageRoundTrip`、`v2FileWithoutImage_opensWithoutReject`、`v1File_chainMigrates`、`invalidImagePixelSize_decodesAsNil`、`v3FileWithImage_migratesToBlocks_imageAboveText`、`v4RoundTrip_blocksPreserved`）全部改为 `== 5`。然后在 `CodecTests` suite 末尾加：

```swift
    @Test func layoutRoundTrip_preservesLogicAndRadial() throws {
        var logic = MindMapDocument.blank(rootText: "根")
        logic.layout = .logic
        let logicBack = try LinvaCodec.decode(try LinvaCodec.encode(logic))
        #expect(logicBack.layout == .logic)

        let radial = MindMapDocument.blank(rootText: "根")
        let radialBack = try LinvaCodec.decode(try LinvaCodec.encode(radial))
        #expect(radialBack.layout == .radial)
    }

    @Test func v4FileWithoutLayout_decodesAsRadial() throws {
        let json = """
        {"version":4,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"children":[]}}
        """.data(using: .utf8)!
        let back = try LinvaCodec.decode(json)
        #expect(back.version == 5)
        #expect(back.layout == .radial)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' -only-testing:LinvaAppTests/CodecTests`
Expected: FAIL（编译失败：`LayoutKind`/`layout` 未定义；v4 用例编译过了但断言 5 vs 实际 4）。

- [ ] **Step 3: 实现**

`LinvaApp/LinvaApp/Model/MindMapDocument.swift` 整体替换为：

```swift
import Foundation

/// 文档布局类型：同一棵树的画布排布方式（随 `.linva` 持久化，v5）。
enum LayoutKind: String, Codable, Sendable, Equatable, Hashable {
    /// 中心辐射：根在中心、左右对称展开（v1 起默认）。
    case radial
    /// 逻辑图（总分树）：根在最左、层级向右层层展开。
    case logic
}

struct MindMapDocument: Equatable, Codable, Sendable {
    static let currentVersion = 5
    var version: Int
    var root: Node
    /// 布局（文档属性，v5 起持久化；v4 及以下缺省 .radial，零拒绝迁移）。
    var layout: LayoutKind = .radial

    init(version: Int, root: Node, layout: LayoutKind = .radial) {
        self.version = version
        self.root = root
        self.layout = layout
    }

    static func blank(rootText: String = "中心主题") -> MindMapDocument {
        MindMapDocument(version: currentVersion, root: Node(text: rootText))
    }

    private enum CodingKeys: String, CodingKey {
        case version, root, layout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        root = try c.decode(Node.self, forKey: .root)
        // v4 及以下无 layout 字段 → 缺省 .radial（同 fill/image/blocks 缺省容错模式）。
        layout = try c.decodeIfPresent(LayoutKind.self, forKey: .layout) ?? .radial
    }
}
```

`LinvaApp/LinvaApp/Model/LinvaCodec.swift` 两处编辑：

① 迁移：在 v3→v4 块后、`guard doc.version == MindMapDocument.currentVersion` 前插入：

```swift
        // 迁移：v4 → v5（layout 缺省 .radial；MindMapDocument 解码器对缺失 layout 天然容错）。
        if doc.version == 4 {
            doc.version = 5
        }
```

② sanitize：末尾重建文档改为保留 layout：

```swift
        // layout 是文档属性：sanitize 重建时须保留，否则逻辑图文档消毒后被重置为辐射。
        return MindMapDocument(version: document.version, root: root, layout: document.layout)
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同上 `-only-testing:LinvaAppTests/CodecTests`
Expected: PASS（含新增 2 例）。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Model/MindMapDocument.swift LinvaApp/LinvaApp/Model/LinvaCodec.swift LinvaAppTests/CodecTests.swift
git commit -m "feat: 文档布局字段 LayoutKind + Codec v5 迁移（layout 缺省 radial）"
```

---

## Task 2: 提取 LayoutSupport 共享辅助 + RadialLayout 瘦身

**Files:**
- Create: `LinvaApp/LinvaApp/Layout/LayoutSupport.swift`
- Modify: `LinvaApp/LinvaApp/Layout/RadialLayout.swift`
- Test: `LinvaAppTests/RadialLayoutTests.swift`（既有，作回归守卫）

**Interfaces:**
- Consumes: `NodeFrame`/`BranchToggle`/`BlockLayoutFrame`/`ImagePayload`/`NodeSize`/`LayoutConstants`（均已有）。
- Produces: `struct BranchMetadata { size: NodeSize; height: CGFloat; blocks: [BlockLayoutFrame]; children: [BranchMetadata] }`；`enum LayoutSupport` 静态方法：`subtreeHeight(_:isRoot:measure:) -> BranchMetadata`、`centeredBlocks(from:) -> [BlockLayoutFrame]`、`countDescendants(_:) -> Int`、`makeToggle(node:frame:side:) -> BranchToggle`、`collectImagePayloads(root:frames:) -> [UUID: ImagePayload]`。

- [ ] **Step 1: 新建 LayoutSupport.swift**

```swift
import CoreGraphics
import Foundation

/// 布局共享的递归测高元数据：RadialLayout 与 LogicLayout 共用。
struct BranchMetadata {
    let size: NodeSize
    let height: CGFloat
    let blocks: [BlockLayoutFrame]
    let children: [BranchMetadata]
}

/// 布局共享辅助：测高 / 块映射 / toggle / 图片载荷，供两种布局引擎复用。
enum LayoutSupport {
    static func subtreeHeight(_ node: Node, isRoot: Bool, measure: TextMeasure) -> BranchMetadata {
        let m = measure.measure(for: node, isRoot: isRoot)
        let size = m.size
        guard !node.collapsed, !node.children.isEmpty else {
            return BranchMetadata(size: size, height: size.height, blocks: m.blocks, children: [])
        }
        let childLayouts = node.children.map { subtreeHeight($0, isRoot: false, measure: measure) }
        let childrenHeight = childLayouts.reduce(0) { $0 + $1.height }
            + LayoutConstants.vGap * CGFloat(childLayouts.count - 1)
        return BranchMetadata(
            size: size,
            height: max(size.height, childrenHeight),
            blocks: m.blocks,
            children: childLayouts
        )
    }

    static func centeredBlocks(from metadata: BranchMetadata) -> [BlockLayoutFrame] {
        metadata.blocks.map { b -> BlockLayoutFrame in
            if b.text != nil {
                return BlockLayoutFrame(
                    blockId: b.blockId,
                    text: b.text,
                    rect: CGRect(x: 0, y: b.rect.minY, width: metadata.size.width, height: b.rect.height)
                )
            }
            return BlockLayoutFrame(
                blockId: b.blockId,
                text: nil,
                rect: CGRect(
                    x: (metadata.size.width - b.rect.width) / 2,
                    y: b.rect.minY,
                    width: b.rect.width,
                    height: b.rect.height
                )
            )
        }
    }

    static func countDescendants(_ node: Node) -> Int {
        node.children.reduce(0) { $0 + 1 + countDescendants($1) }
    }

    static func makeToggle(node: Node, frame: NodeFrame, side: Side) -> BranchToggle {
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

    static func collectImagePayloads(root: Node, frames: [UUID: NodeFrame]) -> [UUID: ImagePayload] {
        var payloads: [UUID: ImagePayload] = [:]
        func collect(_ node: Node) {
            for block in node.blocks {
                if case .image(let img) = block.kind, frames[node.id] != nil {
                    payloads[block.id] = ImagePayload(pixelSize: img.pixelSize, data: img.data)
                }
            }
            node.children.forEach(collect)
        }
        collect(root)
        return payloads
    }
}
```

- [ ] **Step 2: 跑既有测试确认基线绿**

Run: `xcodebuild test ... -only-testing:LinvaAppTests/RadialLayoutTests -only-testing:LinvaAppTests/ImageLayoutTests`
Expected: PASS（重构前基线）。

- [ ] **Step 3: RadialLayout 改用共享辅助**

`LinvaApp/LinvaApp/Layout/RadialLayout.swift` 精确替换（保持 `layout`/`edge`/`placeBranch`/`makeBranchToggles`/`appendToggles` 逻辑不变）：
- 删除本地 `subtreeHeight` 函数体，根调用 `subtreeHeight(document.root, isRoot: true)` 改为 `LayoutSupport.subtreeHeight(document.root, isRoot: true, measure: measure)`。
- `placeBranch` 内 `countDescendants(node)` → `LayoutSupport.countDescendants(node)`；`Self.centeredBlocks(from: metadata)` → `LayoutSupport.centeredBlocks(from: metadata)`。
- 根 frame 构造内 `countDescendants(document.root)` → `LayoutSupport.countDescendants(document.root)`；`Self.centeredBlocks(from: rootMetadata)` → `LayoutSupport.centeredBlocks(from: rootMetadata)`。
- 删除本地 `collectPayloads` 闭包，改为在根 frame 后 `let payloads = LayoutSupport.collectImagePayloads(root: document.root, frames: frames)`；删除两处 `collectPayloads(document.root)` 调用（早退分支与末尾），早退分支的 `imagePayloads: payloads` 直接引用该 `payloads`。
- `appendToggles` 内 `makeToggle(...)`（2 处）→ `LayoutSupport.makeToggle(...)`。
- 删除文件末尾私有 `makeToggle`、`countDescendants`、`centeredBlocks`、`BranchMetadata`。
- 文件尾部保留 `extension RadialLayout: LayoutEngine {}`。

- [ ] **Step 4: 跑测试确认行为不变**

Run: `-only-testing:LinvaAppTests/RadialLayoutTests -only-testing:LinvaAppTests/ImageLayoutTests`
Expected: PASS（与基线一致）。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Layout/LayoutSupport.swift LinvaApp/LinvaApp/Layout/RadialLayout.swift
git commit -m "refactor: 提取 LayoutSupport 共享辅助，RadialLayout 改用（行为不变）"
```

---

## Task 3: LogicLayout 总分树引擎

**Files:**
- Create: `LinvaApp/LinvaApp/Layout/LogicLayout.swift`
- Test: `LinvaAppTests/LogicLayoutTests.swift`

**Interfaces:**
- Consumes: `LayoutSupport`（Task 2）、`LayoutConstants`、`NodeFrame`/`EdgeGeometry`/`BranchToggle`/`LayoutSnapshot`、`TextMeasure`。
- Produces: `enum LogicLayout: LayoutEngine`（`static layout(document:measure:) -> LayoutSnapshot`），`LogicLayout.layout` 被 Task 4/9 调用。

- [ ] **Step 1: 写失败测试 LogicLayoutTests.swift**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import LinvaApp

@Suite("LogicLayout 总分树")
struct LogicLayoutTests {
    @Test func rootAtFarLeft_childrenToTheRight() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let a = Node(text: "章一")
        let b = Node(text: "章二")
        doc.root.children = [a, b]

        let snap = LogicLayout.layout(document: doc, measure: TextMeasure())
        let root = try #require(snap.frames[doc.root.id])
        let af = try #require(snap.frames[a.id])
        let bf = try #require(snap.frames[b.id])

        #expect(root.isRoot)
        #expect(root.side == nil)
        #expect(af.side == .right)
        #expect(af.center.x > root.rect.maxX)
        #expect(bf.center.x > root.rect.maxX)
        #expect(root.rect.minX == LayoutConstants.rootPadX)
    }

    @Test func siblings_stackVerticallyWithGap() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let a = Node(text: "A")
        let b = Node(text: "B")
        doc.root.children = [a, b]

        let snap = LogicLayout.layout(document: doc, measure: TextMeasure())
        let af = try #require(snap.frames[a.id])
        let bf = try #require(snap.frames[b.id])
        #expect(bf.rect.minY - af.rect.maxY == LayoutConstants.vGap)
    }

    @Test func lShapedOrthogonalEdge() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let a = Node(text: "章")
        doc.root.children = [a]

        let snap = LogicLayout.layout(document: doc, measure: TextMeasure())
        let root = try #require(snap.frames[doc.root.id])
        let af = try #require(snap.frames[a.id])
        let edge = try #require(snap.edges.first)

        #expect(edge.fromId == doc.root.id)
        #expect(edge.toId == a.id)
        #expect(edge.side == .right)
        #expect(edge.points.count == 4)
        #expect(edge.points[0] == CGPoint(x: root.rect.maxX, y: root.center.y))
        #expect(edge.points[3] == CGPoint(x: af.rect.minX, y: af.center.y))
        #expect(edge.points[1].x == edge.points[3].x)
        #expect(edge.points[2].x == edge.points[3].x)
    }

    @Test func descendants_moveFurtherRight() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let grand = Node(text: "节")
        let chapter = Node(text: "章", children: [grand])
        doc.root.children = [chapter]

        let snap = LogicLayout.layout(document: doc, measure: TextMeasure())
        let cf = try #require(snap.frames[chapter.id])
        let gf = try #require(snap.frames[grand.id])
        #expect(gf.center.x > cf.rect.maxX)
    }

    @Test func collapsedBranch_hidesDescendants_toggleOnRight() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let grand = Node(text: "孙")
        let child = Node(text: "子", collapsed: true, children: [grand])
        doc.root.children = [child]

        let snap = LogicLayout.layout(document: doc, measure: TextMeasure())
        #expect(snap.frames[grand.id] == nil)
        let cf = try #require(snap.frames[child.id])
        #expect(cf.hiddenCount == 1)
        let toggle = try #require(snap.branchToggles.first { $0.nodeId == child.id })
        #expect(toggle.side == .right)
        #expect(toggle.collapsed == true)
        #expect(toggle.center.x > cf.rect.maxX)
    }

    @Test func rootCollapsed_degenerateSnapshot_singleRightToggle() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        doc.root.children = [Node(text: "章")]
        doc.root.collapsed = true

        let snap = LogicLayout.layout(document: doc, measure: TextMeasure())
        #expect(snap.frames.count == 1)
        #expect(snap.edges.isEmpty)
        let toggles = snap.branchToggles.filter { $0.nodeId == doc.root.id }
        #expect(toggles.count == 1)
        #expect(toggles[0].side == .right)
    }

    @Test func imageNode_collectsPayload() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        doc.root.children = [
            Node(text: "带图", image: Data([0x89, 0x50]), imagePixelSize: ImagePixelSize(width: 100, height: 50)),
        ]
        let snap = LogicLayout.layout(document: doc, measure: TextMeasure())
        let frame = try #require(snap.frames[doc.root.children[0].id])
        let imageBlock = try #require(frame.blocks.first { $0.text == nil })
        #expect(snap.imagePayloads[imageBlock.blockId] != nil)
    }

    @Test func longTextNodes_doNotOverlap() throws {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let long = Node(text: String(repeating: "很长的章节标题内容", count: 8))
        let short = Node(text: "短")
        doc.root.children = [long, short]

        let snap = LogicLayout.layout(document: doc, measure: TextMeasure())
        let lf = try #require(snap.frames[long.id])
        let sf = try #require(snap.frames[short.id])
        #expect(lf.size.width > sf.size.width)
        #expect(abs(lf.center.y - sf.center.y) >= lf.size.height)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test ... -only-testing:LinvaAppTests/LogicLayoutTests`
Expected: FAIL（编译失败：`LogicLayout` 未定义）。

- [ ] **Step 3: 实现 LogicLayout.swift**

```swift
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

        let rootMetadata = LayoutSupport.subtreeHeight(document.root, isRoot: true, measure: measure)
        let rootFrame = NodeFrame(
            id: document.root.id,
            text: document.root.text,
            center: CGPoint(x: LayoutConstants.rootPadX + rootMetadata.size.width / 2, y: 0),
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

        // 根折叠早退：此时仅根有 frame，只收集根的载荷（与 RadialLayout 一致）。
        let rootPayloads = LayoutSupport.collectImagePayloads(root: document.root, frames: frames)
        let toggles = makeBranchToggles(frames: frames, root: document.root)

        guard !document.root.collapsed else {
            return LayoutSnapshot(frames: frames, edges: edges, branchToggles: toggles, imagePayloads: rootPayloads)
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
        return LayoutSnapshot(frames: frames, edges: edges, branchToggles: toggles, imagePayloads: payloads)
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
            toggles.append(LayoutSupport.makeToggle(node: node, frame: frame, side: .right))
        }
        return toggles
    }
}

extension LogicLayout: LayoutEngine {}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `-only-testing:LinvaAppTests/LogicLayoutTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Layout/LogicLayout.swift LinvaAppTests/LogicLayoutTests.swift
git commit -m "feat: LogicLayout 总分树布局引擎（根左/层右/L 形边/右侧 toggle）"
```

---

## Task 4: LayoutPipeline 按 layout 分派

**Files:**
- Modify: `LinvaApp/LinvaApp/Session/LayoutPipeline.swift`
- Test: `LinvaAppTests/LayoutPipelineTests.swift`

**Interfaces:**
- Consumes: `LayoutKind`（Task 1）、`RadialLayout`/`LogicLayout`（Task 3）。
- Produces: `LayoutPipeline.relayout(document:)` 按 `document.layout` 分派；删 `layoutEngineType` 注入。

- [ ] **Step 1: 改写 LayoutPipelineTests.swift（删 FakeLayoutEngine，换分派用例）**

```swift
import Foundation
import Testing
@testable import LinvaApp

@Suite("LayoutPipeline")
struct LayoutPipelineTests {
    @Test func radialDocument_usesRadialLayout() {
        let pipeline = LayoutPipeline()
        let doc = MindMapDocument.blank()
        let snap = pipeline.relayout(document: doc)
        let expected = RadialLayout.layout(document: doc, measure: TextMeasure())
        #expect(snap == expected)
    }

    @Test func logicDocument_usesLogicLayout() {
        var doc = MindMapDocument.blank(rootText: "根")
        doc.layout = .logic
        let child = Node(text: "章", children: [Node(text: "节")])
        doc.root.children = [child]

        let pipeline = LayoutPipeline()
        let snap = pipeline.relayout(document: doc)
        let expected = LogicLayout.layout(document: doc, measure: TextMeasure())
        #expect(snap == expected)
        #expect(snap.frames[child.id]!.center.x > snap.frames[doc.root.id]!.rect.maxX)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test ... -only-testing:LinvaAppTests/LayoutPipelineTests`
Expected: FAIL（编译错误：`LayoutPipeline` 已无 `layoutEngineType` 注入、`FakeLayoutEngine` 引用删掉后剩余调用不匹配）。

- [ ] **Step 3: 实现 LayoutPipeline.swift**

```swift
import Foundation

/// 布局子域（SRP）：持量字器，按文档布局类型分派引擎，产出 LayoutSnapshot。
/// 换布局只改 `document.layout`，`relayout()` 单点自动生效。
final class LayoutPipeline {
    private let measure: TextMeasure

    init(measure: TextMeasure = TextMeasure()) {
        self.measure = measure
    }

    func relayout(document: MindMapDocument) -> LayoutSnapshot {
        switch document.layout {
        case .radial:
            return RadialLayout.layout(document: document, measure: measure)
        case .logic:
            return LogicLayout.layout(document: document, measure: measure)
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `-only-testing:LinvaAppTests/LayoutPipelineTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Session/LayoutPipeline.swift LinvaAppTests/LayoutPipelineTests.swift
git commit -m "feat: LayoutPipeline 按 document.layout 分派引擎（删引擎类型注入）"
```

---

## Task 5: setLayout 命令

**Files:**
- Modify: `LinvaApp/LinvaApp/Commands/MindMapCommand.swift`
- Modify: `LinvaApp/LinvaApp/Model/MindMapModel.swift`
- Modify: `LinvaApp/LinvaApp/Commands/CommandBus.swift`
- Test: `LinvaAppTests/CommandBusTests.swift`

**Interfaces:**
- Consumes: `LayoutKind`（Task 1）。
- Produces: `MindMapCommand.setLayout(kind: LayoutKind)`；`MindMapModel.setLayout(_:) -> LayoutKind?`（nil = no-op）。

- [ ] **Step 1: 写失败测试（CommandBusTests suite 末尾加）**

```swift
    @Test func setLayout_undoRedo_roundTrips() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        #expect(model.document.layout == .radial)

        bus.execute(.setLayout(kind: .logic))
        #expect(model.document.layout == .logic)

        bus.undo()
        #expect(model.document.layout == .radial)

        bus.redo()
        #expect(model.document.layout == .logic)
    }

    @Test func setLayout_sameKind_isNoOp() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        bus.execute(.setLayout(kind: .radial))
        #expect(!bus.canUndo)
        #expect(model.document.layout == .radial)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test ... -only-testing:LinvaAppTests/CommandBusTests`
Expected: FAIL（编译失败：`.setLayout` case 不存在）。

- [ ] **Step 3: 实现**

`MindMapCommand.swift` 末尾（`setFill` 后）加：

```swift
    case setLayout(kind: LayoutKind)
```

`MindMapModel.swift`（`setFill` 方法后）加：

```swift
    /// 设置文档布局（文档属性，与选中无关）；返回旧值供 Undo；无变化返回 nil（no-op 不入栈）。
    @discardableResult
    func setLayout(_ kind: LayoutKind) -> LayoutKind? {
        guard document.layout != kind else { return nil }
        let old = document.layout
        document.layout = kind
        return old
    }
```

`CommandBus.swift` `applyForward` 的 `.setFill` 分支后加：

```swift
        case let .setLayout(kind):
            guard let old = model.setLayout(kind) else { return nil }
            return Entry(
                undo: { _ = self.model.setLayout(old) },
                redo: { _ = self.model.setLayout(kind) }
            )
```

- [ ] **Step 4: 跑测试确认通过**

Run: `-only-testing:LinvaAppTests/CommandBusTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Commands/MindMapCommand.swift LinvaApp/LinvaApp/Model/MindMapModel.swift LinvaApp/LinvaApp/Commands/CommandBus.swift LinvaAppTests/CommandBusTests.swift
git commit -m "feat: setLayout 命令入栈（no-op 不入栈，undo/redo 往返）"
```

---

## Task 6: DocumentSession（layout / setLayout / canSetSide / 自动 fit） + Canvas fitVersion

**Files:**
- Modify: `LinvaApp/LinvaApp/Session/DocumentSession.swift`
- Modify: `LinvaApp/LinvaApp/Render/CanvasMetalView.swift`
- Test: `LinvaAppTests/DocumentSessionTests.swift`

**Interfaces:**
- Consumes: `setLayout` 命令（Task 5）、`LayoutPipeline` 分派（Task 4）、`LayoutKind`。
- Produces: `DocumentSession.layout: LayoutKind`（计算属性）、`DocumentSession.setLayout(_:)`、`DocumentSession.fitVersion: Int`、`DocumentSession.canSetSide`（logic 下 false）、`CanvasMTKView.appliedFitVersion`。

- [ ] **Step 1: 写失败测试（DocumentSessionTests suite 加）**

```swift
    @Test func setLayout_switchesSnapshot_andGatesCanSetSide() {
        let session = DocumentSession()
        let root = session.model.document.root.id
        let child = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        session.selectOnly(child)
        #expect(session.canSetSide)

        session.setLayout(.logic)
        #expect(session.layout == .logic)
        #expect(session.model.document.layout == .logic)
        let rootFrame = session.snapshot.frames[root]!
        let childFrame = session.snapshot.frames[child]!
        #expect(childFrame.center.x > rootFrame.rect.maxX)
        #expect(!session.canSetSide)
        #expect(session.fitVersion == 1)

        session.commandBus.undo()
        #expect(session.layout == .radial)
        #expect(session.canSetSide)
        #expect(session.fitVersion == 2)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test ... -only-testing:LinvaAppTests/DocumentSessionTests`
Expected: FAIL（`session.layout`/`setLayout`/`fitVersion` 未定义；且 `canSetSide` 在 logic 下仍 true）。

- [ ] **Step 3: 实现**

`DocumentSession.swift`：
① 属性区加：

```swift
    /// 布局变化触发画布重新 fit 的信号（D1：切换/撤销均经 markDirtyAndRelayout 统一 bump）。
    @Published private(set) var fitVersion = 0
    private var appliedLayoutForFit: LayoutKind?
```

② `init` 末尾 `relayout()` 之后加：`appliedLayoutForFit = model.document.layout`。

③ `markDirtyAndRelayout()` 改为：

```swift
    func markDirtyAndRelayout() {
        isDirty = persistence.noteChange(current: model.document)
        relayout()
        // D1：布局变化（工具栏切换或 ⌘Z/⌘⇧Z 往返）统一触发再适配。
        if model.document.layout != appliedLayoutForFit {
            appliedLayoutForFit = model.document.layout
            fitVersion += 1
        }
    }
```

④ `canSetSide` 改为：

```swift
    /// 逻辑图无左右语义：⌘←/⌘→ 与侧向拖放置灰（FR-L4）；切回辐射恢复。
    var canSetSide: Bool {
        model.document.layout != .logic
            && model.selectedIds.contains { model.parentId(of: $0) == model.document.root.id }
    }
```

⑤ 在 `setFill(_:)` 前加：

```swift
    /// 当前布局（文档属性，随 .linva 持久化）。改走 setLayout 命令入栈。
    var layout: LayoutKind { model.document.layout }

    func setLayout(_ kind: LayoutKind) {
        commitEditingIfNeeded()
        commandBus.execute(.setLayout(kind: kind))
    }
```

⑥ `resetSessionState` 末尾 `relayout()` 之后加：`appliedLayoutForFit = model.document.layout`（新文档相机已重置，无需 bump）。

`CanvasMetalView.swift`：
① `CanvasMTKView` 属性区加：`var appliedFitVersion = 0`。
② `updateNSView` 中 `refreshCursorForTool()` 后加：

```swift
        if session.fitVersion != view.appliedFitVersion {
            view.appliedFitVersion = session.fitVersion
            view.markNeedsFitContent()
        }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `-only-testing:LinvaAppTests/DocumentSessionTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Session/DocumentSession.swift LinvaApp/LinvaApp/Render/CanvasMetalView.swift LinvaAppTests/DocumentSessionTests.swift
git commit -m "feat: DocumentSession 暴露 layout/setLayout；布局变化自动 fit；logic 下 canSetSide 置灰"
```

---

## Task 7: DropIntent 逻辑图下侧向意图禁用

**Files:**
- Modify: `LinvaApp/LinvaApp/Session/DropIntent.swift`
- Test: `LinvaAppTests/DropIntentTests.swift`

**Interfaces:**
- Consumes: `LayoutKind`、`LogicLayout`（Task 3，测试用）、`resolveDropIntent`/`resolveEmptySideIntent`。
- Produces: 逻辑图下根侧带→child、空白过中线→nil。

- [ ] **Step 1: 写失败测试（DropIntentTests suite 加）**

```swift
    @Test func logicLayout_rootSideZones_degradeToChild() throws {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        model.document.layout = .logic
        _ = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let b = model.insertChild(parentId: root, text: "B", side: .left, at: nil)
        let snapshot = LogicLayout.layout(document: model.document, measure: TextMeasure())
        let rootFrame = try #require(snapshot.frames[root])

        let leftPoint = CGPoint(x: rootFrame.rect.minX + rootFrame.rect.width * 0.1, y: rootFrame.rect.midY)
        #expect(resolveDropIntent(screenPoint: leftPoint, movingIds: Set([b]), snapshot: snapshot, camera: camera, model: model) == .child(targetId: root))
    }

    @Test func logicLayout_emptySide_intentSuppressed() throws {
        let model = MindMapModel.makeNew()
        let root = model.document.root.id
        model.document.layout = .logic
        _ = model.insertChild(parentId: root, text: "A", side: .right, at: nil)
        let snapshot = LogicLayout.layout(document: model.document, measure: TextMeasure())
        let moving = [model.document.root.children[0].id]
        let point = CGPoint(x: -200, y: -200)
        #expect(resolveDropIntent(screenPoint: point, movingIds: Set(moving), snapshot: snapshot, camera: camera, model: model) == nil)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test ... -only-testing:LinvaAppTests/DropIntentTests`
Expected: FAIL（`.logic` 文档下仍产出 `.sideLeft`/`.sideRight`）。

- [ ] **Step 3: 实现**

`DropIntent.swift` `resolveDropIntent` 的根命中分支改为：

```swift
    if target.isRoot {
        // 逻辑图无左右侧语义：侧带降级为成子（FR-L4）。
        if model.document.layout == .logic {
            return model.isValidDropTarget(target.id, movingIds: movingIds)
                ? .child(targetId: target.id)
                : nil
        }
        let u = (world.x - target.rect.minX) / max(target.rect.width, 1)
        if u < 1.0 / 3.0 { return .sideLeft(targetId: target.id, viaEmpty: false) }
        if u > 2.0 / 3.0 { return .sideRight(targetId: target.id, viaEmpty: false) }
        return model.isValidDropTarget(target.id, movingIds: movingIds)
            ? .child(targetId: target.id)
            : nil
    }
```

`resolveEmptySideIntent` 开头加：

```swift
    // 逻辑图无左右侧语义：空白改侧意图整体禁用（FR-L4）。
    guard model.document.layout != .logic else { return nil }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `-only-testing:LinvaAppTests/DropIntentTests`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Session/DropIntent.swift LinvaAppTests/DropIntentTests.swift
git commit -m "feat: 逻辑图下侧向拖放意图禁用（根侧带降级成子，空白改侧置 nil）"
```

---

## Task 8: 工具栏布局菜单 + ⌥L 切换

**Files:**
- Modify: `LinvaApp/LinvaApp/App/MainToolbar.swift`
- Modify: `LinvaApp/LinvaApp/ContentView.swift`
- Modify: `LinvaApp/LinvaApp/LinvaAppApp.swift`
- Test: 无单测（SwiftUI 壳层），手动冒烟（Task 10）。

**Interfaces:**
- Consumes: `DocumentSession.layout`/`setLayout`（Task 6）。
- Produces: 工具栏 `Picker(.menu)`（辐射/逻辑图）、菜单栏 ⌥L 循环切换。

- [ ] **Step 1: 实现 MainToolbar**

`MainToolbar` 属性区（`let setFill` 后）加：

```swift
    let layout: LayoutKind
    let setLayout: (LayoutKind) -> Void
```

automatic 组 `FillSwatchesView(...)` 之后、`}` 前加：

```swift
            Divider()
            Picker("布局", selection: Binding(
                get: { layout },
                set: { setLayout($0) }
            )) {
                Text("辐射").tag(LayoutKind.radial)
                Text("逻辑图").tag(LayoutKind.logic)
            }
            .pickerStyle(.menu)
            .help("布局（⌥L 切换）")
```

- [ ] **Step 2: 实现 ContentView 接线**

`ContentView` 的 `.toolbar { MainToolbar(...) }` 调用，在 `setFill: { fill in session.setFill(fill) },` 后加：

```swift
                    layout: session.layout,
                    setLayout: { session.setLayout($0) },
```

- [ ] **Step 3: 实现 DocumentCommands ⌥L**

`LinvaAppApp.swift` `DocumentCommands` 的 `after: .undoRedo` 组末尾（`移到右侧` Button 后）加：

```swift
            Divider()

            Button(session.layout == .radial ? "切换到逻辑图布局" : "切换到辐射布局") {
                session.setLayout(session.layout == .radial ? .logic : .radial)
            }
            .keyboardShortcut("l", modifiers: .option)
            .help("切换布局（⌥L）")
```

- [ ] **Step 4: 构建验证（编译 + 手动冒烟见 Task 10）**

Run: `xcodebuild build -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/App/MainToolbar.swift LinvaApp/LinvaApp/ContentView.swift LinvaApp/LinvaApp/LinvaAppApp.swift
git commit -m "feat: 工具栏布局菜单（Picker）+ 菜单栏 ⌥L 循环切换"
```

---

## Task 9: PNG 导出按当前布局

**Files:**
- Modify: `LinvaApp/LinvaApp/Render/PNGExporter.swift`
- Test: `LinvaAppTests/PNGExporterTests.swift`

**Interfaces:**
- Consumes: `RadialLayout`/`LogicLayout`（Task 3）。
- Produces: `PNGExporter.data` 按 `expanded.layout` 分派产快照。

- [ ] **Step 1: 写失败测试（PNGExporterTests suite 加）**

```swift
    @Test func data_rendersLogicLayout_whenMetalAvailable() throws {
        try #require(MTLCreateSystemDefaultDevice() != nil)
        var d = MindMapDocument.blank(rootText: "根")
        d.layout = .logic
        d.root.children = [Node(text: "章", children: [Node(text: "节")])]
        let data = PNGExporter.data(document: d)
        #expect(data != nil)
        let sig = data?.prefix(8)
        #expect(sig == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test ... -only-testing:LinvaAppTests/PNGExporterTests`
Expected: 当前实现硬编码 `RadialLayout`，logic 文档仍按辐射导出——测试期望非空 PNG，现有实现其实也非空（只是布局错），此测试作为「logic 下可导出」守卫；断言 PNG 魔数即可。若在无 Metal 宿主则 `#require` 跳过。

- [ ] **Step 3: 实现**

`PNGExporter.data` 中 `let expanded = fullyExpanded(document)` 后、`let bounds = ...` 前，把 `let snapshot = RadialLayout.layout(document: expanded, measure: TextMeasure())` 替换为：

```swift
        // FR-L5：按当前布局离屏渲染（relayout 产出哪张快照就渲染哪张）。
        let snapshot: LayoutSnapshot
        switch expanded.layout {
        case .radial:
            snapshot = RadialLayout.layout(document: expanded, measure: TextMeasure())
        case .logic:
            snapshot = LogicLayout.layout(document: expanded, measure: TextMeasure())
        }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `-only-testing:LinvaAppTests/PNGExporterTests`
Expected: PASS（含既有 radial 用例与新增 logic 用例）。

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Render/PNGExporter.swift LinvaAppTests/PNGExporterTests.swift
git commit -m "feat: PNG 导出按当前布局分派渲染"
```

---

## Task 10: 文档、技能、全量验证

**Files:**
- Modify: `docs/架构现状.md`
- Modify: `.agents/skills/linva-codec-version/SKILL.md`、`.agents/skills/linva-layout-snapshot/SKILL.md`、`.agents/skills/linva-command/SKILL.md`

- [ ] **Step 1: 更新文档与技能**

`docs/架构现状.md`：新增一节「布局类型：辐射 / 逻辑图」（新引擎 `LogicLayout`、共享 `LayoutSupport`、`LayoutPipeline` 分派、`document.layout` v5 持久化、setLayout 命令、side 降级、PNG 分派），并在「修订记录」加一行（日期、说明「新增布局类型」）。

`.agents/skills/linva-codec-version/SKILL.md`：把「现状 `currentVersion == 3`（v2 fill；v3 image）」更新为「现状 `currentVersion == 5`（v4 blocks 图文流；v5 layout 布局字段，v4→v5 迁移：`layout` 缺省 `.radial`）」；补充 checklist 提示 `sanitize` 重建文档须保留 `layout`。

`.agents/skills/linva-layout-snapshot/SKILL.md`：注明已存在 `LayoutEngine` 协议 + `LayoutPipeline` 按 `document.layout` 分派（`RadialLayout`/`LogicLayout`）；共享辅助在 `LayoutSupport`；逻辑图 L 形边、统一 `.right` side、右侧 toggle。

`.agents/skills/linva-command/SKILL.md`：命令清单末尾补 `setLayout(kind: LayoutKind)`（文档属性命令，no-op 不入栈，仿 `setFill`）。

- [ ] **Step 2: 边界校验**

Run: `scripts/check-boundaries.sh`
Expected: 输出「依赖边界检查通过」退出 0（新文件仅 `import Foundation/CoreGraphics`）。

- [ ] **Step 3: 全量单测**

Run: `xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS'`
Expected: 全绿。

- [ ] **Step 4: 手动冒烟（PRD §6 验收表 1–9）**

跑 App（`open` 或 Xcode 运行），逐一验证：工具栏「布局」菜单切换辐射↔逻辑图全图重排且当前高亮；⌘Z/⌘⇧Z 往返且选中/折叠保持、视野自动适配；逻辑图根在最左、层级向右、L 形边、无重叠；折叠分支 toggle 在右侧、后代不占空间；逻辑图下 ⌘←/⌘→ 置灰、切回辐射左右分组完整；保存重开布局保持（v4 老文件缺省辐射零拒绝）；逻辑图下拖拽搬移/插入线/命中选中正常；导出 PNG 按当前布局；图片节点图文同框、长文本自适应不重叠。

- [ ] **Step 5: Commit**

```bash
git add docs/架构现状.md .agents/skills/linva-codec-version/SKILL.md .agents/skills/linva-layout-snapshot/SKILL.md .agents/skills/linva-command/SKILL.md
git commit -m "docs: 布局类型文档与技能更新；边界/单测/冒烟验证通过"
```

---

## Self-Review

**Spec 覆盖**：D1 自动 fit（Task 6 ✓）；D2 工具栏 Picker（Task 8 ✓）；D3 引擎分派删注入（Task 4 ✓）；D4 LayoutSupport 提取（Task 2 ✓）；D5 根左缘（Task 3 ✓）。FR-L1 Codec v5（Task 1 ✓）；FR-L2 LogicLayout（Task 3 ✓）；FR-L3 命令/会话/UI（Task 5/6/8 ✓）；FR-L4 side 降级 + DropIntent（Task 6/7 ✓）；FR-L5 导出（Task 9 ✓）；测试（各 Task ✓）；文档/技能/验证（Task 10 ✓）。

**类型一致性**：`LayoutKind`（Task 1）被 Task 4/5/6/7/8/9 引用，签名一致；`LayoutSupport.subtreeHeight(_:isRoot:measure:)`（Task 2）被 Task 3 按同名调用；`DocumentSession.setLayout(_:)`/`fitVersion`/`canSetSide`（Task 6）被 Task 8/测试引用；`LogicLayout.layout(document:measure:)`（Task 3）被 Task 4/9 调用，均与 spec 一致。
