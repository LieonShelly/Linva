# Linva v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 `LinvaApp` macOS 工程上实现可证伪的 v1 思维导图：树模型、命令 Undo、中心辐射布局、`.linva` 存盘、SwiftUI 壳 + Metal 画布（对齐原型交互）。

**Architecture:** 分层内核 + 薄壳。`MindMapModel` / `CommandBus` / `TextMeasure` / `RadialLayout` 无 UI；`DocumentSession` 管单文档文件；`CanvasMetalView` + `MetalRenderer` 只消费 `LayoutSnapshot`；SwiftUI 管工具条、菜单、编辑浮层。

**Tech Stack:** Swift 5、SwiftUI、AppKit（`NSOpenPanel` / `NSSavePanel` / 浮层输入）、MetalKit、Core Text、Swift Testing；工程路径 `LinvaApp/`（`PBXFileSystemSynchronizedRootGroup`，新文件放入目录即可被 Xcode 拾取）。

**Spec:** `docs/superpowers/specs/2026-09-24-linva-v1-architecture-design.md`  
**原型对照:** `prototype/app.js`（布局常量与算法）

## Global Constraints

- 平台：macOS（工程 `MACOSX_DEPLOYMENT_TARGET = 26.4`）
- 单窗口：`WindowGroup` + 自管一份文档；不做 `DocumentGroup`
- 文件：`.linva` = UTF-8 JSON，`version: 1`；存树 + `collapsed`；不存相机/选中
- 文案：允许多行；编辑态 ⌥Enter/⌘Enter 换行，Enter 提交
- 文字：Core Text 量字 + 纹理缓存；编辑用浮层，不做 Metal IME
- Undo：自研命令栈；⌘Z / ⇧⌘Z
- 一级 `side`：仅自动左右均衡；v1 不手动改侧
- 文档语言：仓库文档中文优先；代码标识符英文
- Model/Command **禁止** import SwiftUI / AppKit / Metal
- 测试命令默认：`xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' -only-testing:LinvaAppTests/<Suite>`

---

## File Structure

```text
LinvaApp/LinvaApp/
  Model/
    Side.swift
    Node.swift
    MindMapDocument.swift
    MindMapModel.swift
    LinvaCodec.swift
  Commands/
    MindMapCommand.swift
    CommandBus.swift
  Layout/
    LayoutConstants.swift
    NodeSize.swift
    TextMeasure.swift
    LayoutSnapshot.swift
    RadialLayout.swift
  Session/
    Camera.swift
    DocumentSession.swift
  Render/
    Shaders.metal
    TextAtlas.swift
    MetalRenderer.swift
    CanvasMetalView.swift
  App/
    ContentView.swift          # 改
    MainToolbar.swift
    NodeEditorOverlay.swift
    LinvaAppApp.swift          # 改：菜单、环境对象
  Resources/
    LinvaDocumentType.plist    # 或 Info 键：文档类型 UTType
  LinvaApp.entitlements        # 若需加 sandbox 文件权限，随工程已有文件调整

LinvaApp/LinvaAppTests/
  ModelTests.swift
  CommandBusTests.swift
  CodecTests.swift
  RadialLayoutTests.swift
  DocumentSessionTests.swift
```

删除或清空：`LinvaAppTests.swift` 中的占位 `example` 测试（Task 1 起替换）。

---

### Task 1: Model — Node / Document / MindMapModel

**Files:**
- Create: `LinvaApp/LinvaApp/Model/Side.swift`
- Create: `LinvaApp/LinvaApp/Model/Node.swift`
- Create: `LinvaApp/LinvaApp/Model/MindMapDocument.swift`
- Create: `LinvaApp/LinvaApp/Model/MindMapModel.swift`
- Create: `LinvaApp/LinvaAppTests/ModelTests.swift`
- Modify: `LinvaApp/LinvaAppTests/LinvaAppTests.swift`（删除占位或整文件删掉）

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum Side: String, Codable, Sendable { case left, right }`
  - `struct Node: Identifiable, Equatable, Codable, Sendable` — `id: UUID`, `text: String`, `collapsed: Bool`, `side: Side?`, `children: [Node]`
  - `struct MindMapDocument: Equatable, Codable, Sendable` — `version: Int`, `root: Node`；`static let currentVersion = 1`
  - `final class MindMapModel` — `var document: MindMapDocument`, `var selectedId: UUID`；`func node(id:) -> Node?`；`func parent(of:) -> (parent: Node, index: Int)?`（内部可变树 API 供 Command 使用，见下）
  - 可变 API（供 CommandBus，同文件 `extension MindMapModel`）：`mutating` 风格通过类方法：`func insertChild(parentId:text:side:at:) -> UUID`；`func insertSibling(of:text:) -> UUID?`；`func remove(id:) -> (parentId: UUID, index: Int, node: Node)?`；`func setText(id:_:)`；`func toggleCollapse(id:)`；`func select(_ id: UUID?)`；`static func makeNew() -> MindMapModel`

- [ ] **Step 1: 写失败测试 — 新建文档与侧分配查询**

```swift
import Testing
import Foundation
@testable import LinvaApp

@Suite("MindMapModel")
struct ModelTests {
    @Test func makeNew_hasSingleRootSelected() {
        let model = MindMapModel.makeNew()
        #expect(model.document.version == MindMapDocument.currentVersion)
        #expect(model.document.root.text == "中心主题")
        #expect(model.document.root.children.isEmpty)
        #expect(model.selectedId == model.document.root.id)
    }

    @Test func insertChild_onRoot_assignsBalancedSide() {
        let model = MindMapModel.makeNew()
        let rootId = model.document.root.id
        let a = model.insertChild(parentId: rootId, text: "A", side: nil, at: nil)
        let b = model.insertChild(parentId: rootId, text: "B", side: nil, at: nil)
        let c = model.insertChild(parentId: rootId, text: "C", side: nil, at: nil)
        let sides = model.document.root.children.map(\.side)
        #expect(sides == [.left, .right, .left] || sides == [.left, .right, .right])
        // 均衡：left 与 right 数量差 ≤ 1
        let left = sides.filter { $0 == .left }.count
        let right = sides.filter { $0 == .right }.count
        #expect(abs(left - right) <= 1)
        #expect(Set([a, b, c]).count == 3)
    }

    @Test func remove_selectsParent() {
        let model = MindMapModel.makeNew()
        let rootId = model.document.root.id
        let child = model.insertChild(parentId: rootId, text: "X", side: .right, at: nil)
        model.select(child)
        let removed = model.remove(id: child)
        #expect(removed != nil)
        #expect(model.selectedId == rootId)
        #expect(model.document.root.children.isEmpty)
    }

    @Test func remove_root_returnsNil() {
        let model = MindMapModel.makeNew()
        #expect(model.remove(id: model.document.root.id) == nil)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```bash
cd /Users/renjun.li/Desktop/Linva && xcodebuild test -project LinvaApp/LinvaApp.xcodeproj -scheme LinvaApp -destination 'platform=macOS' -only-testing:LinvaAppTests/ModelTests
```
Expected: FAIL（`MindMapModel` 未定义）

- [ ] **Step 3: 实现 Model 类型**

`Side.swift`:
```swift
import Foundation

enum Side: String, Codable, Sendable, Equatable {
    case left
    case right
}
```

`Node.swift`:
```swift
import Foundation

struct Node: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var text: String
    var collapsed: Bool
    var side: Side?
    var children: [Node]

    init(
        id: UUID = UUID(),
        text: String,
        collapsed: Bool = false,
        side: Side? = nil,
        children: [Node] = []
    ) {
        self.id = id
        self.text = text
        self.collapsed = collapsed
        self.side = side
        self.children = children
    }
}
```

`MindMapDocument.swift`:
```swift
import Foundation

struct MindMapDocument: Equatable, Codable, Sendable {
    static let currentVersion = 1
    var version: Int
    var root: Node

    static func blank(rootText: String = "中心主题") -> MindMapDocument {
        MindMapDocument(version: currentVersion, root: Node(text: rootText))
    }
}
```

`MindMapModel.swift`（核心逻辑；`nextSide` 对齐原型：`left <= right ? left : right`）:
```swift
import Foundation

final class MindMapModel {
    var document: MindMapDocument
    var selectedId: UUID

    init(document: MindMapDocument, selectedId: UUID? = nil) {
        self.document = document
        self.selectedId = selectedId ?? document.root.id
    }

    static func makeNew() -> MindMapModel {
        let doc = MindMapDocument.blank()
        return MindMapModel(document: doc, selectedId: doc.root.id)
    }

    func select(_ id: UUID?) {
        guard let id, node(id: id) != nil else {
            selectedId = document.root.id
            return
        }
        selectedId = id
    }

    func node(id: UUID) -> Node? {
        Self.find(id: id, in: document.root)
    }

    @discardableResult
    func insertChild(parentId: UUID, text: String, side: Side?, at index: Int?) -> UUID {
        let newId = UUID()
        var assignedSide = side
        if parentId == document.root.id, assignedSide == nil {
            assignedSide = nextSide()
        }
        if parentId != document.root.id {
            assignedSide = nil
        }
        let child = Node(id: newId, text: text, side: assignedSide)
        _ = mutate(id: parentId) { parent in
            let i = index ?? parent.children.count
            parent.children.insert(child, at: min(i, parent.children.count))
        }
        selectedId = newId
        return newId
    }

    @discardableResult
    func insertSibling(of id: UUID, text: String) -> UUID? {
        guard id != document.root.id,
              var path = pathTo(id),
              let parentId = path.parentId else { return nil }
        let side: Side? = parentId == document.root.id
            ? (node(id: id)?.side)
            : nil
        return insertChild(parentId: parentId, text: text, side: side, at: path.index + 1)
    }

    @discardableResult
    func remove(id: UUID) -> (parentId: UUID, index: Int, node: Node)? {
        guard id != document.root.id, let path = pathTo(id), let parentId = path.parentId else {
            return nil
        }
        var removed: Node?
        _ = mutate(id: parentId) { parent in
            removed = parent.children.remove(at: path.index)
        }
        guard let removed else { return nil }
        selectedId = parentId
        return (parentId, path.index, removed)
    }

    func setText(id: UUID, _ text: String) {
        _ = mutate(id: id) { $0.text = text }
    }

    func toggleCollapse(id: UUID) {
        _ = mutate(id: id) { $0.collapsed.toggle() }
    }

    func restoreChild(parentId: UUID, index: Int, node: Node) {
        _ = mutate(id: parentId) { parent in
            parent.children.insert(node, at: min(index, parent.children.count))
        }
    }

    // MARK: - Private tree helpers

    private func nextSide() -> Side {
        let left = document.root.children.filter { $0.side == .left }.count
        let right = document.root.children.filter { $0.side != .left }.count
        return left <= right ? .left : .right
    }

    private static func find(id: UUID, in node: Node) -> Node? {
        if node.id == id { return node }
        for c in node.children {
            if let f = find(id: id, in: c) { return f }
        }
        return nil
    }

    private struct Path { var parentId: UUID?; var index: Int }

    private func pathTo(_ id: UUID) -> Path? {
        if document.root.id == id { return Path(parentId: nil, index: 0) }
        return pathTo(id, parent: document.root)
    }

    private func pathTo(_ id: UUID, parent: Node) -> Path? {
        for (i, c) in parent.children.enumerated() {
            if c.id == id { return Path(parentId: parent.id, index: i) }
            if let p = pathTo(id, parent: c) { return p }
        }
        return nil
    }

    @discardableResult
    private func mutate(id: UUID, _ body: (inout Node) -> Void) -> Bool {
        var root = document.root
        let ok = Self.mutate(&root, id: id, body)
        if ok { document.root = root }
        return ok
    }

    private static func mutate(_ node: inout Node, id: UUID, _ body: (inout Node) -> Void) -> Bool {
        if node.id == id {
            body(&node)
            return true
        }
        for i in node.children.indices {
            if mutate(&node.children[i], id: id, body) { return true }
        }
        return false
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

同一 `xcodebuild test … ModelTests` 命令。Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Model LinvaApp/LinvaAppTests/ModelTests.swift
git add -u LinvaApp/LinvaAppTests/LinvaAppTests.swift
git commit -m "$(cat <<'EOF'
feat: 添加思维导图 Model 与树操作

含 Node/Document、均衡 side 分配与删除后选中父节点。
EOF
)"
```

---

### Task 2: CommandBus 与可逆命令

**Files:**
- Create: `LinvaApp/LinvaApp/Commands/MindMapCommand.swift`
- Create: `LinvaApp/LinvaApp/Commands/CommandBus.swift`
- Create: `LinvaApp/LinvaAppTests/CommandBusTests.swift`

**Interfaces:**
- Consumes: `MindMapModel`（Task 1）
- Produces:
  - `enum MindMapCommand` — `addChild(parentId:text:)` / `addSibling(selectedId:text:)` / `delete(id:)` / `setText(id:old:new:)` / `toggleCollapse(id:)`
  - `final class CommandBus` — `init(model: MindMapModel)`；`func execute(_:)`；`var canUndo/canRedo: Bool`；`func undo()`；`func redo()`；`func clearHistory()`；执行成功后可选 `onChange: (() -> Void)?`

- [ ] **Step 1: 写失败测试**

```swift
import Testing
import Foundation
@testable import LinvaApp

@Suite("CommandBus")
struct CommandBusTests {
    @Test func addChild_undo_redo() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        bus.execute(.addChild(parentId: model.document.root.id, text: "子"))
        #expect(model.document.root.children.count == 1)
        bus.undo()
        #expect(model.document.root.children.isEmpty)
        bus.redo()
        #expect(model.document.root.children.count == 1)
        #expect(model.document.root.children[0].text == "子")
    }

    @Test func setText_undo() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        let id = model.document.root.id
        bus.execute(.setText(id: id, old: "中心主题", new: "会议"))
        #expect(model.document.root.text == "会议")
        bus.undo()
        #expect(model.document.root.text == "中心主题")
    }

    @Test func delete_root_isNoOp() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        bus.execute(.delete(id: model.document.root.id))
        #expect(model.document.root.children.isEmpty)
        #expect(!bus.canUndo)
    }

    @Test func clearHistory_onDemand() {
        let model = MindMapModel.makeNew()
        let bus = CommandBus(model: model)
        bus.execute(.addChild(parentId: model.document.root.id, text: "A"))
        bus.clearHistory()
        #expect(!bus.canUndo)
        #expect(!bus.canRedo)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `… -only-testing:LinvaAppTests/CommandBusTests`  
Expected: FAIL

- [ ] **Step 3: 在 MindMapModel 上暴露路径查询，并实现命令与 Bus**

在 `MindMapModel` 增加（`pathTo` 保持可用）：

```swift
func parentId(of id: UUID) -> UUID? { pathTo(id)?.parentId }
func indexInParent(of id: UUID) -> Int? { pathTo(id)?.index }
```

`MindMapCommand.swift`:
```swift
import Foundation

enum MindMapCommand: Equatable {
    case addChild(parentId: UUID, text: String)
    case addSibling(selectedId: UUID, text: String)
    case delete(id: UUID)
    case setText(id: UUID, old: String, new: String)
    case toggleCollapse(id: UUID)
}
```

`CommandBus.swift`（redo 使用节点快照，UUID 稳定）：
```swift
import Foundation

final class CommandBus {
    private let model: MindMapModel
    private var undoStack: [Entry] = []
    private var redoStack: [Entry] = []
    var onChange: (() -> Void)?

    private struct Entry {
        let undo: () -> Void
        let redo: () -> Void
    }

    init(model: MindMapModel) { self.model = model }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    func execute(_ command: MindMapCommand) {
        guard let entry = applyForward(command) else { return }
        undoStack.append(entry)
        redoStack.removeAll()
        onChange?()
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }
        entry.undo()
        redoStack.append(entry)
        onChange?()
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        entry.redo()
        undoStack.append(entry)
        onChange?()
    }

    private func entryForInsertedNode(id: UUID) -> Entry? {
        guard let snapshot = model.node(id: id),
              let parentId = model.parentId(of: id),
              let index = model.indexInParent(of: id) else { return nil }
        return Entry(
            undo: { _ = self.model.remove(id: id) },
            redo: {
                self.model.restoreChild(parentId: parentId, index: index, node: snapshot)
                self.model.select(snapshot.id)
            }
        )
    }

    private func applyForward(_ command: MindMapCommand) -> Entry? {
        switch command {
        case let .addChild(parentId, text):
            let newId = model.insertChild(parentId: parentId, text: text, side: nil, at: nil)
            return entryForInsertedNode(id: newId)

        case let .addSibling(selectedId, text):
            guard let newId = model.insertSibling(of: selectedId, text: text) else { return nil }
            return entryForInsertedNode(id: newId)

        case let .delete(id):
            guard let removed = model.remove(id: id) else { return nil }
            return Entry(
                undo: {
                    self.model.restoreChild(
                        parentId: removed.parentId,
                        index: removed.index,
                        node: removed.node
                    )
                    self.model.select(removed.node.id)
                },
                redo: { _ = self.model.remove(id: id) }
            )

        case let .setText(id, old, new):
            model.setText(id: id, new)
            return Entry(
                undo: { self.model.setText(id: id, old) },
                redo: { self.model.setText(id: id, new) }
            )

        case let .toggleCollapse(id):
            model.toggleCollapse(id: id)
            return Entry(
                undo: { self.model.toggleCollapse(id: id) },
                redo: { self.model.toggleCollapse(id: id) }
            )
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Expected: PASS（含 undo/redo UUID 稳定）

- [ ] **Step 5: Commit**

```bash
git add LinvaApp/LinvaApp/Commands LinvaApp/LinvaApp/Model/MindMapModel.swift LinvaApp/LinvaAppTests/CommandBusTests.swift
git commit -m "$(cat <<'EOF'
feat: 添加 CommandBus 与可逆导图命令

覆盖增删改文案与折叠的 undo/redo。
EOF
)"
```

---

### Task 3: `.linva` JSON 编解码

**Files:**
- Create: `LinvaApp/LinvaApp/Model/LinvaCodec.swift`
- Create: `LinvaApp/LinvaAppTests/CodecTests.swift`

**Interfaces:**
- Consumes: `MindMapDocument`
- Produces:
  - `enum LinvaCodecError: Error` — `unsupportedVersion(Int)`, `decodingFailed`
  - `enum LinvaCodec` — `static func encode(_ doc: MindMapDocument) throws -> Data`；`static func decode(_ data: Data) throws -> MindMapDocument`（未知 version 抛错；深层 `side` 在 decode 后 `sanitize` 清掉并可选 `warnings: inout [String]`）

- [ ] **Step 1: 写失败测试**

```swift
import Testing
import Foundation
@testable import LinvaApp

@Suite("LinvaCodec")
struct CodecTests {
    @Test func roundTrip() throws {
        let model = MindMapModel.makeNew()
        _ = model.insertChild(parentId: model.document.root.id, text: "左", side: .left, at: nil)
        model.document.root.children[0].collapsed = true
        let data = try LinvaCodec.encode(model.document)
        let decoded = try LinvaCodec.decode(data)
        #expect(decoded == model.document)
    }

    @Test func rejectsUnknownVersion() throws {
        let json = """
        {"version":99,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"x","collapsed":false,"children":[]}}
        """.data(using: .utf8)!
        #expect(throws: LinvaCodecError.self) {
            _ = try LinvaCodec.decode(json)
        }
    }

    @Test func stripsDeepSide() throws {
        let json = """
        {"version":1,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"根","collapsed":false,"children":[{"id":"00000000-0000-0000-0000-000000000002","text":"一","collapsed":false,"side":"left","children":[{"id":"00000000-0000-0000-0000-000000000003","text":"二","collapsed":false,"side":"right","children":[]}]}]}}
        """.data(using: .utf8)!
        let doc = try LinvaCodec.decode(json)
        #expect(doc.root.children[0].side == .left)
        #expect(doc.root.children[0].children[0].side == nil)
    }
}
```

- [ ] **Step 2: 跑测试确认失败** → Expected: FAIL

- [ ] **Step 3: 实现 Codec**

```swift
import Foundation

enum LinvaCodecError: Error, Equatable {
    case unsupportedVersion(Int)
    case decodingFailed
}

enum LinvaCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    static func encode(_ document: MindMapDocument) throws -> Data {
        try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> MindMapDocument {
        let doc: MindMapDocument
        do {
            doc = try decoder.decode(MindMapDocument.self, from: data)
        } catch {
            throw LinvaCodecError.decodingFailed
        }
        guard doc.version == MindMapDocument.currentVersion else {
            throw LinvaCodecError.unsupportedVersion(doc.version)
        }
        return sanitize(doc)
    }

    private static func sanitize(_ document: MindMapDocument) -> MindMapDocument {
        var root = document.root
        root.side = nil
        root.children = root.children.map { child in
            var c = child
            // keep side on first level only
            c.children = stripSide(c.children)
            return c
        }
        return MindMapDocument(version: document.version, root: root)
    }

    private static func stripSide(_ nodes: [Node]) -> [Node] {
        nodes.map { n in
            var x = n
            x.side = nil
            x.children = stripSide(x.children)
            return x
        }
    }
}
```

注意：测试 JSON 里的 UUID 字符串需与 `UUID` 的 `Codable` 格式一致（系统默认无连字符时可能失败）。若 decode 失败，改为在测试里用 `MindMapModel` 构造再 `encode` 出「深层带 side」的 Data，手动改 JSON 插入 `"side":"right"` 到孙节点后再 decode。

- [ ] **Step 4: 测试通过**

- [ ] **Step 5: Commit** — `feat: 添加 .linva JSON 编解码与版本校验`

---

### Task 4: TextMeasure + RadialLayout

**Files:**
- Create: `LinvaApp/LinvaApp/Layout/LayoutConstants.swift`
- Create: `LinvaApp/LinvaApp/Layout/NodeSize.swift`
- Create: `LinvaApp/LinvaApp/Layout/TextMeasure.swift`
- Create: `LinvaApp/LinvaApp/Layout/LayoutSnapshot.swift`
- Create: `LinvaApp/LinvaApp/Layout/RadialLayout.swift`
- Create: `LinvaApp/LinvaAppTests/RadialLayoutTests.swift`

**Interfaces:**
- Consumes: `Node` / `MindMapDocument`
- Produces:
  - `enum LayoutConstants` — `hGap=56`, `vGap=16`, `rootPadX/Y`, `nodePadX/Y`（对齐 `prototype/app.js`）
  - `struct NodeSize: Equatable` — `width: CGFloat`, `height: CGFloat`
  - `struct TextMeasure` — `func size(for node: Node, isRoot: Bool) -> NodeSize`（Core Text；系统字体即可，不强制 Fraunces）
  - `struct NodeFrame: Equatable` — `id`, `center: CGPoint`, `size: NodeSize`, `isRoot`, `side: Side?`, `collapsed`, `hiddenCount: Int`；计算属性 `var rect: CGRect`（中心锚点）
  - `struct EdgeGeometry: Equatable` — `fromId`, `toId`, `side: Side`, `points` 或起终控制点
  - `struct LayoutSnapshot: Equatable` — `frames: [UUID: NodeFrame]`, `edges: [EdgeGeometry]`
  - `enum RadialLayout` — `static func layout(document:measure:) -> LayoutSnapshot`

布局语义：根在 `(0,0)` 中心；左右分侧；折叠子树不占位；常量与 `prototype/app.js` 的 `layoutTree` / `placeBranch` / `placeSide` 一致。

- [ ] **Step 1: 写失败测试 — 单根与左右一级**

```swift
import Testing
import Foundation
import CoreGraphics
@testable import LinvaApp

@Suite("RadialLayout")
struct RadialLayoutTests {
    @Test func singleRoot_centeredAtOrigin() {
        let doc = MindMapDocument.blank()
        let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
        let root = snap.frames[doc.root.id]!
        #expect(root.center == .zero)
        #expect(snap.edges.isEmpty)
    }

    @Test func leftAndRight_childrenOppositeX() {
        var doc = MindMapDocument.blank()
        let left = Node(text: "L", side: .left)
        let right = Node(text: "R", side: .right)
        doc.root.children = [left, right]
        let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
        let lf = snap.frames[left.id]!
        let rf = snap.frames[right.id]!
        #expect(lf.center.x < 0)
        #expect(rf.center.x > 0)
        #expect(snap.edges.count == 2)
    }

    @Test func collapsed_hidesDescendants() {
        var doc = MindMapDocument.blank()
        let grand = Node(text: "孙")
        var child = Node(text: "子", side: .right, collapsed: true, children: [grand])
        doc.root.children = [child]
        let snap = RadialLayout.layout(document: doc, measure: TextMeasure())
        #expect(snap.frames[grand.id] == nil)
        #expect(snap.frames[child.id]?.hiddenCount == 1)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

- [ ] **Step 3: 实现 Layout（移植原型算法）**

`LayoutConstants.swift`:
```swift
import CoreGraphics

enum LayoutConstants {
    static let hGap: CGFloat = 56
    static let vGap: CGFloat = 16
    static let rootPadX: CGFloat = 22
    static let rootPadY: CGFloat = 16
    static let nodePadX: CGFloat = 16
    static let nodePadY: CGFloat = 10
    static let rootMaxTextWidth: CGFloat = 220
    static let nodeMaxTextWidth: CGFloat = 188
    static let rootLineHeight: CGFloat = 24
    static let nodeLineHeight: CGFloat = 20
}
```

`TextMeasure.swift`：用 `NSAttributedString` / `CTFramesetter` 或按字符累加 `CTLine` 宽度，逻辑对齐原型按字折行（`maxW`）。macOS 可 `import AppKit` **仅在 Layout 层**（规格允许 Core Text；若需 `NSFont`，Layout 可依赖 AppKit，仍禁止 SwiftUI/Metal）。

`RadialLayout.swift`：按 `prototype/app.js` 的 `subtreeHeight` → `placeSide` → `placeBranch` 逐行移植；`countDescendants` 同步实现。

- [ ] **Step 4: 测试通过**

- [ ] **Step 5: Commit** — `feat: 添加中心辐射布局与文字测量`

---

### Task 5: DocumentSession（新建 / 打开 / 保存）

**Files:**
- Create: `LinvaApp/LinvaApp/Session/Camera.swift`
- Create: `LinvaApp/LinvaApp/Session/DocumentSession.swift`
- Create: `LinvaApp/LinvaAppTests/DocumentSessionTests.swift`
- Modify: 稍后 Task 7 接 UI；本任务单测纯逻辑

**Interfaces:**
- Consumes: `MindMapModel`, `CommandBus`, `LinvaCodec`, `RadialLayout`, `TextMeasure`
- Produces:
  - `struct Camera: Equatable` — `translation: CGPoint`, `scale: CGFloat`（默认 `1`）；`func fit(contentBounds:viewport:)` 
  - `final class DocumentSession: ObservableObject`（或 `@Observable`）—
    - `model`, `commandBus`, `fileURL: URL?`, `isDirty: Bool`, `camera`, `snapshot: LayoutSnapshot`, `errorMessage: String?`
    - `func newDocument()` / `func load(from: URL) throws` / `func save() throws` / `func saveAs(to: URL) throws`
    - `func markDirtyAndRelayout()`；`func clearError()`
    - 打开/新建前：若 `isDirty`，由 UI 弹确认（Session 提供 `func prepareReplace() -> Bool` 表示「调用方已确认可丢弃」）
    - `load`/`new` 时 `commandBus.clearHistory()`；`isDirty = false`；相机重置为默认（不从文件读）

- [ ] **Step 1: 写失败测试 — 保存再加载**

```swift
import Testing
import Foundation
@testable import LinvaApp

@Suite("DocumentSession")
struct DocumentSessionTests {
    @Test func saveAndLoad_roundTrip() throws {
        let session = DocumentSession()
        let rootId = session.model.document.root.id
        session.commandBus.execute(.addChild(parentId: rootId, text: "议题"))
        session.isDirty = true
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linva-test-\(UUID().uuidString).linva")
        try session.saveAs(to: url)
        #expect(session.isDirty == false)
        #expect(session.fileURL == url)

        let session2 = DocumentSession()
        try session2.load(from: url)
        #expect(session2.model.document.root.children.count == 1)
        #expect(session2.model.document.root.children[0].text == "议题")
        #expect(session2.isDirty == false)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func load_unsupportedVersion_leavesDocument() throws {
        let session = DocumentSession()
        let originalRoot = session.model.document.root.id
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("linva-bad-\(UUID().uuidString).linva")
        try Data("{\"version\":9,\"root\":{\"id\":\"\(UUID())\",\"text\":\"x\",\"collapsed\":false,\"children\":[]}}".utf8)
            .write(to: url)
        #expect(throws: LinvaCodecError.self) {
            try session.load(from: url)
        }
        #expect(session.model.document.root.id == originalRoot)
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 2: 失败确认 → Step 3 实现 Session + Camera → Step 4 通过 → Step 5 Commit**

`saveAs` 伪码：
```swift
func saveAs(to url: URL) throws {
    let data = try LinvaCodec.encode(model.document)
    try data.write(to: url, options: .atomic)
    fileURL = url
    isDirty = false
}

func load(from url: URL) throws {
    let data = try Data(contentsOf: url)
    let doc = try LinvaCodec.decode(data)
    model.document = doc
    model.selectedId = doc.root.id
    commandBus.clearHistory()
    fileURL = url
    isDirty = false
    camera = Camera()
    relayout()
}

func relayout() {
    snapshot = RadialLayout.layout(document: model.document, measure: measure)
}
```

Commit: `feat: 添加 DocumentSession 与相机状态`

---

### Task 6: Metal 画布通路（线 / 框 / 文字纹理 + 相机）

**Files:**
- Create: `LinvaApp/LinvaApp/Render/Shaders.metal`
- Create: `LinvaApp/LinvaApp/Render/TextAtlas.swift`
- Create: `LinvaApp/LinvaApp/Render/MetalRenderer.swift`
- Create: `LinvaApp/LinvaApp/Render/CanvasMetalView.swift`

**Interfaces:**
- Consumes: `LayoutSnapshot`, `Camera`, `selectedId`
- Produces:
  - `final class MetalRenderer` — `init(device:)`；`func draw(in view: MTKView, snapshot:camera:selectedId:)`
  - `final class TextAtlas` — `func texture(for frame:text:scale:device:) -> MTLTexture?`；脏键失效
  - `struct CanvasMetalView: NSViewRepresentable` — 绑定 `DocumentSession`，每帧/变更 `setNeedsDisplay`
  - Shader：正交 2D；顶点色块画节点底与选中描边；边用线段或三角带；文字 textured quad

**测试：** 本任务以**编译 + 手测**为主（清屏非黑死、能见色块）。可选：抽 `Camera` 坐标变换写单测：

```swift
@Test func camera_worldToScreen_roundTrip() {
    var cam = Camera(translation: CGPoint(x: 10, y: 20), scale: 2)
    let world = CGPoint(x: 5, y: 5)
    let screen = cam.worldToScreen(world)
    #expect(cam.screenToWorld(screen).x == world.x)
}
```

把变换方法放在 `Camera.swift`。

- [ ] **Step 1: 给 Camera 加坐标 API + 单测（可放 `DocumentSessionTests` 或新 `CameraTests.swift`）**
- [ ] **Step 2: 实现 `Shaders.metal` + `MetalRenderer` 最小清屏与画矩形**
- [ ] **Step 3: `TextAtlas` — CGBitmap → `MTLTexture`，按节点贴字**
- [ ] **Step 4: `CanvasMetalView` 嵌入临时 `ContentView`，Run App 手测：默认中心主题可见**
- [ ] **Step 5: Commit** — `feat: 添加 Metal 画布渲染与文字纹理缓存`

`CanvasMetalView` 要点：
```swift
final class CanvasMTKView: MTKView {
    var session: DocumentSession!
    // mouseDragged → 改 camera.translation（不入命令栈）
    // scrollWheel → 以指针为锚缩放
}

struct CanvasMetalView: NSViewRepresentable {
    @ObservedObject var session: DocumentSession
    func makeNSView(context: Context) -> CanvasMTKView { /* device, renderer, delegate */ }
    func updateNSView(_ view: CanvasMTKView, context: Context) { view.session = session; view.setNeedsDisplay(view.bounds) }
}
```

Metal 设备失败：`makeNSView` 若 `MTLCreateSystemDefaultDevice() == nil`，Session `errorMessage = "无法初始化 Metal"`，UI 显示告警。

---

### Task 7: 命中、选中、编辑浮层、工具条与快捷键

**Files:**
- Create: `LinvaApp/LinvaApp/App/MainToolbar.swift`
- Create: `LinvaApp/LinvaApp/App/NodeEditorOverlay.swift`
- Modify: `LinvaApp/LinvaApp/ContentView.swift`
- Modify: `LinvaApp/LinvaApp/Render/CanvasMetalView.swift`（点击命中）
- Modify: `LinvaApp/LinvaApp/LinvaAppApp.swift`（`.commands` 菜单可放到 Task 8；本任务先工具条 + 本地快捷键）

**Interfaces:**
- Consumes: `DocumentSession`, `CommandBus`, `LayoutSnapshot`, `Camera`
- Produces: 完整交互闭环（FR-2～9、FR-12～14 的 UI 侧）

行为清单：
| 操作 | 实现 |
|------|------|
| 单击节点 | `hitTest` → `model.select` |
| 点空白 | 选中取消→回到根或保持「无操作焦点」：规格为取消选中；实现为 `selectedId = root` 亦可，与原型对齐：原型点空白取消；采用 `selectedId` 仍指向原节点但「无高亮」更复杂 — **对齐原型：点空白不强制改 selected，工具条禁用**；简化：**点空白将 selected 置为 root 且不显示选中描边若 hit 空白**。采用：`selection = hit ?? nil`，`nil` 时工具条禁用增删；渲染无选中描边 |
| 双击 | `editingId = id`，浮层 `TextEditor`/`NSTextView` |
| 编辑提交 | Enter → `setText` 命令；⌥Enter/⌘Enter 插入 `\n` |
| Tab | `addChild` |
| Enter（非编辑） | `addSibling`（根禁用） |
| ⌫ | `delete`（根禁用） |
| 工具条缩放/适应 | 改 `camera`；适应用 snapshot 所有 frame 的 bounds |

- [ ] **Step 1: 实现 `hitTest(screen:snapshot:camera) -> UUID?`（可放 `Camera` 或 `CanvasMetalView` 旁纯函数）+ 单测**
- [ ] **Step 2: 接线鼠标与快捷键到 `CommandBus`**
- [ ] **Step 3: `NodeEditorOverlay` 定位到节点屏幕 rect**
- [ ] **Step 4: `MainToolbar` 绑定启用态**
- [ ] **Step 5: Run App 手测 UJ-1 路径（建树、折叠、缩放）**
- [ ] **Step 6: Commit** — `feat: 画布命中、编辑浮层与工具条快捷键`

命中函数：
```swift
func hitTest(screenPoint: CGPoint, snapshot: LayoutSnapshot, camera: Camera) -> UUID? {
    let world = camera.screenToWorld(screenPoint)
    // 从上到下：后绘制的优先；遍历 frames，含 world 点的 rect 中取面积最小者或任意命中
    return snapshot.frames.values
        .filter { $0.rect.contains(world) }
        .min(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height })?
        .id
}
```

---

### Task 8: 菜单、Undo、文档类型、脏标记与关闭确认

**Files:**
- Modify: `LinvaApp/LinvaApp/LinvaAppApp.swift`
- Modify: `LinvaApp/LinvaApp/Session/DocumentSession.swift`（`windowTitle`）
- Modify: `LinvaApp/LinvaApp.xcodeproj` 的 target Info（文档类型）— 因同步根组，可用 `LinvaApp/Info.plist` + Build Settings `INFOPLIST_FILE`，或 `GENERATE_INFOPLIST_FILE` 的 `INFOPLIST_KEY_CFBundleDocumentTypes`

**Interfaces:**
- 菜单：新建 / 打开 / 保存 / 另存为；撤销 / 重做
- 未保存：`NSAlert` 三按钮
- 标题：`文件名` 或 `未命名` + dirty 时 `•`
- 注册：`public.linva` 或 `com.linva.document`，扩展名 `linva`，角色 Editor
- 命令执行后 `isDirty = true`（load/save/new 除外）

- [ ] **Step 1: 所有 `commandBus.execute` / 成功改树路径设置 `isDirty = true`（可在 `CommandBus.onChange` 里由 Session 设置）**
- [ ] **Step 2: 实现文件菜单 + `NSOpenPanel`/`NSSavePanel`（allowedContentTypes）**
- [ ] **Step 3: 撤销重做菜单绑定 `bus.undo/redo`，快捷键 ⌘Z / ⇧⌘Z**
- [ ] **Step 4: 关闭窗口 / 新建 / 打开前 dirty 确认**
- [ ] **Step 5: 配置文档 UTType（`UTType(filenameExtension: "linva")` 导入声明）**
- [ ] **Step 6: 手测：保存→退出→打开；误删后 ⌘Z**
- [ ] **Step 7: Commit** — `feat: 文件菜单、Undo 与 .linva 文档类型`

打开面板示例：
```swift
let panel = NSOpenPanel()
panel.allowedContentTypes = [UTType(filenameExtension: "linva")!]
panel.begin { resp in
    guard resp == .OK, let url = panel.url else { return }
    try? session.load(from: url)
}
```

---

## Self-Review

| Spec 项 | 对应 Task |
|---------|-----------|
| Model / side / 树 | T1 |
| CommandBus Undo | T2、T8 |
| `.linva` codec / version | T3、T5 |
| Layout + measure | T4 |
| DocumentSession 单文档 | T5、T8 |
| Metal + TextAtlas | T6 |
| 命中/编辑/工具条/快捷键 | T7 |
| 菜单/脏/文档类型 | T8 |
| 不做：DocumentGroup、手动改侧、PNG、VoiceOver 深通达 | 无任务（正确） |

已消除模糊点：`addChild`/`addSibling` 统一 snapshot 可逆；Codec 深层 `side` 测试构造方式已说明；点空白选中采用 hit 语义（未命中则无选中描边 / 工具条按 `selectedId == nil` 或约定处理，Task 7 表内已写明）。

---

## 执行方式

计划完成后由用户选择：

1. **Subagent-Driven（推荐）** — 每任务新子代理 + 任务间审查  
2. **Inline Execution** — 本会话按 `executing-plans` 批量执行并设检查点
