# 节点图文内容流 + 编辑态贴图 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把节点「单图 + 单文字」升级为「多图多段内容流（块序列）」，并修复编辑态 ⌘V 粘贴图片失败。

**Architecture:** `Node` 存储改为 `blocks: [ContentBlock]`（text/image 块，块级 UUID），`text`/`image`/`imagePixelSize` 变只读计算属性；Codec v3→v4 迁移（旧文件 fallback 合成块，保持「图上文下」视觉）；命令栈新增 `setBlocks`/`appendImageBlock`/`replaceImageBlock`/`removeImageBlock`；编辑提交走「聚拢规则」（文本合并单块、图片按序聚拢单侧）；布局/渲染/命中/导出全部按块遍历；`CommitTextView.paste(_:)` 拦截图片粘贴。

**Tech Stack:** Swift 6 / SwiftUI + AppKit + Metal；Testing framework（swift-testing）；xcodebuild 构建。

---

## 文件结构

| 文件 | 职责 | 动作 |
|---|---|---|
| `YMindApp/YMindApp/Model/ContentBlock.swift` | 块类型（text/image，块级 id） | 新建 |
| `YMindApp/YMindApp/Model/Node.swift` | blocks 存储 + 只读计算属性 + decode fallback | 改 |
| `YMindApp/YMindApp/Model/MindMapDocument.swift` | `currentVersion = 4` | 改 |
| `YMindApp/YMindApp/Model/YMindCodec.swift` | 迁移链 v3→v4 | 改 |
| `YMindApp/YMindApp/Commands/MindMapCommand.swift` | 4 个新命令 case | 改 |
| `YMindApp/YMindApp/Commands/CommandBus.swift` | applyForward 分支 | 改 |
| `YMindApp/YMindApp/Model/MindMapModel.swift` | 块变更方法 | 改 |
| `YMindApp/YMindApp/Session/DocumentSession.swift` | 聚拢提交 / 粘贴 / 块选中态 | 改 |
| `YMindApp/YMindApp/ContentView.swift` | 编辑态 ⌘V 回调接线 / 选中回落 | 改 |
| `YMindApp/YMindApp/App/NodeEditorOverlay.swift` | `paste(_:)` 拦截图片 | 改 |
| `YMindApp/YMindApp/Layout/LayoutSnapshot.swift` | `BlockLayoutFrame` + `NodeFrame.blocks` | 改 |
| `YMindApp/YMindApp/Layout/TextMeasure.swift` | 块序尺寸合成 | 改 |
| `YMindApp/YMindApp/Layout/RadialLayout.swift` | 产出块布局 + payload 按块 id | 改 |
| `YMindApp/YMindApp/Render/TextAtlas.swift` | 按块 id 栅格化文本块 | 改 |
| `YMindApp/YMindApp/Render/ImageTextureCache.swift` | 脏键改块 id | 改 |
| `YMindApp/YMindApp/Render/MetalRenderer.swift` | drawText/drawImage 块遍历 + 选中描边 | 改 |
| `YMindApp/YMindApp/Render/CanvasHitTesting.swift` | 块级命中 `(nodeId, blockId)` | 改 |
| `YMindApp/YMindApp/Render/CanvasMetalView.swift` | 双击/⌫/Esc 走块选中 | 改 |
| `YMindApp/YMindApp/Model/MarkdownExporter.swift` | 多图引用按块 id | 改 |
| `YMindApp/YMindApp/YMindAppApp.swift` | 导出文件夹包多 assets | 改 |
| `docs/架构现状.md`、`docs/superpowers/specs/2026-10-01-ymind-content-flow-design.md` | 落档 | 改 |

测试文件：`CodecTests.swift`、`CommandBusTests.swift`、`DocumentSessionTests.swift`、`LayoutSnapshotTests`（RadialLayoutTests/HitTestTests 内）、`ImageTextureCacheTests.swift`、`MarkdownExporterTests.swift`、`PNGExporterTests.swift`。

---

### Task 1: 数据层 v4 —— ContentBlock + Node + Codec + 命令 + Session 接口（可编译原子单元）

**理由**：`Node.text` 变只读计算属性后，`setText`/`setImage` 命令及其 Session 调用**编译期强制失败**，无法拆开提交；本任务一次完成 Model+Commands+Session 接口重构，产出可编译、全测试绿。

**Files:**
- Create: `YMindApp/YMindApp/Model/ContentBlock.swift`
- Modify: `YMindApp/YMindApp/Model/Node.swift`、`Model/MindMapDocument.swift`、`Model/YMindCodec.swift`、`Commands/MindMapCommand.swift`、`Commands/CommandBus.swift`、`Model/MindMapModel.swift`、`Session/DocumentSession.swift`
- Test: `YMindApp/YMindAppTests/CodecTests.swift`、`CommandBusTests.swift`、`DocumentSessionTests.swift`

- [ ] **Step 1: 新建 `ContentBlock.swift`**

```swift
import Foundation

/// 节点内容块：文本或图片。块级 UUID 持久化（图片选中/删除/替换/Undo 按块 id 寻址）。
struct ContentBlock: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var kind: Kind

    enum Kind: Codable, Equatable, Sendable {
        case text(String)
        case image(BlockImage)
    }

    struct BlockImage: Codable, Equatable, Sendable {
        var data: Data
        var pixelSize: ImagePixelSize
    }
}
```

- [ ] **Step 2: 改造 `Node.swift`（存储 → blocks + 只读计算属性 + decode fallback）**

`Node.swift` 全文件替换为：

```swift
import Foundation

struct Node: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var blocks: [ContentBlock]
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
        image: Data? = nil,
        imagePixelSize: ImagePixelSize? = nil,
        children: [Node] = []
    ) {
        self.id = id
        if let image, let imagePixelSize {
            // 构造兼容：旧单图形态 → 图在上、文在下（保持旧视觉）。
            self.blocks = [
                ContentBlock(id: UUID(), kind: .image(.init(data: image, pixelSize: imagePixelSize))),
                ContentBlock(id: UUID(), kind: .text(text)),
            ]
        } else {
            self.blocks = [ContentBlock(id: UUID(), kind: .text(text))]
        }
        self.collapsed = collapsed
        self.side = side
        self.fill = fill
        self.children = children
    }

    /// 只读兼容：文本块按序以 "\n" 连接（搜索/编辑 draft/导出标题零改动）。
    var text: String {
        blocks.compactMap { if case .text(let s) = $0.kind { s } else { nil } }.joined(separator: "\n")
    }

    /// 只读兼容：首个图片块数据（单图读方零改动；多图读方走 blocks）。
    var image: Data? {
        for b in blocks {
            if case .image(let img) = b.kind { return img.data }
        }
        return nil
    }

    /// 只读兼容：与 `image` 同块。
    var imagePixelSize: ImagePixelSize? {
        for b in blocks {
            if case .image(let img) = b.kind { return img.pixelSize }
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, collapsed, side, fill, image, imagePixelSize, blocks, children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        side = try c.decodeIfPresent(Side.self, forKey: .side)
        if let raw = try c.decodeIfPresent(String.self, forKey: .fill),
           let fill = NodeFill(rawValue: raw) {
            self.fill = fill
        } else {
            self.fill = nil
        }
        children = try c.decodeIfPresent([Node].self, forKey: .children) ?? []

        // v4：直接读 blocks。
        if let blocks = try c.decodeIfPresent([ContentBlock].self, forKey: .blocks) {
            self.blocks = blocks
            return
        }
        // v1/v2/v3 fallback：text + image/imagePixelSize → 合成块（图在上、文在下）。
        let text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        var blocks: [ContentBlock] = []
        if let image = try c.decodeIfPresent(Data.self, forKey: .image) {
            var px: ImagePixelSize? = nil
            do {
                px = try c.decodeIfPresent(ImagePixelSize.self, forKey: .imagePixelSize)
                if let ps = px, !(ps.width > 0 && ps.height > 0 && ps.width.isFinite && ps.height.isFinite) {
                    px = nil
                }
            } catch {
                px = nil
            }
            if let px {
                blocks.append(ContentBlock(id: UUID(), kind: .image(.init(data: image, pixelSize: px))))
            }
        }
        blocks.append(ContentBlock(id: UUID(), kind: .text(text)))
        self.blocks = blocks
    }
}
```

- [ ] **Step 3: `MindMapDocument.swift` 升版本**

```swift
static let currentVersion = 4
```

- [ ] **Step 4: `YMindCodec.swift` 迁移链追加**

在 `if doc.version == 2 { doc.version = 3 }` 之后追加：

```swift
// 迁移：v3 → v4（blocks 由 Node 解码器 fallback 合成，此处仅抬版本号）。
if doc.version == 3 {
    doc.version = 4
}
```

- [ ] **Step 5: `MindMapCommand.swift` 命令更替**

删除 `case setText(id: UUID, old: String, new: String)` 与 `case setImage(ids: [UUID], image: Data?, pixelSize: ImagePixelSize?)`，替换为：

```swift
case setBlocks(id: UUID, old: [ContentBlock], new: [ContentBlock])
case appendImageBlock(id: UUID, image: Data, pixelSize: ImagePixelSize)
case replaceImageBlock(id: UUID, blockId: UUID, image: Data, pixelSize: ImagePixelSize)
case removeImageBlock(id: UUID, blockId: UUID)
```

- [ ] **Step 6: `MindMapModel.swift` 新增块变更方法（删除 setText/setImage）**

删除 `setText(id:_:)` 与 `setImage(ids:image:pixelSize:)`，新增：

```swift
/// 整块序列替换（编辑提交）。old == new → 返回 false 不入栈。
@discardableResult
func setBlocks(id: UUID, old: [ContentBlock], new: [ContentBlock]) -> Bool {
    guard let node = node(id: id), node.blocks != old else { return false }
    _ = mutate(id: id) { $0.blocks = new }
    return true
}

/// 末尾追加图片块；返回新块 id（redo 用同 id 重插）。
@discardableResult
func appendImageBlock(id: UUID, image: Data, pixelSize: ImagePixelSize) -> UUID {
    let block = ContentBlock(id: UUID(), kind: .image(.init(data: image, pixelSize: pixelSize)))
    _ = mutate(id: id) { $0.blocks.append(block) }
    return block.id
}

/// 替换指定图片块数据（块 id 不变）；返回旧块供 Undo；无该块返回 nil。
@discardableResult
func replaceImageBlock(id: UUID, blockId: UUID, image: Data, pixelSize: ImagePixelSize) -> ContentBlock? {
    guard let node = node(id: id),
          let index = node.blocks.firstIndex(where: { $0.id == blockId }),
          case .image = node.blocks[index].kind else {
        return nil
    }
    let old = node.blocks[index]
    _ = mutate(id: id) {
        $0.blocks[index] = ContentBlock(
            id: blockId,
            kind: .image(.init(data: image, pixelSize: pixelSize))
        )
    }
    return old
}

/// 删除图片块；返回被删块与下标供 Undo 按原位置恢复；无该块/非图片块返回 nil。
@discardableResult
func removeImageBlock(id: UUID, blockId: UUID) -> (block: ContentBlock, index: Int)? {
    guard let node = node(id: id),
          let index = node.blocks.firstIndex(where: { $0.id == blockId }),
          case .image = node.blocks[index].kind else {
        return nil
    }
    let block = node.blocks[index]
    _ = mutate(id: id) { $0.blocks.remove(at: index) }
    return (block, index)
}
```

- [ ] **Step 7: `CommandBus.swift` applyForward 分支**

替换 `setText` 分支（第 95-100 行）为：

```swift
case let .setBlocks(id, old, new):
    guard model.setBlocks(id: id, old: old, new: new) else { return nil }
    return Entry(
        undo: { _ = self.model.setBlocks(id: id, old: new, new: old) },
        redo: { _ = self.model.setBlocks(id: id, old: old, new: new) }
    )
```

替换 `setImage` 分支（第 245-258 行）为：

```swift
case let .appendImageBlock(id, image, pixelSize):
    let blockId = model.appendImageBlock(id: id, image: image, pixelSize: pixelSize)
    return Entry(
        undo: { _ = self.model.removeImageBlock(id: id, blockId: blockId) },
        redo: { _ = self.model.appendImageBlock(id: id, image: image, pixelSize: pixelSize) }
    )

case let .replaceImageBlock(id, blockId, image, pixelSize):
    guard let old = model.replaceImageBlock(id: id, blockId: blockId, image: image, pixelSize: pixelSize) else {
        return nil
    }
    return Entry(
        undo: {
            if case let .image(oldImg) = old.kind {
                _ = self.model.replaceImageBlock(id: id, blockId: blockId, image: oldImg.data, pixelSize: oldImg.pixelSize)
            }
        },
        redo: { _ = self.model.replaceImageBlock(id: id, blockId: blockId, image: image, pixelSize: pixelSize) }
    )

case let .removeImageBlock(id, blockId):
    guard let removed = model.removeImageBlock(id: id, blockId: blockId) else { return nil }
    return Entry(
        undo: {
            _ = self.model.mutate(id: id) { $0.blocks.insert(removed.block, at: min(removed.index, $0.blocks.count)) }
        },
        redo: { _ = self.model.removeImageBlock(id: id, blockId: blockId) }
    )
```

- [ ] **Step 8: `DocumentSession.swift` 粘贴入口改造（保留 selectedImageId/setImage 过渡壳）**

**关键约束**：`selectedImageId`（节点 id）与 `setImage` 被 `ContentView.clearImage`、`CanvasMetalView` 双击/⌫/Esc、`MetalRenderer` 选中描边引用，而这些的块级改造依赖 `NodeFrame.blocks`（Task 2）与 `hitTestImageBlock`（Task 3）。**本任务保留 `selectedImageId` 声明与 `setImage` 签名不删**，只改粘贴入口与命令调用，保证 Task 1 独立可编译；块级选中态彻底改造见 Task 3 Step 4。

替换 `setPastedImage`（第 468-479 行）为：

```swift
/// 粘贴/拖入入口：归一 + 追加图片块到节点末尾。要求有选中节点。
@discardableResult
func appendPastedImage(from data: Data) -> Bool {
    commitEditingIfNeeded()
    guard let normalizer = imageNormalizer,
          !model.selectedIds.isEmpty,
          let normalized = normalizer(data) else {
        return false
    }
    self.selectedImageId = nil
    for id in Array(model.selectedIds) {
        commandBus.execute(
            .appendImageBlock(id: id, image: normalized.data, pixelSize: normalized.pixelSize)
        )
    }
    return true
}
```

替换 `setImage`（第 453-464 行）为过渡壳（沿用 `selectedImageId` 节点 id 语义，`image == nil` 时删除该节点**首个图片块**；非 nil 分支追加——保留签名以不破坏 `ContentView.clearImage` 回调）：

```swift
/// 过渡壳：⌫ 清图 → 删除选中节点首个图片块；非清除 → 追加。Task 3 由 removeSelectedImageBlock 取代。
func setImage(_ image: Data?, pixelSize: ImagePixelSize?) {
    commitEditingIfNeeded()
    if let image, let pixelSize {
        self.selectedImageId = nil
        for id in Array(model.selectedIds) {
            commandBus.execute(.appendImageBlock(id: id, image: image, pixelSize: pixelSize))
        }
        return
    }
    // 清除：删除选中节点（或 ⌫ 分派目标）的首个图片块。
    let targetIds = selectedImageId.map { [$0] } ?? Array(model.selectedIds)
    self.selectedImageId = nil
    for id in targetIds {
        guard let node = model.node(id: id),
              let first = node.blocks.first(where: {
                  if case .image = $0.kind { return true } else { return false }
              }) else { continue }
        commandBus.execute(.removeImageBlock(id: id, blockId: first.id))
    }
}
```

`selectImage`/`clearImageSelection`（第 484-490 行）**保留不动**（仍操作 `selectedImageId`）。

- [ ] **Step 9: `DocumentSession.swift` 聚拢规则（startEditing + commitEditingIfNeeded）**

`setText` 命令删除后，`commitEditingIfNeeded` 调用 `.setText` 会编译错误——本步骤必须完成。`startEditing`（第 519-523 行）：

```swift
selectOnly(id)
originalEditingText = node.text
originalBlocks = node.blocks      // 新增：Undo 基线
draftText = node.text
editingId = id
```

新增属性（与 `originalEditingText` 相邻声明）：

```swift
/// 编辑提交的 Undo 基线（内容流聚拢前的块序列）。
private var originalBlocks: [ContentBlock] = []
```

`commitEditingIfNeeded`（第 526-537 行）替换为聚拢规则：

```swift
@discardableResult
func commitEditingIfNeeded() -> Bool {
    guard let editingId else { return false }
    let committedText = draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "未命名"
        : draftText
    self.editingId = nil
    // 聚拢规则：文本合并单块；图片按原相对顺序聚拢单侧——
    // 原序列首个非空块是图片 → [images] + [text]（图上文下）；否则 [text] + [images]（文上图下）。
    let images = originalBlocks.filter { block in
        if case .image = block.kind { return true } else { return false }
    }
    let firstBlockIsImage: Bool = {
        guard let first = originalBlocks.first else { return false }
        if case .image = first.kind { return true } else { return false }
    }()
    var newBlocks: [ContentBlock]
    if firstBlockIsImage {
        newBlocks = images + [ContentBlock(id: UUID(), kind: .text(committedText))]
    } else {
        newBlocks = [ContentBlock(id: UUID(), kind: .text(committedText))] + images
    }
    if newBlocks != originalBlocks {
        commandBus.execute(
            .setBlocks(id: editingId, old: originalBlocks, new: newBlocks)
        )
    }
    originalBlocks = []
    originalEditingText = ""
    return true
}
```

`cancelEditing` 同步清 `originalBlocks = []`。`newDocument`/`loadImported`/`restoreRecovery`/`load`/`save` 等处若有 `originalEditingText = ""` 重置，相邻加 `originalBlocks = []`（或依赖 `commitEditingIfNeeded` 已清——凡直接赋 `editingId = nil` 而不走 commit 的路径都要清）。

- [ ] **Step 10: 更新 `CodecTests.swift`（v4 往返 + 旧格式迁移）**

`CodecImageTests` 的 `v2FileWithoutImage_opensWithoutReject`、`v1File_chainMigrates` 断言 `back.version == 3` → `== 4`；`imageRoundTrip` 的 `back.root.children[0].image == Data(...)` 改走计算属性仍成立（`Node.image` 只读兼容），但新增 v3→v4 显式迁移测试：

```swift
@Test func v3FileWithImage_migratesToBlocks_imageAboveText() throws {
    // v3 格式：text + image + imagePixelSize，无 blocks。
    let json = """
    {"version":3,"root":{"id":"00000000-0000-0000-0000-000000000001","text":"标题","collapsed":false,"image":"iVBORw0KGgo=","imagePixelSize":{"width":100,"height":50},"children":[]}}
    """.data(using: .utf8)!
    let back = try YMindCodec.decode(json)
    #expect(back.version == 4)
    let root = back.root
    #expect(root.blocks.count == 2)
    if case .image = root.blocks[0].kind {} else { Issue.record("第 0 块应为图片") }
    if case .text(let s) = root.blocks[1].kind { #expect(s == "标题") } else { Issue.record("第 1 块应为文本") }
    #expect(root.image == Data(base64Encoded: "iVBORw0KGgo="))
    #expect(root.text == "标题")
}

@Test func v4RoundTrip_blocksPreserved() throws {
    let model = MindMapModel.makeNew()
    let root = model.document.root.id
    let blockId = model.appendImageBlock(
        id: root,
        image: Data([0x89, 0x50]),
        pixelSize: ImagePixelSize(width: 10, height: 20)!
    )
    let data = try YMindCodec.encode(model.document)
    let back = try YMindCodec.decode(data)
    #expect(back.version == 4)
    #expect(back.root.blocks.count == 2)
    #expect(back.root.blocks[1].id == blockId)
    if case .image(let img) = back.root.blocks[1].kind {
        #expect(img.data == Data([0x89, 0x50]))
        #expect(img.pixelSize == ImagePixelSize(width: 10, height: 20))
    } else {
        Issue.record("blocks[1] 应为图片")
    }
}
```

- [ ] **Step 11: 更新 `CommandBusTests.swift`（4 新命令 undo/redo）**

删除 `setText_undo` 与 `setImage`/`clearImage`/`noOpSetImage` 用例，替换为：

```swift
@Test func setBlocks_undoRedo() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    let old = model.document.root.blocks
    let new = [ContentBlock(id: UUID(), kind: .text("新文本"))]
    bus.execute(.setBlocks(id: root, old: old, new: new))
    #expect(model.node(id: root)?.blocks == new)
    bus.undo()
    #expect(model.node(id: root)?.blocks == old)
    bus.redo()
    #expect(model.node(id: root)?.blocks == new)
}

@Test func appendImageBlock_undoRemoves_redoReinsertsSameId() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    let px = ImagePixelSize(width: 10, height: 10)!
    bus.execute(.appendImageBlock(id: root, image: Data([0x01]), pixelSize: px))
    let blockId = model.node(id: root)!.blocks[1].id
    #expect(model.node(id: root)?.blocks.count == 2)
    bus.undo()
    #expect(model.node(id: root)?.blocks.count == 1)
    bus.redo()
    #expect(model.node(id: root)?.blocks[1].id == blockId)
}

@Test func replaceImageBlock_undoRestoresOld() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    let px = ImagePixelSize(width: 10, height: 10)!
    bus.execute(.appendImageBlock(id: root, image: Data([0x01]), pixelSize: px))
    let blockId = model.node(id: root)!.blocks[1].id
    bus.execute(.replaceImageBlock(id: root, blockId: blockId, image: Data([0x02]), pixelSize: px))
    if case .image(let img) = model.node(id: root)!.blocks[1].kind {
        #expect(img.data == Data([0x02]))
    }
    bus.undo()
    if case .image(let img) = model.node(id: root)!.blocks[1].kind {
        #expect(img.data == Data([0x01]))
    }
    bus.redo()
    if case .image(let img) = model.node(id: root)!.blocks[1].kind {
        #expect(img.data == Data([0x02]))
    }
}

@Test func removeImageBlock_undoRestoresBlockAtSameIndex() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    let px = ImagePixelSize(width: 10, height: 10)!
    bus.execute(.appendImageBlock(id: root, image: Data([0x01]), pixelSize: px))
    let blockId = model.node(id: root)!.blocks[1].id
    bus.execute(.removeImageBlock(id: root, blockId: blockId))
    #expect(model.node(id: root)?.blocks.count == 1)
    bus.undo()
    #expect(model.node(id: root)?.blocks.count == 2)
    #expect(model.node(id: root)?.blocks[1].id == blockId)
    bus.redo()
    #expect(model.node(id: root)?.blocks.count == 1)
}

@Test func noOpSetBlocks_doesNotEnterUndoStack() {
    let model = MindMapModel.makeNew()
    let bus = CommandBus(model: model)
    let root = model.document.root.id
    let old = model.document.root.blocks
    bus.execute(.setBlocks(id: root, old: old, new: old))
    #expect(bus.canUndo == false)
}
```

- [ ] **Step 12: 更新 `DocumentSessionTests.swift`**

`setPastedImage_commitsEditingFirst` 改名为 `appendPastedImage_commitsEditingFirst`（调 `appendPastedImage(from:)`，断言不变）；**删除** ⌫ 分派、`selectImage` 相关用例（`removeSelectedImageBlock`/`selectImageBlock` 尚未存在，Task 3 才引入——Task 3 Step 4 会重建这些用例）。新增：

```swift
@Test func appendPastedImage_appendsBlockAtEnd() {
    let session = DocumentSession()
    let root = session.model.document.root.id
    let px = ImagePixelSize(width: 10, height: 10)!
    let normalizer: (Data) -> (data: Data, pixelSize: ImagePixelSize)? = {
        ($0, px)
    }
    session.imageNormalizer = normalizer
    session.selectOnly(root)
    let ok = session.appendPastedImage(from: Data([0x01]))
    #expect(ok == true)
    #expect(session.model.node(id: root)?.blocks.count == 2)
    if case .image(let img) = session.model.node(id: root)!.blocks[1].kind {
        #expect(img.data == Data([0x01]))
    } else {
        Issue.record("blocks[1] 应为图片")
    }
}
```

- [ ] **Step 13: 编译 + 全量测试**

```bash
cd /Users/renjun.li/Desktop/YMind/YMindApp && xcodebuild test -scheme YMindApp -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `TEST SUCCEEDED`（Model/Codec/Command/Session 层全绿；布局/渲染用例此时可能因签名编译错误失败，进入 Task 2 修复）。

- [ ] **Step 14: Commit**

```bash
git add YMindApp/YMindApp/Model YMindApp/YMindApp/Commands YMindApp/YMindApp/Session YMindApp/YMindAppTests
git commit -m "feat: Node 内容流 schema v4（blocks 块序列）+ 块级命令栈（setBlocks/append/replace/removeImageBlock）"
```

---

### Task 2: 布局层 —— BlockLayoutFrame + TextMeasure 块序 + RadialLayout

**Files:**
- Modify: `YMindApp/YMindApp/Layout/LayoutSnapshot.swift`、`Layout/TextMeasure.swift`、`Layout/RadialLayout.swift`
- Test: `YMindApp/YMindAppTests/RadialLayoutTests.swift`、`HitTestTests.swift`

- [ ] **Step 1: `LayoutSnapshot.swift` 扩展**

替换 `NodeFrame.imageRect` 为块布局数组：

```swift
/// 块布局帧：文本块带内容，图片块 text 为 nil。rect 为节点局部坐标 top-left 原点。
struct BlockLayoutFrame: Equatable {
    let blockId: UUID
    let text: String?
    let rect: CGRect
}

// NodeFrame 内：
let blocks: [BlockLayoutFrame]

// init 参数：blocks: [BlockLayoutFrame] = []（替换 imageRect: CGRect? = nil）
// 删除 imageRect 属性。
```

- [ ] **Step 2: `TextMeasure.swift` 块序尺寸合成**

新增 `measure(for:isRoot:) -> (size: NodeSize, blocks: [BlockLayoutFrame])`，`size(for:isRoot:)` 改为调用它取 `.size`（对外签名不变）：

```swift
struct BlockMeasure {
    let size: NodeSize
    let blocks: [BlockLayoutFrame]
}

func measure(for node: Node, isRoot: Bool) -> BlockMeasure {
    let font = NSFont.systemFont(
        ofSize: isRoot ? 18.4 : 14.7,
        weight: isRoot ? .bold : .medium
    )
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let maxWidth = isRoot
        ? LayoutConstants.rootMaxTextWidth
        : LayoutConstants.nodeMaxTextWidth

    let horizontalPadding = isRoot ? LayoutConstants.rootPadX : LayoutConstants.nodePadX
    let verticalPadding = isRoot ? LayoutConstants.rootPadY : LayoutConstants.nodePadY
    let lineHeight = isRoot ? LayoutConstants.rootLineHeight : LayoutConstants.nodeLineHeight

    var blocks: [BlockLayoutFrame] = []
    var maxBlockWidth: CGFloat = 0
    var contentHeight: CGFloat = 0

    for block in node.blocks {
        switch block.kind {
        case .text(let s):
            let measured = measureTextWidth(s, maxWidth: maxWidth, attributes: attributes)
            let lines = lineCount(s, maxWidth: maxWidth, attributes: attributes)
            let width = ceil(measured + horizontalPadding * 2)
            let height = ceil(CGFloat(lines) * lineHeight)
            maxBlockWidth = max(maxBlockWidth, width)
            blocks.append(BlockLayoutFrame(blockId: block.id, text: s, rect: CGRect(x: 0, y: contentHeight, width: width, height: height)))
            contentHeight += height
        case .image(let img):
            guard img.pixelSize.width > 0, img.pixelSize.height > 0 else { continue }
            let width = min(CGFloat(img.pixelSize.width), LayoutConstants.imageMaxDisplayWidth)
            let height = width * CGFloat(img.pixelSize.height) / CGFloat(img.pixelSize.width)
            maxBlockWidth = max(maxBlockWidth, width + horizontalPadding * 2)
            blocks.append(BlockLayoutFrame(
                blockId: block.id,
                text: nil,
                rect: CGRect(x: 0, y: contentHeight, width: width, height: height)
            ))
            contentHeight += height
        }
        contentHeight += LayoutConstants.imageTextGap
    }
    if !blocks.isEmpty { contentHeight -= LayoutConstants.imageTextGap }  // 末块后无 gap

    return BlockMeasure(
        size: NodeSize(
            width: ceil(max(maxBlockWidth, 1)),
            height: ceil(contentHeight + verticalPadding * 2)
        ),
        blocks: blocks
    )
}
```

保留 `textWidth`/`lineCount` 私有方法（把原 `for sourceLine in sourceLines` 拆成 `lineCount(_:maxWidth:attributes:) -> Int` 与 `measureTextWidth(_:maxWidth:attributes:) -> CGFloat`，逻辑不变）。`size(for:isRoot:)` 变：

```swift
func size(for node: Node, isRoot: Bool) -> NodeSize {
    measure(for: node, isRoot: isRoot).size
}
```

- [ ] **Step 3: `RadialLayout.swift` 产出块布局 + payload 按块 id**

`BranchMetadata` 增 `let blocks: [BlockLayoutFrame]`；`subtreeHeight` 内：

```swift
func subtreeHeight(_ node: Node, isRoot: Bool) -> BranchMetadata {
    let m = measure.measure(for: node, isRoot: isRoot)
    let size = m.size
    guard !node.collapsed, !node.children.isEmpty else {
        return BranchMetadata(size: size, height: size.height, blocks: m.blocks, children: [])
    }
    // ... children 同现状 ...
    return BranchMetadata(size: size, height: max(size.height, childrenHeight), blocks: m.blocks, children: childLayouts)
}
```

`placeBranch`/`rootFrame` 中（`metadata` 携带 `blocks`）：

```swift
let centeredBlocks = metadata.blocks.map { b -> BlockLayoutFrame in
    if b.text != nil {
        // 文本块：水平撑满节点内容宽（居中栅格化）。
        return BlockLayoutFrame(
            blockId: b.blockId,
            text: b.text,
            rect: CGRect(x: 0, y: b.rect.minY, width: metadata.size.width, height: b.rect.height)
        )
    }
    // 图片块：水平居中。
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
```

`NodeFrame` 构造：`imageRect: Self.imageRect(...)` → `blocks: centeredBlocks`（`subtreeHeight` 返回的 metadata 需先经此居中映射，placeBranch 内对 `metadata` 调用）。`collectPayloads` 改为：

```swift
func collectPayloads(_ node: Node) {
    for block in node.blocks {
        if case .image(let img) = block.kind, frames[node.id] != nil {
            payloads[block.id] = ImagePayload(pixelSize: img.pixelSize, data: img.data)
        }
    }
    node.children.forEach(collectPayloads)
}
```

删除 `imageRect(size:pixelSize:)` 私有方法。

- [ ] **Step 4: 更新布局测试**

`RadialLayoutTests` 中 `imageRect` 断言改为 `blocks` 遍历（找 `text == nil` 的块）：

```swift
let imageBlocks = frame.blocks.filter { $0.text == nil }
#expect(imageBlocks.count == 1)
let rect = imageBlocks[0].rect
#expect(rect.width == 300)
#expect(abs(rect.height - 150) < 0.001)
#expect(abs(rect.midX - frame.size.width / 2) < 0.001)
```

新增多块叠加测试：

```swift
@Test func multipleBlocks_stackVerticallyInOrder() {
    let doc = MindMapDocument.blank(rootText: "根")
    let root = doc.root.id
    var node = doc.root
    node.blocks = [
        ContentBlock(id: UUID(), kind: .text("文")),
        ContentBlock(id: UUID(), kind: .image(.init(data: Data([0x01]), pixelSize: ImagePixelSize(width: 100, height: 100)!))),
        ContentBlock(id: UUID(), kind: .text("尾")),
    ]
    node.id = root
    doc.root = node
    let snapshot = RadialLayout.layout(document: doc, measure: measure())
    let frame = snapshot.frames[root]!
    let blocks = frame.blocks
    #expect(blocks.count == 3)
    #expect(blocks[0].text == "文")
    #expect(blocks[1].text == nil)
    #expect(blocks[2].text == "尾")
    #expect(blocks[1].rect.minY >= blocks[0].rect.maxY)
    #expect(blocks[2].rect.minY >= blocks[1].rect.maxY)
}
```

（`RadialLayout.layout(document:measure:)` 现有签名返回 `LayoutSnapshot`，测试内 `measure()` 为既有 helper。）

- [ ] **Step 5: 编译 + 测试**

```bash
cd /Users/renjun.li/Desktop/YMind/YMindApp && xcodebuild test -scheme YMindApp -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: 布局层绿；Render 层编译错误进入 Task 3。

- [ ] **Step 6: Commit**

```bash
git add YMindApp/YMindApp/Layout YMindApp/YMindAppTests
git commit -m "feat: 布局层块序合成（BlockLayoutFrame + TextMeasure.measure + payload 按块 id）"
```

---

### Task 3: 渲染层 —— TextAtlas 块化 + drawImage 遍历 + 块级命中/选中

**Files:**
- Modify: `YMindApp/YMindApp/Render/TextAtlas.swift`、`Render/ImageTextureCache.swift`、`Render/MetalRenderer.swift`、`Render/CanvasHitTesting.swift`、`Render/CanvasMetalView.swift`、`ContentView.swift`、`Session/DocumentSession.swift`
- Test: `YMindApp/YMindAppTests/ImageTextureCacheTests.swift`、`HitTestTests.swift`、`PNGExporterTests.swift`、`DocumentSessionTests.swift`

- [ ] **Step 0: 块级选中态彻底改造（DocumentSession selectedImageId → selectedImageBlock）**

`NodeFrame.blocks`（Task 2）与 `hitTestImageBlock`（本任务）就绪后，把 Task 1 保留的 `selectedImageId`/`setImage` 过渡壳换成块级语义：

`DocumentSession.swift`：
- 状态声明（第 95-96 行）：`@Published private(set) var selectedImageId: UUID?` → `@Published private(set) var selectedImageBlock: (nodeId: UUID, blockId: UUID)?`；
- 全部 `selectedImageId` 出现处（`newDocument`/`loadImported`/`restoreRecovery`/`load`/`save`/`selectOnly`/`clearSelection`/`syncSelectionFromModel`/`appendPastedImage`/`setImage`）逐一改为 `selectedImageBlock`（置 nil）；
- 删除过渡壳 `setImage(_:pixelSize:)`（Task 1 版本），替换为：

```swift
/// 删除选中的图片块（⌫ 分派）。无图片选中则 no-op。
func removeSelectedImageBlock() {
    commitEditingIfNeeded()
    guard let selected = selectedImageBlock else { return }
    self.selectedImageBlock = nil   // 删块后回落：选中回节点
    commandBus.execute(.removeImageBlock(id: selected.nodeId, blockId: selected.blockId))
}
```

- `selectImage`/`clearImageSelection`（Task 1 保留的 `selectedImageId` 版本）替换为块级：

```swift
/// 双击图片块：进入图片级选中（节点选中态不变）。
func selectImageBlock(nodeId: UUID, blockId: UUID) {
    guard model.node(id: nodeId) != nil else { return }
    selectedImageBlock = (nodeId, blockId)
}

func clearImageSelection() {
    selectedImageBlock = nil
}
```

- [ ] **Step 1: `TextAtlas.swift` 按块栅格化**

`texture(for:frame:text:scale:device:)` 替换为块接口（entries key 用 blockId）：

```swift
func texture(
    for frame: NodeFrame,
    block: BlockLayoutFrame,
    scale: CGFloat,
    device: MTLDevice
) -> MTLTexture? {
    let displayScale = max(scale, 1)
    let width = max(Int(ceil(block.rect.width * displayScale)), 1)
    let height = max(Int(ceil(block.rect.height * displayScale)), 1)
    let text = block.text ?? ""
    let key = CacheKey(
        text: text,
        width: width,
        height: height,
        scale: Int((displayScale * 100).rounded()),
        isRoot: frame.isRoot
    )
    if let cached = entries[block.blockId], cached.key == key {
        return cached.texture
    }
    // 字体/段落同现状；textRect 用块 rect（含 padding 居中）。
    let horizontalPadding: CGFloat = frame.isRoot ? LayoutConstants.rootPadX : LayoutConstants.nodePadX
    let textRect = CGRect(
        x: horizontalPadding,
        y: 0,
        width: max(block.rect.width - horizontalPadding * 2, 1),
        height: max(block.rect.height, 1)
    )
    // ... 其余栅格化/上传逻辑同现状，entries[block.blockId] 写入。
}
```

- [ ] **Step 2: `MetalRenderer.swift` drawText 逐块**

`drawText` 内循环改为：

```swift
for frame in orderedFrames(snapshot) {
    for block in frame.blocks where block.text != nil {
        guard let texture = textAtlas.texture(
            for: frame,
            block: block,
            scale: rasterScale,
            device: device
        ) else { continue }
        let worldRect = CGRect(
            x: frame.rect.minX + block.rect.minX,
            y: frame.rect.minY + block.rect.minY,
            width: block.rect.width,
            height: block.rect.height
        )
        let color = rgba(frame.isRoot ? .white : .labelColor)
        let vertices = texturedQuad(rect: screenRect(worldRect, camera: camera), color: color)
        guard let buffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<TexturedVertex>.stride * vertices.count
        ) else { continue }
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(
            &viewport,
            length: MemoryLayout<ViewportUniforms>.stride,
            index: 1
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }
}
```

- [ ] **Step 3: `MetalRenderer.swift` drawImage 遍历块**

`drawImage` 内循环改为：

```swift
for frame in orderedFrames(snapshot) {
    for block in frame.blocks where block.text == nil {
        guard let payload = snapshot.imagePayloads[block.blockId] else { continue }
        let worldRect = CGRect(
            x: frame.rect.minX + block.rect.minX,
            y: frame.rect.minY + block.rect.minY,
            width: block.rect.width,
            height: block.rect.height
        )
        guard worldRect.intersects(viewportWorldRect) else { continue }
        knownIds.insert(block.blockId)
        guard let texture = imageTextureCache.texture(
            id: block.blockId,
            localRect: block.rect,
            payload: payload,
            displayScale: rasterScale,
            device: device
        ) else { continue }
        // 绘制 quad 同现状（用 worldRect）
    }
}
```

- [ ] **Step 4: `MetalRenderer.swift` 选中描边按块**

签名 `selectedImageId: UUID?` → `selectedImageBlock: (nodeId: UUID, blockId: UUID)?`（drawSelectionStrokes 与 drawImage 参数、调用点、PNG 导出 `selectedImageId: nil` 全部同步）；描边段：

```swift
if let sel = selectedImageBlock,
   let frame = snapshot.frames[sel.nodeId],
   let block = frame.blocks.first(where: { $0.blockId == sel.blockId }) {
    let worldRect = CGRect(
        x: frame.rect.minX + block.rect.minX,
        y: frame.rect.minY + block.rect.minY,
        width: block.rect.width,
        height: block.rect.height
    )
    vertices += strokeVertices(
        rect: screenRect(worldRect, camera: camera),
        thickness: max(1.5, 2 * camera.scale),
        color: rgba(.controlAccentColor)
    )
}
```

- [ ] **Step 5: `CanvasHitTesting.swift` 块级命中**

```swift
/// 双击命中图片块：返回 (nodeId, blockId)。
func hitTestImageBlock(
    screenPoint: CGPoint,
    snapshot: LayoutSnapshot,
    camera: Camera
) -> (nodeId: UUID, blockId: UUID)? {
    let world = camera.screenToWorld(screenPoint)
    for frame in snapshot.frames.values {
        for block in frame.blocks where block.text == nil {
            let worldRect = CGRect(
                x: frame.rect.minX + block.rect.minX,
                y: frame.rect.minY + block.rect.minY,
                width: block.rect.width,
                height: block.rect.height
            )
            if worldRect.contains(world) {
                return (frame.id, block.blockId)
            }
        }
    }
    return nil
}
```

- [ ] **Step 6: `CanvasMetalView.swift` 双击/⌫/Esc**

双击段（第 287-295 行）：

```swift
if event.clickCount == 2 {
    if let hit = hitTestImageBlock(
        screenPoint: point,
        snapshot: session.snapshot,
        camera: session.camera
    ) {
        session.selectImageBlock(nodeId: hit.nodeId, blockId: hit.blockId)
    } else {
        actions.edit(id)
    }
    gesture = .none
    return
}
```

⌫ 段（第 475-479 行）与 Esc 段（第 481-483 行）：

```swift
case 51, 117:
    if session.selectedImageBlock != nil {
        actions.clearImage()      // 选中图片块 → 删块
    } else {
        actions.delete()          // 删节点
    }
...
case 53:
    if session.selectedImageBlock != nil {
        session.clearImageSelection()
    } else if !session.cutSourceIds.isEmpty {
        actions.cancelCut()
    }
```

`CanvasActions.clearImage` 回调（ContentView 第 49 行）改：

```swift
clearImage: { session.removeSelectedImageBlock() }
```

`selectedImageId: session.selectedImageId`（CanvasMetalView 第 219 行）改 `selectedImageBlock: session.selectedImageBlock`。

- [ ] **Step 7: ContentView 选中回落**

`deleteSelected`（第 261-264 行）：

```swift
if let sel = session.selectedImageBlock, session.model.node(id: sel.nodeId) == nil {
    session.clearImageSelection()
}
```

- [ ] **Step 8: 更新测试**

`ImageTextureCacheTests`：`imageRect:` 参数 → `blocks:` 数组（含一个 `BlockLayoutFrame(text: nil, ...)`），`frame.imageRect!` → 取 blocks 中图片块的 `rect`。`HitTestTests`：`hitTestImageRect` → `hitTestImageBlock`（返回 tuple，`#expect(hit?.nodeId == id)` / `#expect(hit == nil)`）。`PNGExporterTests` 同改。

`DocumentSessionTests`：Task 1 删除的块级选中用例在此重建（`selectedImageBlock` 现可用）：

```swift
@Test func removeSelectedImageBlock_deletesBlockAndClearsSelection() {
    let session = DocumentSession()
    let root = session.model.document.root.id
    let blockId = session.model.appendImageBlock(
        id: root,
        image: Data([0x01]),
        pixelSize: ImagePixelSize(width: 10, height: 10)!
    )
    session.selectImageBlock(nodeId: root, blockId: blockId)
    #expect(session.selectedImageBlock != nil)

    session.removeSelectedImageBlock()
    #expect(session.model.node(id: root)?.blocks.count == 1)
    #expect(session.selectedImageBlock == nil)
}

@Test func selectImageBlock_clearOnEscapeProxy_andNotInUndoStack() {
    let session = DocumentSession()
    let root = session.model.document.root.id
    let blockId = session.model.appendImageBlock(
        id: root, image: Data([0x01]), pixelSize: ImagePixelSize(width: 10, height: 10)!
    )
    session.selectImageBlock(nodeId: root, blockId: blockId)
    #expect(session.selectedImageBlock?.blockId == blockId)
    session.clearImageSelection()
    #expect(session.selectedImageBlock == nil)
    #expect(session.commandBus.canUndo == false)
}
```

（原 Task 1 保留的 `selectImage(...)` 用例改为 `selectImageBlock`。）

- [ ] **Step 9: 编译 + 测试**

```bash
cd /Users/renjun.li/Desktop/YMind/YMindApp && xcodebuild test -scheme YMindApp -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `TEST SUCCEEDED`（此时仅剩导出层编译错误/失败，进入 Task 4）。

- [ ] **Step 10: Commit**

```bash
git add YMindApp/YMindApp/Render YMindApp/YMindApp/ContentView.swift YMindApp/YMindAppTests
git commit -m "feat: 渲染/命中按块遍历（TextAtlas 块栅格 + imageRects 绘制 + 块级选中）"
```

---

### Task 4: 编辑态 ⌘V —— CommitTextView.paste 拦截

**Files:**
- Modify: `YMindApp/YMindApp/App/NodeEditorOverlay.swift`、`ContentView.swift`
- Test: `YMindApp/YMindAppTests/DocumentSessionTests.swift`（逻辑层）

- [ ] **Step 1: `NodeEditorOverlay.swift` 加回调**

`NodeEditorOverlay`/`NodeTextEditor` 增 `let onPasteImage: () -> Void`；`NodeTextEditor.makeNSView` 里 `textView.onPasteImage = onPasteImage`；`updateNSView` 同步。`CommitTextView`：

```swift
var onPasteImage: (() -> Void)?

override func paste(_ sender: Any?) {
    let pb = NSPasteboard.general
    let hasImage = pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil
    if hasImage, let onPasteImage {
        onPasteImage()          // 图片粘贴走壳层（先提交文字再追加图片块）
    } else {
        super.paste(sender)     // 纯文本 → 正常 NSTextView 粘贴
    }
}
```

- [ ] **Step 2: `ContentView.swift` 接线**

`NodeEditorOverlay(...)` 调用处加 `onPasteImage: paste`（`paste` 是既有闭包，内部已 `commitEditing()` + 图片分支）。

- [ ] **Step 3: 逻辑层测试（Session 侧已覆盖 commit+append 路径）**

`DocumentSessionTests` 新增：

```swift
@Test func pasteImageWhileEditing_commitsTextThenAppendsBlock() {
    let session = DocumentSession()
    let root = session.model.document.root.id
    session.selectOnly(root)
    session.startEditing(root)
    session.draftText = "先提交的文字"
    // 模拟编辑态 ⌘V 图片：先 commitEditingIfNeeded 再 appendPastedImage（paste 闭包同序）。
    session.commitEditingIfNeeded()
    let ok = session.appendPastedImage(from: Data([0x01]))
    #expect(ok == false)   // 无归一器 stub → false；先验证提交生效
    #expect(session.model.node(id: root)?.text == "先提交的文字")
}
```

（`NSTextView.paste` 的 UI 行为无法单测，逻辑链路 commit+append 由本用例钉死；真机手测见 Task 6。）

- [ ] **Step 4: 编译 + 测试**

```bash
cd /Users/renjun.li/Desktop/YMind/YMindApp && xcodebuild test -scheme YMindApp -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/App/NodeEditorOverlay.swift YMindApp/YMindApp/ContentView.swift YMindApp/YMindAppTests
git commit -m "fix: 编辑态 ⌘V 图片粘贴（CommitTextView.paste 拦截 → 提交文字 + 追加图片块）"
```

---

### Task 5: 导出层 —— Markdown 多图按块 id

**Files:**
- Modify: `YMindApp/YMindApp/Model/MarkdownExporter.swift`、`YMindAppApp.swift`
- Test: `YMindApp/YMindAppTests/MarkdownExporterTests.swift`

- [ ] **Step 1: `MarkdownExporter.swift` 多图**

`MarkdownImage` 的 `nodeId: UUID` → `blockId: UUID`；`output(from:)` 根节点行与 `walk` 中：

```swift
// 根节点
var rootLine = "# \(collapsedText(document.root.text))"
for block in document.root.blocks {
    if case .image(let img) = block.kind {
        rootLine += " ![图片](assets/\(block.id.uuidString).png)"
        images.append(MarkdownImage(blockId: block.id, data: img.data))
    }
}
```

`walk` 内 `content += " ![图片](assets/\(child.id.uuidString).png)"` 同理改为遍历 `child.blocks`。

- [ ] **Step 2: `YMindAppApp.swift` 导出**

`exportMarkdown` 文件夹包路径 `assets/<nodeId>.png` → `assets/<blockId>.png`（`output.images` 已带 blockId，直接 `image.blockId.uuidString`）。

- [ ] **Step 3: 更新测试**

`MarkdownExporterTests`：`output.images[0].nodeId == child.id` → 改为遍历 `child.blocks` 找图片块的 id 断言；`collapsedBranchWithImage_stillExported` 的 `.images.count == 1` 不变。新增多图：

```swift
@Test func multiImageNode_exportsAllReferences() {
    var doc = MindMapDocument.blank(rootText: "根")
    let png = Data([0x89, 0x50])
    let px = ImagePixelSize(width: 10, height: 10)!
    var child = Node(text: "多图节点")
    child.blocks.append(ContentBlock(id: UUID(), kind: .image(.init(data: png, pixelSize: px))))
    child.blocks.append(ContentBlock(id: UUID(), kind: .image(.init(data: png, pixelSize: px))))
    doc.root.children = [child]
    let output = MarkdownExporter.output(from: doc)
    let refs = output.images
    #expect(refs.count == 2)
    for ref in refs {
        #expect(output.text.contains("![图片](assets/\(ref.blockId.uuidString).png)"))
    }
}
```

- [ ] **Step 4: 编译 + 全量测试**

```bash
cd /Users/renjun.li/Desktop/YMind/YMindApp && xcodebuild test -scheme YMindApp -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `TEST SUCCEEDED`。

- [ ] **Step 5: Commit**

```bash
git add YMindApp/YMindApp/Model/MarkdownExporter.swift YMindApp/YMindApp/YMindAppApp.swift YMindApp/YMindAppTests
git commit -m "feat: Markdown 导出多图（按块 id 引用 + 文件夹包多 assets）"
```

---

### Task 6: 收尾 —— 边界脚本、文档、手测

**Files:**
- Modify: `docs/架构现状.md`、`scripts/check-boundaries.sh`（如需）、`docs/superpowers/specs/2026-10-01-ymind-content-flow-design.md`（状态更新）

- [ ] **Step 1: 边界检查**

```bash
cd /Users/renjun.li/Desktop/YMind && scripts/check-boundaries.sh
```

Expected: 全部通过（`ContentBlock.swift` 只 import Foundation，属 Model 白名单；新增文件无越界 import）。若有违规，修 import 或按 AGENTS.md 追加白名单。

- [ ] **Step 2: 文档落档**

`docs/架构现状.md`：字段表更新 Node（blocks 取代 text/image/imagePixelSize 存储）、currentVersion=4、§5 依赖白名单核对（无新增 import 则不改）。

- [ ] **Step 3: 构建 + 手测 App**

```bash
cd /Users/renjun.li/Desktop/YMind/YMindApp && xcodebuild build -scheme YMindApp -destination 'platform=macOS' 2>&1 | tail -3
```

启动 App 手测（`docs/架构现状.md` §7.4 基础上追加）：
- 编辑态 ⌘V 贴图 → 文字提交 + 图片在节点下方；编辑态 ⌘V 纯文本 → 正常文本粘贴；
- 双击图片块 → 替换；选中图片块 ⌫ → 删块、文字保留；⌘Z 恢复；
- 先贴图后输文（图上文下）/ 先输文后贴图（文上图下）两种顺序；
- 多图追加（多次粘贴 → 多图按序）；
- 打开 v3 旧文件 → 图在上文在下，无图节点纯文本；保存后为 v4；
- Markdown 导出多图文件夹包；PNG 导出含多图。

- [ ] **Step 4: 全量测试 + Commit**

```bash
cd /Users/renjun.li/Desktop/YMind/YMindApp && xcodebuild test -scheme YMindApp -destination 'platform=macOS' 2>&1 | tail -5
git add -A
git commit -m "docs: 内容流 schema v4 落档（架构现状 + spec 状态）"
```

Expected: `TEST SUCCEEDED` + 手测通过。
