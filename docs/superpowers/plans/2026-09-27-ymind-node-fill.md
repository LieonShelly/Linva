# YMind 节点轻填色 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 YMind 节点加 5 个预设填色 token（sage/sky/sand/rose/lilac）+ 默认清除，工具条色点套用/清除选中节点填色，含 Undo、持久化 v2、复制粘贴保留。

**Architecture:** 分层增量：Model 存 `Node.fill: NodeFill?`（typed enum，lenient 解码）→ `.ymind` v2 迁移 → 新命令 `setFill` 一步 Undo → `NodeFrame.fill` 经 Layout 传给 Render → Metal 按 token 取系统语义色（动态 `NSColor`）画浅底+边框 / 根深色 → 工具条色点组（5 色 + 默认）套用。调色板单一来源 `NodeFillStyle` 在 Render 层。

**Tech Stack:** Swift 6、SwiftUI（工具条）、Metal（画布）、Swift Testing（`@Suite`/`@Test`）。无新 shader、无新依赖。

**Spec:** `docs/superpowers/specs/2026-09-27-ymind-node-fill-design.md`（本 plan 从 spec 论证；执行者需同时读 spec 与本文）。需求真源：`docs/prds/prd-ymind-style-2026-09-25/prd.md`（已按 spec 回写调色板）。

## Global Constraints

（逐条取自 spec，所有 task 隐式包含本节）

- `NodeFill` 固定 5 token：`sage` / `sky` / `sand` / `rose` / `lilac`；nil = 默认外观（spec §3.1，PRD FR-C1）。
- 未知/缺失 fill token 解码为 nil（spec §3.1，PRD §7）。
- `.ymind` `currentVersion` 从 1 升到 2；decode 迁移 v1→v2（fill 缺省 nil，仅版本升迁）；非 1/2 版本仍抛 `unsupportedVersion`（spec §4.1，ymind-codec-version 铁律）。
- `NodeFrame` 新增 `let fill: NodeFill?`，**显式 init 带 `fill: NodeFill? = nil` 默认值**（保持既有直接构造点零改动）。
- 调色板：系统语义色派生（token 色相 + 系统语义明度 → 动态 `NSColor`，随亮/暗外观自适应），放 **Render** 层 `Render/NodeFillStyle.swift`（import AppKit 在白名单内）；**不落 Model**（Model 仅 Foundation）（spec §3.2、§2.2）。
- 视觉：有 fill 普通节点 = 浅底 `background` + 协调边框 `border`（描边厚度 `max(1, 1.5 * camera.scale)`）；根 = `rootBackground` 深色变体；无 fill 维持现状（普通节点 `controlBackgroundColor`、根 `controlAccentColor`，**不新增边框**）（spec §7、§1.2）。
- 文字色不变：普通节点 `labelColor`、根 `white`（spec §7）。
- 命令 `setFill` 一步 Undo/Redo；全无变化 → 不入栈；不改选中（spec §5）。
- 无新 shader、无新第三方依赖（边界脚本 `scripts/check-boundaries.sh` 不应新增违规：NodeFill.swift 仅 Foundation、NodeFillStyle.swift 仅 AppKit，均已在白名单）。
- 复制粘贴保留 fill：`Node` 值类型深拷贝天然携带，剪贴板代码不改（spec §1.2）。

---

### Task 1: Model — `NodeFill` token 与 `Node.fill`（lenient Codable）

**Files:**
- Create: `YMindApp/YMindApp/Model/NodeFill.swift`
- Modify: `YMindApp/YMindApp/Model/Node.swift`
- Test: `YMindApp/YMindAppTests/CodecTests.swift`

**Interfaces:**
- Consumes: 无（新类型）。
- Produces: `enum NodeFill: String, Codable, CaseIterable, Sendable, Equatable, Hashable`（case `sage, sky, sand, rose, lilac`）；`Node.fill: NodeFill?`（init 默认 nil）；`Node` 自定义 `init(from:)`（未知/缺失 fill → nil）。后续 Task 2、3、5、6、8 依赖这些名字与签名。

- [ ] **Step 1: 创建 `NodeFill.swift`**

```swift
import Foundation

/// 5 个具名预设填色 token；nil = 默认外观（PRD FR-C1）。
enum NodeFill: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case sage, sky, sand, rose, lilac
}
```

- [ ] **Step 2: 修改 `Node.swift` —— 加 `fill` 字段与 lenient Codable**

把文件替换为（原字段 + `fill` + 自定义 `init(from:)` + `CodingKeys`；`encode(to:)` 由编译器合成，nil 时省略字段）：

```swift
import Foundation

struct Node: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var text: String
    var collapsed: Bool
    var side: Side?
    var fill: NodeFill?
    var children: [Node]

    init(
        id: UUID = UUID(),
        text: String,
        collapsed: Bool = false,
        side: Side? = nil,
        fill: NodeFill? = nil,
        children: [Node] = []
    ) {
        self.id = id
        self.text = text
        self.collapsed = collapsed
        self.side = side
        self.fill = fill
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, collapsed, side, fill, children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        side = try c.decodeIfPresent(Side.self, forKey: .side)
        if let raw = try c.decodeIfPresent(String.self, forKey: .fill),
           let fill = NodeFill(rawValue: raw) {
            self.fill = fill
        } else {
            self.fill = nil
        }
        children = try c.decodeIfPresent([Node].self, forKey: .children) ?? []
    }
}
```

- [ ] **Step 3: 在 `CodecTests.swift` 加往返保留 fill 测试**

在 `struct CodecTests` 内追加（`@testable import YMindApp` 已存在）：

```swift
@Test func roundTrip_preservesFill() throws {
    let model = MindMapModel.makeNew()
    model.document.root.fill = .sage
    let child = model.insertChild(parentId: model.document.root.id, text: "子", side: .left, at: nil)
    _ = model.mutate(id: child) { $0.fill = .rose }
    let data = try YMindCodec.encode(model.document)
    let decoded = try YMindCodec.decode(data)
    #expect(decoded == model.document)
    #expect(decoded.root.fill == .sage)
    #expect(decoded.root.children[0].fill == .rose)
}
```

> 此时 `currentVersion` 仍是 1，encode/decode 用当前版本，测试独立于后续版本升迁，不会因 Task 2 破坏。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/renjun.li/Desktop/YMind && xcodebuild test -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/CodecTests`
Expected: `roundTrip_preservesFill` 等全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Model/NodeFill.swift YMindApp/YMindApp/Model/Node.swift YMindApp/YMindAppTests/CodecTests.swift
git commit -m "feat: Node.fill 填色字段 + lenient Codable（未知 token→nil）"
```

---

### Task 2: Codec — `.ymind` v2 与 v1→v2 迁移

**Files:**
- Modify: `YMindApp/YMindApp/Model/MindMapDocument.swift`（`currentVersion` 1→2）
- Modify: `YMindApp/YMindApp/Model/YMindCodec.swift`（decode 迁移）
- Test: `YMindApp/YMindAppTests/CodecTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `Node.fill` 与 lenient `init(from:)`。
- Produces: `MindMapDocument.currentVersion == 2`；`decode(_:warnings:)` 接受 version 1（迁移到 2）与 2，其余版本抛 `unsupportedVersion`。Task 8 之外无下游依赖，但所有后续 encode/decode 测试以此为准。

- [ ] **Step 1: 升 `currentVersion`**

在 `MindMapDocument.swift`：

```swift
    static let currentVersion = 2
```

- [ ] **Step 2: `YMindCodec.decode` 加 v1→v2 迁移**

把 `decode(_:warnings:)` 改为（`doc` 由 `let` 改 `var`，先迁移再校验）：

```swift
    static func decode(_ data: Data, warnings: inout [String]?) throws -> MindMapDocument {
        var doc: MindMapDocument
        do {
            doc = try decoder.decode(MindMapDocument.self, from: data)
        } catch {
            throw YMindCodecError.decodingFailed
        }
        // 迁移：v1 → v2（fill 缺省 nil，仅版本号升迁；Node 解码器对缺失 fill 天然容错）。
        if doc.version == 1 {
            doc.version = 2
        }
        guard doc.version == MindMapDocument.currentVersion else {
            throw YMindCodecError.unsupportedVersion(doc.version)
        }
        return sanitize(doc, warnings: &warnings)
    }
```

- [ ] **Step 3: 更新既有 `stripsDeepSide` 测试 JSON 版本为 2**

`CodecTests.swift` 中 `stripsDeepSide` 的 JSON `{"version":1,...` 改为 `{"version":2,...`（该测试专注 side 消毒，不测迁移；避免与迁移语义纠缠）。其余断言不变。

- [ ] **Step 4: 加迁移与未知 token 测试**

`CodecTests.swift` 内追加：

```swift
@Test func migratesV1ToV2() throws {
    let json = """
    {"version":1,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"children":[{"id":"00000000-0000-0000-0000-000000000002","text":"子","collapsed":false,"children":[]}]}}
    """.data(using: .utf8)!
    let doc = try YMindCodec.decode(json)
    #expect(doc.version == 2)
    #expect(doc.root.fill == nil)
    #expect(doc.root.children[0].fill == nil)
}

@Test func unknownFillToken_decodesAsNil() throws {
    let json = """
    {"version":2,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"fill":"neon","children":[]}}
    """.data(using: .utf8)!
    let doc = try YMindCodec.decode(json)
    #expect(doc.version == 2)
    #expect(doc.root.fill == nil)
}
```

- [ ] **Step 5: 跑 CodecTests 确认通过**

Run: `xcodebuild test -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/CodecTests`
Expected: 全部 PASS（含既有 `roundTrip`、`rejectsUnknownVersion`、更新后的 `stripsDeepSide`、新增两项）。

- [ ] **Step 6: Commit**

```bash
git add YMindApp/YMindApp/Model/MindMapDocument.swift YMindApp/YMindApp/Model/YMindCodec.swift YMindApp/YMindAppTests/CodecTests.swift
git commit -m "feat: .ymind v2 + v1→v2 迁移（fill 缺省 nil）"
```

---

### Task 3: Command — `setFill` 一步 Undo/Redo

**Files:**
- Modify: `YMindApp/YMindApp/Commands/MindMapCommand.swift`
- Modify: `YMindApp/YMindApp/Model/MindMapModel.swift`
- Modify: `YMindApp/YMindApp/Commands/CommandBus.swift`
- Test: `YMindApp/YMindAppTests/CommandBusTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `NodeFill`。
- Produces:
  - `MindMapCommand.setFill(ids: [UUID], fill: NodeFill?)`（enum case，Equatable 合成）。
  - `MindMapModel.setFill(ids: [UUID], fill: NodeFill?) -> [(id: UUID, oldFill: NodeFill?)]`。
  - `CommandBus.applyForward` 处理 `.setFill`：全无变化返回 nil（不入栈）；undo/redo 逐节点还原。Task 4（Session 门面）依赖 `commandBus.execute(.setFill(...))`。

- [ ] **Step 1: `MindMapCommand.swift` 加 case**

在枚举末尾（`pasteAsChild` 之后）追加：

```swift
    case setFill(ids: [UUID], fill: NodeFill?)
```

- [ ] **Step 2: `MindMapModel.swift` 加 `setFill` 方法**

在 `setCollapsed(id:to:)` 附近加（`mutate` 是既有方法，可改根与任意节点）：

```swift
    /// 对选中集每个节点写同一 fill（含根）；返回被改节点旧值供 Undo。不改选中。
    @discardableResult
    func setFill(ids: [UUID], fill: NodeFill?) -> [(id: UUID, oldFill: NodeFill?)] {
        var changes: [(id: UUID, oldFill: NodeFill?)] = []
        var seen = Set<UUID>()
        for id in ids where seen.insert(id).inserted {
            guard let node = node(id: id), node.fill != fill else { continue }
            changes.append((id, node.fill))
            _ = mutate(id: id) { $0.fill = fill }
        }
        return changes
    }
```

- [ ] **Step 3: `CommandBus.applyForward` 加 `.setFill` 分支**

在 `case let .applyRootSide(...)` 之后、`case let .pasteAsChild(...)` 之前加：

```swift
        case let .setFill(ids, fill):
            let changes = model.setFill(ids: ids, fill: fill)
            guard !changes.isEmpty else { return nil }
            return Entry(
                undo: {
                    for c in changes {
                        _ = self.model.mutate(id: c.id) { $0.fill = c.oldFill }
                    }
                },
                redo: {
                    _ = self.model.setFill(ids: ids, fill: fill)
                }
            )
```

- [ ] **Step 4: 加 `CommandBusTests` 测试**

在 `struct CommandBusTests` 内追加：

```swift
@Test func setFill_undoRedo_restoresEachOldValue() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    let a = model.insertChild(parentId: root, text: "A", side: .left, at: nil)
    let b = model.insertChild(parentId: root, text: "B", side: .right, at: nil)
    model.document.root.fill = .sage
    _ = model.mutate(id: a) { $0.fill = .sky }
    bus.clearHistory()
    bus.execute(.setFill(ids: [root, a, b], fill: .lilac))
    #expect(model.node(id: root)?.fill == .lilac)
    #expect(model.node(id: a)?.fill == .lilac)
    #expect(model.node(id: b)?.fill == .lilac)
    bus.undo()
    #expect(model.node(id: root)?.fill == .sage)
    #expect(model.node(id: a)?.fill == .sky)
    #expect(model.node(id: b)?.fill == nil)
    bus.redo()
    #expect(model.node(id: root)?.fill == .lilac)
    #expect(model.node(id: a)?.fill == .lilac)
    #expect(model.node(id: b)?.fill == .lilac)
}

@Test func setFill_noChange_isNoOp() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    bus.execute(.setFill(ids: [root], fill: nil))
    #expect(!bus.canUndo)
    model.document.root.fill = .sage
    bus.execute(.setFill(ids: [root], fill: .sage))
    #expect(!bus.canUndo)
}
```

- [ ] **Step 5: 跑 CommandBusTests 确认通过**

Run: `xcodebuild test -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/CommandBusTests`
Expected: 全部 PASS（含既有 setSide/applyRootSide 等，确保未回归）。

- [ ] **Step 6: Commit**

```bash
git add YMindApp/YMindApp/Commands/MindMapCommand.swift YMindApp/YMindApp/Model/MindMapModel.swift YMindApp/YMindApp/Commands/CommandBus.swift YMindApp/YMindAppTests/CommandBusTests.swift
git commit -m "feat: setFill 命令（一步 Undo，no-op 不入栈）"
```

---

### Task 4: Session — `setFill` 门面 + 剪贴板保留 fill 测试

**Files:**
- Modify: `YMindApp/YMindApp/Session/DocumentSession.swift`
- Test: `YMindApp/YMindAppTests/ClipboardTests.swift`

**Interfaces:**
- Consumes: Task 3 的 `commandBus.execute(.setFill(ids:fill:))`。
- Produces: `DocumentSession.setFill(_ fill: NodeFill?)`（先 `commitEditingIfNeeded()`，再对 `model.selectedIds` 执行 `.setFill`）。Task 8（ContentView）依赖此方法。

- [ ] **Step 1: `DocumentSession.swift` 加 `setFill` 门面**

在 `canPaste` / `startEditing` 附近（`pasteToPrimary` 之后即可）加：

```swift
    func setFill(_ fill: NodeFill?) {
        commitEditingIfNeeded()
        commandBus.execute(.setFill(ids: Array(model.selectedIds), fill: fill))
    }
```

- [ ] **Step 2: 加 `ClipboardTests` 复制粘贴保留 fill 测试**

`ClipboardTests.swift` 内追加：

```swift
@Test func copyPaste_preservesFill() {
    let session = DocumentSession()
    let root = session.model.document.root.id
    let a = session.model.insertChild(parentId: root, text: "A", side: .right, at: nil)
    _ = session.model.mutate(id: a) { $0.fill = .sage }
    session.selectOnly(a)
    session.copySelection()
    let t = session.model.insertChild(parentId: root, text: "T", side: .left, at: nil)
    session.selectOnly(t)
    session.pasteToPrimary()
    #expect(session.model.node(id: t)?.children[0].fill == .sage)
}
```

- [ ] **Step 3: 跑测试确认通过**

Run: `xcodebuild test -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/ClipboardTests -only-testing:YMindAppTests/DocumentSessionTests`
Expected: 全部 PASS。

- [ ] **Step 4: Commit**

```bash
git add YMindApp/YMindApp/Session/DocumentSession.swift YMindApp/YMindAppTests/ClipboardTests.swift
git commit -m "feat: Session.setFill 门面 + 剪贴板保留 fill 测试"
```

---

### Task 5: Layout — `NodeFrame.fill` 传递

**Files:**
- Modify: `YMindApp/YMindApp/Layout/LayoutSnapshot.swift`
- Modify: `YMindApp/YMindApp/Layout/RadialLayout.swift`
- Test: `YMindApp/YMindAppTests/RadialLayoutTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `NodeFill`、`Node.fill`。
- Produces: `NodeFrame.fill: NodeFill?`（**显式 init，`fill: NodeFill? = nil` 默认值**）；`RadialLayout.layout` 产出的 root 与普通分支 frame 均带 `node.fill`。Task 6（Render）依赖 `frame.fill`。既有直接构造点（`HitTestTests` 等）因默认值零改动。

- [ ] **Step 1: `LayoutSnapshot.swift` —— `NodeFrame` 加 `fill` + 显式 init**

把 `struct NodeFrame: Equatable { ... }` 改为（保留 `rect` 计算属性）：

```swift
struct NodeFrame: Equatable {
    let id: UUID
    let text: String
    let center: CGPoint
    let size: NodeSize
    let isRoot: Bool
    let side: Side?
    let collapsed: Bool
    let hiddenCount: Int
    let fill: NodeFill?

    init(
        id: UUID,
        text: String,
        center: CGPoint,
        size: NodeSize,
        isRoot: Bool,
        side: Side?,
        collapsed: Bool,
        hiddenCount: Int,
        fill: NodeFill? = nil
    ) {
        self.id = id
        self.text = text
        self.center = center
        self.size = size
        self.isRoot = isRoot
        self.side = side
        self.collapsed = collapsed
        self.hiddenCount = hiddenCount
        self.fill = fill
    }

    var rect: CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
```

> `fill` 带默认 nil → 既有 `NodeFrame(...)` 构造（RadialLayoutTests/HitTestTests）无需改动即可编译。

- [ ] **Step 2: `RadialLayout.swift` 两处构造带入 `node.fill`**

普通分支构造（`placeBranch` 内）加一行：

```swift
                hiddenCount: node.collapsed ? countDescendants(node) : 0,
                fill: node.fill
```

根构造（`layout` 内 rootFrame）加一行：

```swift
            hiddenCount: document.root.collapsed
                ? countDescendants(document.root)
                : 0,
            fill: document.root.fill
```

- [ ] **Step 3: 加 `RadialLayoutTests` 传播测试**

`RadialLayoutTests.swift` 内追加：

```swift
@Test func frameCarriesNodeFill() {
    var doc = MindMapDocument.blank()
    doc.root.fill = .sage
    let child = Node(text: "子", side: .right, fill: .sky)
    doc.root.children = [child]
    let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
    #expect(snap.frames[doc.root.id]?.fill == .sage)
    #expect(snap.frames[child.id]?.fill == .sky)
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme YMindApp -destination 'platform=macOS' -only-testing:YMindAppTests/RadialLayoutTests`
Expected: 全部 PASS（既有各用例因默认值不受影响）。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Layout/LayoutSnapshot.swift YMindApp/YMindApp/Layout/RadialLayout.swift YMindApp/YMindAppTests/RadialLayoutTests.swift
git commit -m "feat: NodeFrame.fill 经 Layout 传递（显式 init 默认 nil）"
```

---

### Task 6: Render — 系统语义色调色板 + 填色绘制

**Files:**
- Create: `YMindApp/YMindApp/Render/NodeFillStyle.swift`
- Modify: `YMindApp/YMindApp/Render/MetalRenderer.swift`
- Test: 无单测（Metal 层偏手测，见架构现状 §7.4）；以编译通过 + 手测验证。

**Interfaces:**
- Consumes: Task 1 的 `NodeFill`、Task 5 的 `frame.fill`。
- Produces: `NodeFillStyle`（`static func swatch/background/border/rootBackground(_ fill: NodeFill) -> NSColor`，均为动态色）。Task 8（工具条）依赖 `NodeFillStyle.swatch(_:)`。Render 层 import AppKit 已在边界白名单，`scripts/check-boundaries.sh` 不应新增违规。

- [ ] **Step 1: 创建 `NodeFillStyle.swift`**

```swift
import AppKit

/// 系统语义色派生的单一来源（Render 层）。每个 token 保留身份色相，明度随外观解析。
enum NodeFillStyle {
    /// token 身份色相（HSB hue，0…1），取自原型 swatch 视觉锚。
    static let hue: [NodeFill: CGFloat] = [
        .sage: 0.34,   // 绿
        .sky: 0.57,    // 蓝
        .sand: 0.10,   // 暖金
        .rose: 0.01,   // 粉红
        .lilac: 0.74,  // 紫
    ]

    /// 工具条色点色。
    static func swatch(_ fill: NodeFill) -> NSColor {
        appearanceAware(hue: hue[fill]!, light: (0.30, 0.82), dark: (0.40, 0.62))
    }

    /// 普通节点浅底。
    static func background(_ fill: NodeFill) -> NSColor {
        appearanceAware(hue: hue[fill]!, light: (0.14, 0.94), dark: (0.24, 0.26))
    }

    /// 普通节点协调边框。
    static func border(_ fill: NodeFill) -> NSColor {
        appearanceAware(hue: hue[fill]!, light: (0.20, 0.58), dark: (0.30, 0.52))
    }

    /// 中心主题深色变体（白字可读）。
    static func rootBackground(_ fill: NodeFill) -> NSColor {
        appearanceAware(hue: hue[fill]!, light: (0.42, 0.30), dark: (0.38, 0.36))
    }

    /// 由 token 色相 + 明度档（s, b）构造随外观解析的动态 NSColor。
    private static func appearanceAware(
        hue: CGFloat,
        light: (s: CGFloat, b: CGFloat),
        dark: (s: CGFloat, b: CGFloat)
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let pair = isDark ? dark : light
            return NSColor(hue: hue, saturation: pair.s, brightness: pair.b, alpha: 1)
        }
    }
}
```

> 明度档为起点值，最终对比度以手测为准（spec §3.2 允许微调）；根深色与白字对比度必须满足可读。

- [ ] **Step 2: 重写 `MetalRenderer.fillVertices` 按 `frame.fill` 分派**

把 `fillVertices` 整体替换为：

```swift
    private func fillVertices(snapshot: LayoutSnapshot, camera: Camera) -> [SolidVertex] {
        orderedFrames(snapshot).flatMap { frame in
            let rect = screenRect(frame.rect, camera: camera)
            if let fill = frame.fill {
                if frame.isRoot {
                    return rectangleQuad(
                        rect: rect,
                        color: rgba(NodeFillStyle.rootBackground(fill))
                    )
                } else {
                    var vertices = rectangleQuad(
                        rect: rect,
                        color: rgba(NodeFillStyle.background(fill))
                    )
                    vertices += strokeVertices(
                        rect: rect,
                        thickness: max(1, 1.5 * camera.scale),
                        color: rgba(NodeFillStyle.border(fill))
                    )
                    return vertices
                }
            } else {
                let color = rgba(
                    frame.isRoot
                        ? NSColor.controlAccentColor
                        : NSColor.controlBackgroundColor
                )
                return rectangleQuad(rect: rect, color: color)
            }
        }
    }
```

> `rgba(_:)` 的 `usingColorSpace(.deviceRGB)` 会在绘制时把动态 `NSColor` 按当前外观解析为 SIMD（spec §7）。无新 shader、无新顶点类型。

- [ ] **Step 3: 编译 + 跑全量测试（确认未回归、边界通过）**

Run: `xcodebuild test -scheme YMindApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED（含边界校验 build phase）；全部测试 PASS。再单独确认边界脚本：
Run: `scripts/check-boundaries.sh`
Expected: `依赖边界检查通过: 各层 import 均在白名单内。`

- [ ] **Step 4: Commit**

```bash
git add YMindApp/YMindApp/Render/NodeFillStyle.swift YMindApp/YMindApp/Render/MetalRenderer.swift
git commit -m "feat: 填色绘制（系统语义色派生浅底+边框 / 根深色）"
```

---

### Task 7: Shell — 工具条色点组 + ContentView 接线

**Files:**
- Create: `YMindApp/YMindApp/App/FillSwatches.swift`
- Modify: `YMindApp/YMindApp/App/MainToolbar.swift`
- Modify: `YMindApp/YMindApp/ContentView.swift`
- Test: 无单测（SwiftUI 壳层手测，对齐 PRD §5 验收）。

**Interfaces:**
- Consumes: Task 3 的 `setFill` 命令语义、Task 4 的 `DocumentSession.setFill(_:)`、Task 6 的 `NodeFillStyle.swatch(_:)`、Task 1 的 `NodeFill`。
- Produces:
  - `FillSwatchesView`：`struct FillSwatchesView: View`，参数 `canSetFill: Bool`、`activeFill: NodeFill?`、`fillActive: Bool`、`setFill: (NodeFill?) -> Void`，渲染 6 个色点。
  - `MainToolbar` 新增 4 个 `let`（`canSetFill`、`activeFill`、`fillActive`、`setFill`）并在 body 加色点组。
  - `ContentView` 计算 `canSetFill` 与 fill 状态、调 `session.setFill`，传给 `MainToolbar`。

- [ ] **Step 1: 创建 `FillSwatches.swift`**

```swift
import SwiftUI

/// 工具条填色色点组：5 色 + 默认清除（斜线）。
struct FillSwatchesView: View {
    let canSetFill: Bool
    let activeFill: NodeFill?
    let fillActive: Bool
    let setFill: (NodeFill?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(NodeFill.allCases, id: \.self) { fill in
                swatchButton(
                    color: Color(nsColor: NodeFillStyle.swatch(fill)),
                    isActive: fillActive && activeFill == fill,
                    help: "填色 \(fill.rawValue)",
                    action: { setFill(fill) }
                )
            }
            // 默认清除点：圆形底 + 对角斜线（对齐原型 .swatch-none）
            swatchButton(
                color: Color(nsColor: .controlBackgroundColor),
                isActive: fillActive && activeFill == nil,
                help: "清除填色",
                action: { setFill(nil) }
            )
        }
    }

    private func swatchButton(
        color: Color,
        isActive: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                SlashLine()
                    .stroke(Color(red: 0.607, green: 0.239, blue: 0.180), lineWidth: 1.5)
                    .frame(width: 9, height: 9)
            }
            .frame(width: 16, height: 16)
            .overlay(
                Circle()
                    .stroke(
                        isActive ? Color.accentColor : Color.secondary.opacity(0.35),
                        lineWidth: isActive ? 2 : 1
                    )
                    .padding(-3)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSetFill)
        .help(help)
    }
}

/// 对角斜线（默认清除点用）。
private struct SlashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}
```

> 注意：默认清除点外圈仍画斜线，但仅当它是「默认」语义时（`fillActive && activeFill == nil`）斜线视觉才合理；为避免误读，可在有填色激活时给默认点也画斜线（斜线是「清除」标识，恒显示即可，见实现时的观感）。此处按「恒显示斜线」实现，手测确认。

- [ ] **Step 2: `MainToolbar.swift` 加参数与色点组**

在 `struct MainToolbar: ToolbarContent { ... }` 的属性区追加 4 个 `let`（放在 `fit` 闭包之后）：

```swift
    let canSetFill: Bool
    let activeFill: NodeFill?
    let fillActive: Bool
    let setFill: (NodeFill?) -> Void
```

在 body 的第一个 `ToolbarItemGroup(placement: .automatic) { ... }` 内、改侧按钮（`Button(action: setSideRight)` 块）之后、该 group 结束前，追加：

```swift
            Divider()
            FillSwatchesView(
                canSetFill: canSetFill,
                activeFill: activeFill,
                fillActive: fillActive,
                setFill: setFill
            )
```

- [ ] **Step 3: `ContentView.swift` 计算状态并接线**

在 `struct ContentView` 加计算属性（`canSetSide` 附近）：

```swift
    private var canSetFill: Bool { !session.selectedIds.isEmpty }

    /// 单选/全一致 → active=true，common 为公共 fill（含全 nil）；多选不一致或选中空 → active=false。
    private var fillSelection: (common: NodeFill?, active: Bool) {
        let ids = Array(session.selectedIds)
        guard !ids.isEmpty else { return (nil, false) }
        let first = session.model.node(id: ids[0])?.fill
        let allSame = ids.allSatisfy { session.model.node(id: $0)?.fill == first }
        return (first, allSame)
    }
```

在 `MainToolbar(...)` 调用处追加参数（在 `setSideRight: ...` 与 `zoomOut: ...` 之间加）：

```swift
                    canSetFill: canSetFill,
                    activeFill: fillSelection.common,
                    fillActive: fillSelection.active,
                    setFill: { fill in session.setFill(fill) },
```

- [ ] **Step 4: 编译**

Run: `xcodebuild build -scheme YMindApp -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/App/FillSwatches.swift YMindApp/YMindApp/App/MainToolbar.swift YMindApp/YMindApp/ContentView.swift
git commit -m "feat: 工具条填色色点组（5 色 + 默认清除）"
```

---

### Task 8: 手测验收 + 文档同步

**Files:**
- Modify: `docs/架构现状.md`（Node 字段表、NodeFrame 字段、版本号）
- Modify: `.agents/skills/ymind-codec-version/SKILL.md`（版本记录）、`.agents/skills/ymind-command/SKILL.md`（命令清单）
- 手测：运行 App 验证 PRD §5 验收表。

**Interfaces:**
- Consumes: Task 1–7 全部产出。
- Produces: 无新代码接口；文档与验收证据。

- [ ] **Step 1: 手测验收（对齐 PRD §5 表 1–6 与 FR-C4）**

Run: `xcodebuild build -scheme YMindApp -destination 'platform=macOS'` 后从 Xcode 运行 App，逐条验证：

| # | 场景 | 期望 |
|---|------|------|
| 1 | 单选点色 | 节点变色（浅底+边框），色点激活 |
| 2 | 多选点色 | 全部同色 |
| 3 | 点默认 | 恢复无填色 |
| 4 | 无选中 | 色点禁用 |
| 5 | 复制粘贴 | 副本保留填色 |
| 6 | 中心主题上色 | 深色变体、白字可读 |

另目测：选中描边、搜索高亮叠于填色之上；亮/暗外观切换后填色随动；缩放清晰不糊。

- [ ] **Step 2: 更新 `docs/架构现状.md`**

- §6 类图 `Node` 增 `+fill: NodeFill?`、`NodeFrame` 增 `+fill`；文件格式段注明 `currentVersion == 2`。
- §7.3「节点样式」标注已实现。
- 若新增了任何层间 import（本增量没有，NodeFillStyle 仅 AppKit 已在白名单），同步 §5 白名单——本增量无需改。

- [ ] **Step 3: 更新两个 ymind 技能**

- `.agents/skills/ymind-codec-version/SKILL.md`：`currentVersion` 相关处注明现为 2，迁移 v1→v2 已内置。
- `.agents/skills/ymind-command/SKILL.md`：命令清单追加 `setFill(ids:fill:)`。

- [ ] **Step 4: 全量测试 + Commit**

Run: `xcodebuild test -scheme YMindApp -destination 'platform=macOS'`
Expected: 全部 PASS。
Run: `scripts/check-boundaries.sh`
Expected: 通过。

```bash
git add docs/架构现状.md .agents/skills/ymind-codec-version/SKILL.md .agents/skills/ymind-command/SKILL.md
git commit -m "docs: 填色增量文档同步（架构现状 + 技能命令/版本清单）"
```

---

## Self-Review 记录

**1. Spec 覆盖核对：**
- §3.1 NodeFill token / lenient Codable → Task 1
- §4.1 v2 + v1→v2 迁移 → Task 2
- §5 setFill 命令一步 Undo / no-op 不入栈 / 不改选中 → Task 3
- §5.4 Session 门面 / §1.2 复制粘贴保留 → Task 4
- §6 NodeFrame.fill 传递（显式 init 默认 nil，零改动既有构造点）→ Task 5
- §3.2 系统语义色派生 / §7 填色绘制 / 文字色不变 / 无新 shader → Task 6
- §8 工具条色点组 / 激活态 / 无选中禁用 / ContentView 接线 → Task 7
- §10 手测验收 / §文档同步 → Task 8

**2. 占位符扫描：** 无 TBD/TODO/“写测试”等空泛步骤；所有代码步骤含完整可粘贴实现。

**3. 类型一致性：** `NodeFill`（Task 1 定义）在 Task 3/5/6/7 中签名一致；`setFill(ids:fill:)` 在 Task 3（Model/Command）与 Task 4（Session）参数与返回类型一致；`NodeFillStyle.swatch/background/border/rootBackground(_:)` 在 Task 6 定义、Task 7 消费一致；`NodeFrame.fill` 在 Task 5 定义、Task 6 消费一致；`MainToolbar` 四个新参数在 Task 7 Step 2/3 定义与调用一致。

## 修订记录

| 日期 | 说明 |
|------|------|
| 2026-09-27 | 初稿：基于 spec 2026-09-27 落盘；NodeFrame 显式 init 默认 nil 以兼容既有构造点 |
