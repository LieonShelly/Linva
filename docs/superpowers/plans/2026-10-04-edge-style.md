# YMind 连线样式实现计划（正交折线 / 曲线 / 大括号 + 可扩展抽象）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 父-子连线支持三种样式（正交折线/曲线/大括号），全局一键切换、持久化、⌘Z 可撤销；样式通过统一 `ConnectorGeometry` + `EdgeStyleProvider` 抽象可扩展。

**Architecture:** `EdgeStyle`（String enum，持久化 token）→ `EdgeStyleRegistry.provider(for:)` 取 `EdgeStyleProvider`；引擎拆为 `placeFrames`（排布，产 NodeFrame）+ Provider `connectors(...)`（产统一 `ConnectorGeometry` 列表）；`LayoutSnapshot` 用 `connectors`；Renderer 只描边 Connector + 画 marker。brace 的 Provider `requiresLogicArrangement = true`，强制逻辑树排布。

**Tech Stack:** Swift, SwiftUI 壳, Metal 渲染, CoreGraphics/Foundation 几何, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-04-ymind-edge-style-design.md`（D1–D8，本文从之）
**实现细则:** `docs/prds/prd-ymind-edge-style-2026-10-04/addendum.md`
**PRD:** `docs/prds/prd-ymind-edge-style-2026-10-04/prd.md`（FR-E1…E5）
**体验真源:** `prototype/edge-style.html`（三样式 + 组括号几何，已验证）

## Global Constraints

- `MindMapDocument.currentVersion` 由 6 升 **7**（唯一版本号变更；不与其他 PRD 撞）。
- `EdgeStyle` 缺省 `.elbow`，decode 缺省容错，零拒绝打开老文件。
- **扩展性铁律**：加新样式只许动 `EdgeStyle` 枚举 + 新建 Provider 文件 + registry 注册；**不得改引擎/Render/Codec**。
- Render 只消费 `LayoutSnapshot`，不读 Model 树。
- 不新增第三方依赖；几何用 CoreGraphics/Foundation；`check-boundaries.sh` 保持绿。
- 中文代码注释；文档语言中文优先。

---

### Task 1: EdgeStyle 枚举 + MindMapDocument.edgeStyle + Codec v7

**Files:**
- Modify: `YMindApp/YMindApp/Model/MindMapDocument.swift`
- Modify: `YMindApp/YMindApp/Model/YMindCodec.swift`
- Test: `YMindApp/YMindAppTests/CodecTests.swift`

**Interfaces:**
- Produces: `enum EdgeStyle: String, Codable, CaseIterable, Sendable, Hashable { case elbow, curve, brace }`；`MindMapDocument.edgeStyle: EdgeStyle`；`currentVersion == 7`。

- [ ] **Step 1: 写失败测试**（CodecTests 增）

```swift
func testEdgeStyleRoundTrip() throws {
    let doc = MindMapDocument.blank(rootText: "根")
    for style in EdgeStyle.allCases {
        var d = doc
        d.edgeStyle = style
        let data = try YMindCodec.encode(d)
        let back = try YMindCodec.decode(data)
        XCTAssertEqual(back.edgeStyle, style)
        XCTAssertEqual(back.version, MindMapDocument.currentVersion)
    }
}

func testEdgeStyleDefaultsToElbow() throws {
    // 构造 v6 文档 JSON（无 edgeStyle 字段），decode 应缺省 .elbow
    let v6JSON = """
    {"version":6,"root":{"text":"根","children":[]}}
    """
    let doc = try YMindCodec.decode(Data(v6JSON.utf8))
    XCTAssertEqual(doc.edgeStyle, .elbow)
    XCTAssertEqual(doc.version, 7)
}
```

- [ ] **Step 2: 跑测试确认失败**
Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -only-testing:YMindAppTests/CodecTests`
Expected: FAIL（`edgeStyle` 不存在）。

- [ ] **Step 3: 实现**（MindMapDocument.swift，`LayoutKind` 后加 `EdgeStyle`；struct 加字段）

```swift
enum EdgeStyle: String, Codable, CaseIterable, Sendable, Hashable {
    case elbow, curve, brace
}

struct MindMapDocument: Equatable, Codable, Sendable {
    static let currentVersion = 7
    var version: Int
    var root: Node
    var layout: LayoutKind = .radial
    /// 连线样式（文档属性，v7 起持久化；v6 及以下缺省 .elbow，零拒绝迁移）。
    var edgeStyle: EdgeStyle = .elbow

    init(version: Int, root: Node, layout: LayoutKind = .radial, edgeStyle: EdgeStyle = .elbow) {
        self.version = version
        self.root = root
        self.layout = layout
        self.edgeStyle = edgeStyle
    }

    private enum CodingKeys: String, CodingKey {
        case version, root, layout, edgeStyle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        root = try c.decode(Node.self, forKey: .root)
        layout = try c.decodeIfPresent(LayoutKind.self, forKey: .layout) ?? .radial
        edgeStyle = try c.decodeIfPresent(EdgeStyle.self, forKey: .edgeStyle) ?? .elbow
    }
}
```

- [ ] **Step 4: Codec 迁移**（YMindCodec.decode，迁移链末尾，`v5→v6` 块后加）

```swift
// 迁移：v6 → v7（edgeStyle 缺省 .elbow；MindMapDocument 解码器对缺失字段天然容错）。
if doc.version == 6 {
    doc.version = 7
}
```

- [ ] **Step 5: 跑测试确认通过**
Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -only-testing:YMindAppTests/CodecTests`
Expected: PASS。

- [ ] **Step 6: Commit**
```bash
git add YMindApp/YMindApp/Model/MindMapDocument.swift YMindApp/YMindApp/Model/YMindCodec.swift YMindApp/YMindAppTests/CodecTests.swift
git commit -m "feat(edge-style): add EdgeStyle enum + edgeStyle field + Codec v7"
```

---

### Task 2: setEdgeStyle 命令 + 会话 + 有效排布 fit

**Files:**
- Modify: `YMindApp/YMindApp/Commands/MindMapCommand.swift`
- Modify: `YMindApp/YMindApp/Model/MindMapModel.swift`
- Modify: `YMindApp/YMindApp/Commands/CommandBus.swift`
- Modify: `YMindApp/YMindApp/Session/DocumentSession.swift`
- Test: `YMindApp/YMindAppTests/CommandBusTests.swift`, `YMindApp/YMindAppTests/DocumentSessionTests.swift`

**Interfaces:**
- Produces: `MindMapCommand.setEdgeStyle(kind: EdgeStyle)`；`MindMapModel.setEdgeStyle(_:) -> EdgeStyle?`；`DocumentSession.edgeStyle` / `setEdgeStyle(_:)`；`markDirtyAndRelayout()` 有效排布变化时 `fitVersion += 1`。
- Consumes: `EdgeStyle`（Task 1）。

- [ ] **Step 1: 写失败测试**（CommandBusTests 增）

```swift
func testSetEdgeStyleCommandUndoRedo() {
    let bus = CommandBus(model: MindMapModel(document: .blank(rootText: "根")))
    XCTAssertEqual(bus.model.document.edgeStyle, .elbow)
    bus.execute(.setEdgeStyle(kind: .curve))
    XCTAssertEqual(bus.model.document.edgeStyle, .curve)
    bus.undo()
    XCTAssertEqual(bus.model.document.edgeStyle, .elbow)
    bus.redo()
    XCTAssertEqual(bus.model.document.edgeStyle, .curve)
}
```

- [ ] **Step 2: 跑测试确认失败**
Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -only-testing:YMindAppTests/CommandBusTests`
Expected: FAIL。

- [ ] **Step 3: 实现**（MindMapCommand 加 case；MindMapModel 加方法，仿 setLayout）

```swift
// MindMapCommand.swift 枚举内加：
case setEdgeStyle(kind: EdgeStyle)
```

```swift
// MindMapModel.swift（仿 setLayout）：
/// 设置文档连线样式（文档属性，与选中无关）；返回旧值供 Undo；无变化返回 nil。
@discardableResult
func setEdgeStyle(_ kind: EdgeStyle) -> EdgeStyle? {
    guard document.edgeStyle != kind else { return nil }
    let old = document.edgeStyle
    document.edgeStyle = kind
    return old
}
```

```swift
// CommandBus.swift applyForward（仿 setLayout case）：
case let .setEdgeStyle(kind):
    guard let old = model.setEdgeStyle(kind) else { return nil }
    return Entry(
        undo: { _ = self.model.setEdgeStyle(old) },
        redo: { _ = self.model.setEdgeStyle(kind) }
    )
```

- [ ] **Step 4: 会话层**（DocumentSession，仿 setLayout；有效排布 fit 用临时占位——Task 4 才引入 Provider，此处 fit 条件先按 `kind == .brace`）

```swift
/// 当前连线样式（文档属性，随 .ymind 持久化）。改走 setEdgeStyle 命令入栈。
var edgeStyle: EdgeStyle { model.document.edgeStyle }

func setEdgeStyle(_ kind: EdgeStyle) {
    commitEditingIfNeeded()
    commandBus.execute(.setEdgeStyle(kind: kind))
}
```

- [ ] **Step 5: 有效排布 fit**（`markDirtyAndRelayout()`，Task 4 会替换为 Provider 判定；先按样式族）

```swift
// D8：有效排布变化（brace 强制逻辑树）触发再适配。Task 4 换 provider.requiresLogicArrangement。
private func effectiveArrangement(_ doc: MindMapDocument) -> LayoutKind {
    doc.edgeStyle == .brace ? .logic : doc.layout
}
// markDirtyAndRelayout() 内，在现有 layout 适配块后：
let eff = effectiveArrangement(model.document)
if eff != appliedArrangementForFit {
    appliedArrangementForFit = eff
    fitVersion += 1
}
```
（新增 `private var appliedArrangementForFit: LayoutKind?`，与现有 `appliedLayoutForFit` 并存或替换——替换为按有效排布。）

- [ ] **Step 6: 跑测试确认通过**（CommandBusTests + DocumentSessionTests 全绿）
Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -only-testing:YMindAppTests/CommandBusTests -only-testing:YMindAppTests/DocumentSessionTests`
Expected: PASS。

- [ ] **Step 7: Commit**
```bash
git add YMindApp/YMindApp/Commands/MindMapCommand.swift YMindApp/YMindApp/Model/MindMapModel.swift YMindApp/YMindApp/Commands/CommandBus.swift YMindApp/YMindApp/Session/DocumentSession.swift YMindApp/YMindAppTests/CommandBusTests.swift YMindApp/YMindAppTests/DocumentSessionTests.swift
git commit -m "feat(edge-style): setEdgeStyle command + session + effective-arrangement fit"
```

---

### Task 3: 统一 ConnectorGeometry — LayoutSnapshot 用 connectors（机械重构）

**Files:**
- Modify: `YMindApp/YMindApp/Layout/LayoutSnapshot.swift`
- Modify: `YMindApp/YMindApp/Layout/RadialLayout.swift`
- Modify: `YMindApp/YMindApp/Layout/LogicLayout.swift`
- Modify: `YMindApp/YMindApp/Render/MetalRenderer.swift`
- Test: `YMindApp/YMindAppTests/RadialLayoutTests.swift`, `YMindApp/YMindAppTests/LogicLayoutTests.swift`, `YMindApp/YMindAppTests/LayoutPipelineTests.swift`

**Interfaces:**
- Produces: `ConnectorMarker`、`ConnectorGeometry`；`LayoutSnapshot.connectors: [ConnectorGeometry]`（删 `edges`）。引擎暂时仍按「elbow 正交折线」产 Connector（style 尚未进几何，Task 4 接入 Provider）。
- Consumes: 现有引擎排布逻辑（`placeBranch` / `subtreeHeight`）。

> 说明：本任务只做**统一契约的机械重构**——把 `EdgeGeometry`（fromId/toId/side/points）换成 `ConnectorGeometry`（id/path/marker），引擎当前仍产折线 Connector，保证编译通过、行为不变。曲线/大括号几何在 Task 4 由 Provider 接入。

- [ ] **Step 1: 写失败测试**（RadialLayoutTests 改为断言 connectors）

```swift
func testRadialProducesConnectors() {
    let doc = MindMapDocument.blank(rootText: "根")
    let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
    XCTAssertFalse(snap.connectors.isEmpty)
    // 每条 connector 有非空 path
    for c in snap.connectors {
        XCTAssertGreaterThanOrEqual(c.path.count, 2)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**
Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -only-testing:YMindAppTests/RadialLayoutTests`
Expected: FAIL（`snap.connectors` 不存在）。

- [ ] **Step 3: 实现 ConnectorGeometry**（LayoutSnapshot.swift，替换 EdgeGeometry）

```swift
struct ConnectorMarker: Equatable {
    enum Kind: Equatable { case circle }
    let kind: Kind
    let center: CGPoint
    let radius: CGFloat
}

/// 统一连线契约：任何样式产一个可描边的连接器（path 折线 + 可选 marker）。
struct ConnectorGeometry: Equatable {
    let id: UUID
    let path: [CGPoint]
    let marker: ConnectorMarker?
}

struct LayoutSnapshot: Equatable {
    let frames: [UUID: NodeFrame]
    let connectors: [ConnectorGeometry]
    let branchToggles: [BranchToggle]
    let imagePayloads: [UUID: ImagePayload]

    init(frames: [UUID: NodeFrame], connectors: [ConnectorGeometry],
         branchToggles: [BranchToggle] = [], imagePayloads: [UUID: ImagePayload] = [:]) {
        self.frames = frames
        self.connectors = connectors
        self.branchToggles = branchToggles
        self.imagePayloads = imagePayloads
    }
}
```
删除 `EdgeGeometry`（连同 fromId/toId/side/points）。

- [ ] **Step 4: 引擎改产 connectors**（RadialLayout / LogicLayout 的 `edge(...)` 改为 `connector(...)`）

```swift
// RadialLayout.swift edge() 改：
func connector(from parent: NodeFrame, to child: NodeFrame, side: Side) -> ConnectorGeometry {
    let direction: CGFloat = side == .left ? -1 : 1
    let start = CGPoint(x: parent.center.x + direction * parent.size.width / 2, y: parent.center.y)
    let end = CGPoint(x: child.center.x - direction * child.size.width / 2, y: child.center.y)
    let controlX = (start.x + end.x) / 2
    return ConnectorGeometry(
        id: child.id,
        path: [start,
               CGPoint(x: controlX, y: start.y),
               CGPoint(x: controlX, y: end.y),
               end],
        marker: nil
    )
}
// 调用处 edges.append(...) → connectors.append(connector(from:to:side:))
// 返回 LayoutSnapshot(frames: frames, connectors: connectors, ...)（LogicLayout 同理，id 用子节点 id）
```

- [ ] **Step 5: Render 改遍历 connectors**（MetalRenderer.edgeVertices 改）

```swift
// 原 edgeVertices 的 snapshot.edges.zip(...) → snapshot.connectors：
return snapshot.connectors
    .filter { visibleIds.contains($0.id) || true }  // 暂保留可见性过滤占位（Task 5 精化）
    .flatMap { connector in
        zip(connector.path, connector.path.dropFirst()).flatMap { start, end in
            segmentQuad(from: camera.worldToScreen(start), to: camera.worldToScreen(end),
                        thickness: thickness, color: color)
        }
    }
```
（注：`EdgeGeometry.fromId/toId` 用于可见性过滤；Connector 只有 `id`（父或子）。Task 5 精化过滤语义——per-edge 用父/子任一可见，brace 用父可见。）

- [ ] **Step 6: 更新全部引用**（PNGExporter 无直接引用；LayoutPipeline 不变；测试改 `snap.connectors`）
Run: `xcodebuild build -project YMindApp/YMindApp.xcodeproj -scheme YMindApp`
Expected: 编译通过。

- [ ] **Step 7: 跑测试确认通过**
Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -only-testing:YMindAppTests/RadialLayoutTests -only-testing:YMindAppTests/LogicLayoutTests -only-testing:YMindAppTests/LayoutPipelineTests`
Expected: PASS。

- [ ] **Step 8: Commit**
```bash
git add YMindApp/YMindApp/Layout/LayoutSnapshot.swift YMindApp/YMindApp/Layout/RadialLayout.swift YMindApp/YMindApp/Layout/LogicLayout.swift YMindApp/YMindApp/Render/MetalRenderer.swift YMindApp/YMindAppTests/RadialLayoutTests.swift YMindApp/YMindAppTests/LogicLayoutTests.swift YMindApp/YMindAppTests/LayoutPipelineTests.swift
git commit -m "refactor(edge-style): unify EdgeGeometry into ConnectorGeometry; LayoutSnapshot.connectors"
```

---

### Task 4: EdgeStyleProvider 抽象 + 引擎拆 placeFrames + Elbow/Curve/Brace Provider

**Files:**
- Create: `YMindApp/YMindApp/Layout/EdgeStyleProvider.swift`, `YMindApp/YMindApp/Layout/EdgeStyleRegistry.swift`, `YMindApp/YMindApp/Layout/EdgeStyleProviders.swift`（含 Elbow/Curve/Brace Provider）
- Modify: `YMindApp/YMindApp/Layout/LayoutSupport.swift`, `YMindApp/YMindApp/Layout/RadialLayout.swift`, `YMindApp/YMindApp/Layout/LogicLayout.swift`, `YMindApp/YMindApp/Session/LayoutPipeline.swift`
- Test: `YMindApp/YMindAppTests/EdgeStyleRegistryTests.swift`（新建）, `YMindApp/YMindAppTests/LayoutPipelineTests.swift`, `YMindApp/YMindAppTests/RadialLayoutTests.swift`, `YMindApp/YMindAppTests/LogicLayoutTests.swift`

**Interfaces:**
- Produces: `EdgeStyleProvider` protocol、`EdgeStyleRegistry.provider(for:)`、`LayoutSupport.edgePoints(from:to:style:)`、`LayoutSupport.sampleCubic(...)`、`RadialLayout.placeFrames(document:measure:) -> [UUID: NodeFrame]`、`LogicLayout.placeFrames(...)`、`BraceProvider`。
- Consumes: `ConnectorGeometry`（Task 3）、`EdgeStyle`（Task 1）。

- [ ] **Step 1: 写失败测试**（EdgeStyleRegistryTests）

```swift
func testRegistryResolvesAllStyles() {
    for style in EdgeStyle.allCases {
        let p = EdgeStyleRegistry.provider(for: style)
        XCTAssertFalse(type(of: p) == EmptyProvider.self)  // 每个样式都有 Provider
    }
    XCTAssertFalse(EdgeStyleRegistry.provider(for: .brace).requiresLogicArrangement)
    XCTAssertTrue(EdgeStyleRegistry.provider(for: .brace).requiresLogicArrangement)
}
```

- [ ] **Step 2: 跑测试确认失败**
Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -only-testing:YMindAppTests/EdgeStyleRegistryTests`
Expected: FAIL（类型不存在）。

- [ ] **Step 3: 实现 Provider 抽象 + registry**（EdgeStyleProvider.swift / EdgeStyleRegistry.swift）

```swift
// EdgeStyleProvider.swift
protocol EdgeStyleProvider {
    /// 是否需要逻辑树排布（brace=true；per-edge=false）。
    var requiresLogicArrangement: Bool { get }
    func connectors(document: MindMapDocument, frames: [UUID: NodeFrame],
                    root: Node, measure: TextMeasure) -> [ConnectorGeometry]
}
// 占位（测试用）：不应被 registry 返回
struct EmptyProvider: EdgeStyleProvider {
    var requiresLogicArrangement: Bool { false }
    func connectors(document: MindMapDocument, frames: [UUID: NodeFrame],
                    root: Node, measure: TextMeasure) -> [ConnectorGeometry] { [] }
}
```

```swift
// EdgeStyleRegistry.swift
enum EdgeStyleRegistry {
    static func provider(for style: EdgeStyle) -> EdgeStyleProvider {
        switch style {                       // 唯一 switch 处
        case .elbow: return ElbowProvider()
        case .curve: return CurveProvider()
        case .brace: return BraceProvider()
        }
    }
}
```

- [ ] **Step 4: LayoutSupport 几何基元**（LayoutSupport.swift 增）

```swift
/// 每边样式的折线：elbow 正交折线；curve 水平切向 S 曲线采样。
static func edgePoints(from: CGPoint, to: CGPoint, style: EdgeStyle) -> [CGPoint] {
    switch style {
    case .elbow:
        let mx = (from.x + to.x) / 2
        return [from, CGPoint(x: mx, y: from.y), CGPoint(x: mx, y: to.y), to]
    case .curve:
        let dx = to.x - from.x, dy = to.y - from.y
        if abs(dx) >= abs(dy) {
            let dir: CGFloat = dx >= 0 ? 1 : -1
            let k = max(18, min(56, abs(dx) * 0.4))
            return sampleCubic(from, CGPoint(x: from.x + dir*k, y: from.y),
                               CGPoint(x: to.x - dir*k, y: to.y), to, segments: 20)
        } else {
            let dir: CGFloat = dy >= 0 ? 1 : -1
            let k = max(18, min(56, abs(dy) * 0.4))
            return sampleCubic(from, CGPoint(x: from.x, y: from.y + dir*k),
                               CGPoint(x: to.x, y: to.y - dir*k), to, segments: 20)
        }
    case .brace: return []   // brace 不走此基元
    }
}

/// 三次贝塞尔采样（Bernstein）。
static func sampleCubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint,
                        segments: Int) -> [CGPoint] {
    var pts: [CGPoint] = []
    for i in 0...segments {
        let t = CGFloat(i) / CGFloat(segments)
        let u = 1 - t
        let x = u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p1.x
        let y = u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p1.y
        pts.append(CGPoint(x: x, y: y))
    }
    return pts
}
```

- [ ] **Step 5: 引擎拆 place**（RadialLayout / LogicLayout；签名统一，见 ledger Ruling）

```swift
// RadialLayout：把 layout() 拆为 place(document:measure:)，返回排布元组；删产边逻辑。
static func place(document: MindMapDocument, measure: TextMeasure)
    -> (frames: [UUID: NodeFrame], branchToggles: [BranchToggle], imagePayloads: [UUID: ImagePayload]) {
    var frames: [UUID: NodeFrame] = [:]
    var toggles: [BranchToggle] = []
    // ……复用现有 placeBranch 排布逻辑，只填充 frames 与 toggles；不再产 edge/connector。
    let payloads = LayoutSupport.collectImagePayloads(root: document.root, frames: frames)
    return (frames, toggles, payloads)
}
// LogicLayout 同理。
```
> 说明：`place(document:measure:)` 返回排布元组（frames/toggles/payloads），LayoutPipeline 与 PNGExporter 共用。旧 `layout()` 删除（由 Pipeline / PNGExporter 改用 `place`）。

- [ ] **Step 6: 实现三个 Provider**（EdgeStyleProviders.swift）

```swift
struct ElbowProvider: EdgeStyleProvider {
    var requiresLogicArrangement: Bool { false }
    func connectors(document: MindMapDocument, frames: [UUID: NodeFrame],
                    root: Node, measure: TextMeasure) -> [ConnectorGeometry] {
        // 遍历父子对，每对产一个 Connector：edgePoints(from:to:.elbow)
        var out: [ConnectorGeometry] = []
        func walk(_ node: Node) {
            guard let pf = frames[node.id] else { return }
            for c in node.children {
                if let cf = frames[c.id] {
                    let p = CGPoint(x: pf.center.x + sideDir(pf.side) * pf.size.width/2, y: pf.center.y)
                    let q = CGPoint(x: cf.center.x - sideDir(cf.side) * cf.size.width/2, y: cf.center.y)
                    out.append(ConnectorGeometry(id: c.id,
                        path: LayoutSupport.edgePoints(from: p, to: q, style: .elbow), marker: nil))
                }
                walk(c)
            }
        }
        walk(root)
        return out
    }
}
// CurveProvider 同构，style 用 .curve。
// BraceProvider：
struct BraceProvider: EdgeStyleProvider {
    var requiresLogicArrangement: Bool { true }
    func connectors(document: MindMapDocument, frames: [UUID: NodeFrame],
                    root: Node, measure: TextMeasure) -> [ConnectorGeometry] {
        // 递归：每有子父节点产一个 "}" Connector（几何按 spec §4.2 / addendum §3）。
        // 父 = 首末子 center.y 中点；xTip/xStem/xRight/r 按公式；marker = 折叠圆圈(可选)。
        // 用 frames 定位子节点；父 stem 并入 path 首段。
        var out: [ConnectorGeometry] = []
        func brace(_ node: Node) {
            let kids = node.children
            if !kids.isEmpty {
                if let pf = frames[node.id],
                   let fc = frames[kids[0].id], let lc = frames[kids[kids.count-1].id] {
                    out.append(Self.buildBrace(parent: pf, first: fc, last: lc, childCount: kids.count,
                                               isMain: node.id == root.id))
                }
                for k in kids { brace(k) }
            }
        }
        brace(root)
        return out
    }
    // buildBrace：按 spec §4.2 公式产 path（"}" Q/L 路径采样成折线）+ marker。
    // 实现细节见 addendum §3；原型 prototype/edge-style.html bracePath() 为参考实现。
}
```
> 说明：`sideDir(_ side: Side?)` 为本地辅助（left → -1，否则 1）；`buildBrace` 完整实现参照原型 `bracePath()` 与 spec §4.2 公式，产出含父 stem 首段的 `path`。

- [ ] **Step 7: LayoutPipeline 用 Provider**（LayoutPipeline.relayout）

```swift
func relayout(document: MindMapDocument) -> LayoutSnapshot {
    let provider = EdgeStyleRegistry.provider(for: document.edgeStyle)
    let arrangement: LayoutKind = provider.requiresLogicArrangement ? .logic : document.layout
    let placed: (frames: [UUID: NodeFrame], toggles: [BranchToggle], payloads: [UUID: ImagePayload])
    switch arrangement {
    case .radial: placed = RadialLayout.place(document: document, measure: measure)
    case .logic:  placed = LogicLayout.place(document: document, measure: measure)
    }
    let connectors = provider.connectors(document: document, frames: placed.frames,
                                         root: document.root, measure: measure)
    return LayoutSnapshot(frames: placed.frames, connectors: connectors,
                          branchToggles: placed.toggles, imagePayloads: placed.payloads)
}
```
> 说明：`place(document:measure:)` 返回 `(frames, toggles, payloads)` 元组（`placeFrames` 的扩展）。旧 `layout()` 删除或保留为测试便利。

- [ ] **Step 8: PNGExporter 走 Pipeline（ledger Ruling — 非零改动）**

`PNGExporter.data(...)` 里 `expanded` 后改为：
```swift
// 删掉直连引擎的 switch（RadialLayout/LogicLayout.layout 已删）；走 Pipeline（有效排布 + Provider）。
let snapshot = LayoutPipeline().relayout(document: expanded)
```
（`LayoutPipeline` 在 `Session/`，同模块可直接用；删除 `case .radial/.logic` switch，消除对 `layout()` 的依赖。）

- [ ] **Step 9: 跑测试确认通过**（registry + pipeline + radial/logic + 新 Provider + 导出）
Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -only-testing:YMindAppTests/EdgeStyleRegistryTests -only-testing:YMindAppTests/LayoutPipelineTests -only-testing:YMindAppTests/RadialLayoutTests -only-testing:YMindAppTests/LogicLayoutTests -only-testing:YMindAppTests/PNGExporterTests`
Expected: PASS（且 brace 产 Connector、elbow/curve 产每边 Connector、PNG 导出按当前样式）。

- [ ] **Step 10: 更新 DocumentSession fit 用 Provider**（替换 Task 2 的临时 `effectiveArrangement`）
```swift
private func effectiveArrangement() -> LayoutKind {
    EdgeStyleRegistry.provider(for: model.document.edgeStyle).requiresLogicArrangement
        ? .logic : model.document.layout
}
```
Run 相关 DocumentSessionTests。Expected: PASS。

- [ ] **Step 11: Commit**
```bash
git add YMindApp/YMindApp/Layout/EdgeStyleProvider.swift YMindApp/YMindApp/Layout/EdgeStyleRegistry.swift YMindApp/YMindApp/Layout/EdgeStyleProviders.swift YMindApp/YMindApp/Layout/LayoutSupport.swift YMindApp/YMindApp/Layout/RadialLayout.swift YMindApp/YMindApp/Layout/LogicLayout.swift YMindApp/YMindApp/Session/LayoutPipeline.swift YMindApp/YMindApp/Session/DocumentSession.swift YMindApp/YMindApp/Render/PNGExporter.swift YMindApp/YMindAppTests/EdgeStyleRegistryTests.swift YMindApp/YMindAppTests/LayoutPipelineTests.swift YMindApp/YMindAppTests/RadialLayoutTests.swift YMindApp/YMindAppTests/LogicLayoutTests.swift YMindApp/YMindAppTests/PNGExporterTests.swift
git commit -m "feat(edge-style): EdgeStyleProvider abstraction + place split + Elbow/Curve/Brace providers"
```

---

### Task 5: 渲染 connectorVertices（path 描边 + marker 圆圈）

**Files:**
- Modify: `YMindApp/YMindApp/Render/MetalRenderer.swift`
- Test: `YMindApp/YMindAppTests/*`（冒烟：真 Metal 渲染不崩、输出含预期段数）

**Interfaces:**
- Consumes: `ConnectorGeometry` / `ConnectorMarker`（Task 3）、Provider 产出的 connectors（Task 4）。
- Produces: `MetalRenderer.connectorVertices(snapshot:visibleIds:camera:)`（替换 `edgeVertices`/`braceVertices`）。

- [ ] **Step 1: 写失败测试**（Render 冒烟：构造 snapshot 含 connector + marker，渲染产顶点）
```swift
// MetalRendererTests（若不存在则新建冒烟，见全局测试约定）
func testConnectorVerticesStrokesPathAndMarker() {
    let renderer = MetalRenderer()
    let snap = LayoutSnapshot(
        frames: [:],
        connectors: [
            ConnectorGeometry(id: UUID(), path: [.zero, CGPoint(x: 10, y: 10)],
                              marker: ConnectorMarker(kind: .circle, center: CGPoint(x: 5, y: 5), radius: 2))
        ])
    let v = renderer.connectorVertices(snapshot: snap, visibleIds: Set(), camera: Camera())
    XCTAssertFalse(v.isEmpty)
}
```

- [ ] **Step 2: 跑测试确认失败**
Expected: FAIL（`connectorVertices` 不存在）。

- [ ] **Step 3: 实现 connectorVertices**（MetalRenderer，替换 edgeVertices/braceVertices）
```swift
private func connectorVertices(snapshot: LayoutSnapshot, visibleIds: Set<UUID>,
                               camera: Camera) -> [SolidVertex] {
    let color = rgba(.separatorColor)
    let thickness = max(1.25, min(3, 2 * camera.scale))
    // 可见性：per-edge 用父/子任一可见；brace 用父可见（本实现统一按 id 可见过滤，精化见注释）。
    var out: [SolidVertex] = []
    for c in snapshot.connectors where visibleIds.contains(c.id) {
        out += zip(c.path, c.path.dropFirst()).flatMap { s, e in
            segmentQuad(from: camera.worldToScreen(s), to: camera.worldToScreen(e),
                        thickness: thickness, color: color)
        }
        if let m = c.marker {
            let center = camera.worldToScreen(m.center)
            let r = m.radius * camera.scale
            out += circleVertices(center: center, radius: r, color: color)
        }
    }
    return out
}
// circleVertices：圆近似（多边形，如 16 段），或复用现有 rectangleQuad/自定义。实现时按现有顶点样式补。
```
（删除 `edgeVertices` / `braceVertices`；`draw(...)` 调用点改 `connectorVertices`。）

- [ ] **Step 4: 跑测试确认通过** + 全量编译
Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp`
Expected: PASS，编译通过。

- [ ] **Step 5: Commit**
```bash
git add YMindApp/YMindApp/Render/MetalRenderer.swift
git commit -m "feat(edge-style): connectorVertices render (path stroke + marker circle)"
```

---

### Task 6: 工具栏连线样式 Picker（CaseIterable）

**Files:**
- Modify: `YMindApp/YMindApp/App/MainToolbar.swift`
- Test: 冒烟（构建 + UI 冒烟，见全局验证）。

**Interfaces:**
- Consumes: `EdgeStyle.allCases`、`session.edgeStyle` / `session.setEdgeStyle(_:)`（Task 1/2）。

- [ ] **Step 1: 写测试**（构建层冒烟：工具栏含 Picker 且三选项）
- [ ] **Step 2: 实现**（MainToolbar，镜像现有布局 Picker）
```swift
// MainToolbar 结构体加：
let edgeStyle: EdgeStyle
let setEdgeStyle: (EdgeStyle) -> Void

// toolbar 内（布局 Picker 后）：
Picker("连线样式", selection: Binding(
    get: { edgeStyle },
    set: { setEdgeStyle($0) }
)) {
    Text("折线").tag(EdgeStyle.elbow)
    Text("曲线").tag(EdgeStyle.curve)
    Text("大括号").tag(EdgeStyle.brace)
}
.pickerStyle(.menu)
.help("连线样式（⇧E 切换）")
```
（ContentView 传 `edgeStyle: session.edgeStyle`、`setEdgeStyle: { session.setEdgeStyle($0) }`。）

- [ ] **Step 3: 构建 + 冒烟验证**
Run: `xcodebuild build -project YMindApp/YMindApp.xcodeproj -scheme YMindApp`
Expected: 编译通过；`check-boundaries.sh` 绿。
- [ ] **Step 4: Commit**
```bash
git add YMindApp/YMindApp/App/MainToolbar.swift YMindApp/YMindApp/ContentView.swift
git commit -m "feat(edge-style): toolbar edge-style picker (CaseIterable)"
```

---

### Task 7: 扩展性回归 — 加 straight 样式验证 D7

**Files:**
- Create: `YMindApp/YMindApp/Layout/StraightStyleProvider.swift`
- Modify: `YMindApp/YMindApp/Model/MindMapDocument.swift`, `YMindApp/YMindApp/Layout/EdgeStyleRegistry.swift`
- Test: `YMindApp/YMindAppTests/EdgeStyleRegistryTests.swift`

**Interfaces:**
- Consumes: `EdgeStyle`、`EdgeStyleRegistry`、`LayoutSupport.edgePoints`。
- Produces: `EdgeStyle.straight` case + `StraightStyleProvider`（直线）。

> 目的：证明「加样式 = enum case + Provider 文件 + registry 注册」即可（引擎/Render/Codec 零改动）。此样式仅作回归验证，**不入最终 UI 三选一**（`Picker` 仍显式三 option；若要暴露，把 Picker 改 `ForEach(EdgeStyle.allCases)` 并加 label——本任务先验证机制，UI 保持三选一）。

- [ ] **Step 1: 写失败测试**
```swift
func testStraightStyleResolves() {
    XCTAssertFalse(EdgeStyleRegistry.provider(for: .straight).requiresLogicArrangement)
    // 产一条直线 connector
}
```
- [ ] **Step 2: 跑测试确认失败**
- [ ] **Step 3: 实现**
```swift
// EdgeStyle 加 case straight
// EdgeStyleRegistry.provider(for:) 加 case .straight: return StraightProvider()
// StraightStyleProvider.swift：
struct StraightStyleProvider: EdgeStyleProvider {
    var requiresLogicArrangement: Bool { false }
    func connectors(document: MindMapDocument, frames: [UUID: NodeFrame],
                    root: Node, measure: TextMeasure) -> [ConnectorGeometry] {
        // 每对父-子产直线 Connector：path = [from, to]（两点直线）。
        // 复用 ElbowProvider 遍历骨架，path 改为 [p, q]。
        … // 同 ElbowProvider 遍历，path = [p, q]
    }
}
```
- [ ] **Step 4: 跑测试确认通过**（确认只动 enum + Provider + registry）
Run: `xcodebuild test -project YMindApp/YMindApp.xcodeproj -scheme YMindApp -only-testing:YMindAppTests/EdgeStyleRegistryTests`
Expected: PASS。
- [ ] **Step 5: Commit**
```bash
git add YMindApp/YMindApp/Layout/StraightStyleProvider.swift YMindApp/YMindApp/Model/MindMapDocument.swift YMindApp/YMindApp/Layout/EdgeStyleRegistry.swift YMindApp/YMindAppTests/EdgeStyleRegistryTests.swift
git commit -m "test(edge-style): straight style proves D7 extensibility (enum+provider+registry)"
```

---

## Self-Review 记录

- **Spec 覆盖**：D1（curve S 曲线）→ Task 4 CurveProvider；D2/D3（brace 组连接器 + 逻辑树）→ Task 4 BraceProvider + Pipeline；D4（Codec v7）→ Task 1；D5（命令）→ Task 2；D6（Connector 契约）→ Task 3/5；D7（Provider 抽象）→ Task 4/7；D8（fit）→ Task 2/4。FR-E1（模型+Codec）→ T1；E2（几何）→ T3/T4；E3（渲染）→ T5；E4（切换器）→ T6；E5（导出）→ T4（Pipeline 零改动 PNGExporter）。
- **占位扫描**：无 TBD；`buildBrace`/`circleVertices` 标注「参照原型/现有实现」，有明确来源（spec §4.2、原型 bracePath、现有顶点样式），非占位。
- **类型一致性**：`ConnectorGeometry(id:path:marker:)` 全计划一致；`EdgeStyleProvider.connectors(document:frames:root:measure:)` 一致；`placeFrames`/`place(document:measure:)` 返回元组一致（Task 4 Step 5/7 对齐）。

**Execution Handoff:** 计划已存 `docs/superpowers/plans/2026-10-04-edge-style.md`。两种执行方式：**1. Subagent-Driven（推荐）** 每任务派新 subagent、任务间评审；**2. Inline** 本会话用 executing-plans 分批 + 检查点。选哪种？
