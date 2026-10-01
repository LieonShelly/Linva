# 设计文档：节点图文内容流 + 编辑态贴图

- **日期：** 2026-10-01
- **状态：** 已实现（2026-10-01，提交 62a220f..87d0477 + 文档 §18）
- **流程：** Superpowers brainstorming → 本 spec → writing-plans → subagent-driven 实现
- **关联：** 承 `2026-10-01-ymind-image-node-design.md`（v3 单图），本文档将其升级为**多图多段内容流**并修复**编辑态 ⌘V 粘贴图片失败**

## 0. 背景与两个问题

### 问题 1：编辑态 ⌘V 粘贴图片失败

现状链路（已实测代码确认）：

- `DocumentCommands`（`YMindAppApp.swift`）未自定义 Paste 菜单项，Edit 菜单走系统默认 `paste:` selector → first responder。
- 编辑态 first responder 是 `CommitTextView`（NSTextView，`App/NodeEditorOverlay.swift`），⌘V 触发**原生文本粘贴**，`ContentView.paste()`（含图片逻辑）不触发。
- `CanvasMetalView.keyDown` 有 `guard session.editingId == nil`，编辑态键盘全让给 NSTextView。

修复：`CommitTextView` override `paste(_:)`，剪贴板含图片时改走图片粘贴回调。

### 问题 2：图文排布顺序

现状：`Node` 单图（`image` + `imagePixelSize`），布局硬编码「图在上、文字在下」（`TextMeasure.size` 高度 = `textHeight + imageTextGap + imageHeight`；`RadialLayout.imageRect` 注释「图在上、文字在下」）。

用户拍板（2026-10-01 会话）：
1. **内容流**：块序列（text/image 交错），**多图多段**按输入顺序排列，严格按块序渲染。
2. 图片**不穿插在文本中央**：常见形态是「图上文下」或「文上图下」；穿插场景自动聚拢。
3. **编辑态**：单文本域合并所有文本块（图片块不可见），回车提交整段。
4. **编辑态 ⌘V 粘贴图片**：先提交文字（本次输入成为文本块），图片**追加到节点末尾**。
5. 图片块操作**最小集**：替换（双击）+ 删除（⌫）。
6. 块级 **UUID**（图片选中/删除/替换/Undo 按块 id 寻址）。

实现取舍（用户拍板）：
- `blocks` 唯一存储 + `text`/`image`/`imagePixelSize` **只读计算属性**（读取方零改动）。
- 编辑提交 **聚拢规则**：文本合并单块，图片按原相对顺序聚拢单侧。
- Markdown 导出图片文件名**改用块 id**（多图唯一名）。

## 1. 数据模型与 Codec v4

### 1.1 ContentBlock（新类型，`Model/ContentBlock.swift`）

```swift
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

- `BlockImage` 复用 Model 的 `ImagePixelSize`（尺寸类型唯一，不漂移）。
- 块 id：创建时生成（`appendImageBlock` / 迁移时）；替换保持 id 不变；删除后 Undo 恢复含原 id。
- 文本块 id 同样持久化（统一块模型；未来块级操作无需区分类型）。

### 1.2 Node 改造（`Model/Node.swift`）

```swift
var blocks: [ContentBlock]        // 唯一存储（取代 text/image/imagePixelSize 存储字段）

var text: String {                // 只读：文本块按序以 "\n" 连接
    blocks.compactMap { if case .text(let s) = $0.kind { s } else { nil } }.joined(separator: "\n")
}
var image: Data? {                // 只读：首个图片块
    blocks.compactMap { if case .image(let i) = $0.kind { i.data } else { nil } }.first
}
var imagePixelSize: ImagePixelSize? {  // 只读：与 image 同块
    blocks.compactMap { if case .image(let i) = $0.kind { i.pixelSize } else { nil } }.first
}
```

- `init(text:)` 保留：`blocks = [ContentBlock(id: UUID(), kind: .text(text))]` → 导入器（Markdown/OPML/FreeMind）、测试构造零迁移。
- 其余 init 参数（collapsed/side/fill/children）不变。
- **读方分类**：
  - 依赖「单值」的读方（搜索、编辑 draft、`NodeEditorOverlay`、测试断言 `.text`、导出标题文本）靠计算属性**零改动**；
  - 需要「遍历所有块」的读方（`TextMeasure` 尺寸合成、`RadialLayout` payload 收集、`MarkdownExporter` 图片清单、渲染）**改为遍历 `blocks`**（§4/§5）——这是本设计的主动改造点，不是兼容负担。
- **写入方**（`setText`/`setImage` 命令）改为块操作（§2）；`text` 只读后任何遗留写入在编译期报错，强制收敛，无静默漂移。

### 1.3 Codec v4（`Model/MindMapDocument.swift` + `Model/YMindCodec.swift`）

- `MindMapDocument.currentVersion = 4`。
- 迁移链追加：`if doc.version == 3 { doc.version = 4 }`（v1→v2→v3→v4 逐段抬升，零拒绝）。
- **Node 自定义解码 fallback**（`init(from:)`，在版本抬升链之前天然生效，不依赖版本号）：
  - 有 `blocks` key → 直接用；
  - 无 `blocks` key（v1/v2/v3 老文件）→ 从 `text` + `image`/`imagePixelSize` 合成：
    - 有图 → `[.image(新id, data, pixelSize), .text(text)]`（**图在上、文在下**，保持旧文件视觉）；
    - 无图 → `[.text(text)]`；
  - `imagePixelSize` 沿用现有容错（宽高非法/非有限 → nil）。
- encode：只写 `blocks`（不再写 `text`/`image`/`imagePixelSize` keys）；`[.prettyPrinted, .sortedKeys]` 稳定输出不变。
- `sanitize`：不动（块无 side 式层级约束；`side` 消毒规则不变）。
- 自动保存走同一 encode 路径，零改动。

## 2. 命令与会话

### 2.1 命令（`Commands/MindMapCommand.swift` + `Commands/CommandBus.swift` + `Model/MindMapModel.swift`）

**更替**：
- 删 `setText(id:old:new:)`（String）→ 新增 `setBlocks(id: UUID, old: [ContentBlock], new: [ContentBlock])`。
- 删 `setImage(ids:image:pixelSize:)`（批量单图覆盖）→ 新增三个块级命令。

**新增**：

```swift
case setBlocks(id: UUID, old: [ContentBlock], new: [ContentBlock])
case appendImageBlock(id: UUID, image: Data, pixelSize: ImagePixelSize)   // 末尾追加，生成新块 id
case replaceImageBlock(id: UUID, blockId: UUID, image: Data, pixelSize: ImagePixelSize)  // 块 id 不变
case removeImageBlock(id: UUID, blockId: UUID)                            // 删块；Undo 恢复原块
```

- `MindMapModel` 提供变更方法返回 Undo 所需数据：
  - `setBlocks(id:old:new:)` → no-op（old == new）返回 nil 不入栈；
  - `appendImageBlock` → 生成块 id 并返回之（redo 用同 id 重插，undo 按 id 移除）；
  - `replaceImageBlock` → 返回旧 `BlockImage` 供 undo；
  - `removeImageBlock` → 返回被删块（含 id）供 undo 按原下标恢复。
- 全部遵循 ymind-command 铁律：applyForward 返回 Entry(undo:redo:)，精确还原；no-op 不入栈；不改选中态（图片选中是会话态，§4.3）。

### 2.2 Session 入口（`Session/DocumentSession.swift`）

```swift
func commitEditingIfNeeded() -> Bool   // 改造：聚拢规则（§3.2）→ setBlocks
func appendPastedImage(from data: Data) -> Bool   // 归一注入 + appendImageBlock（替代 setPastedImage）
func replaceSelectedImage(from data: Data) -> Bool // 双击替换 → replaceImageBlock
func removeSelectedImageBlock()        // ⌫ → removeImageBlock
```

- 各入口先 `commitEditingIfNeeded()`（现状纪律：编辑中先提交再操作）。
- `setPastedImage(from:)` 更名/改语义：归一（注入不变）→ `appendImageBlock`。

## 3. 编辑态（问题 1 修复 + 聚拢规则）

### 3.1 CommitTextView 拦截 ⌘V（`App/NodeEditorOverlay.swift`）

```swift
override func paste(_ sender: Any?) {
    let pb = NSPasteboard.general
    let hasImage = pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil
    if hasImage, let onPasteImage {
        onPasteImage()          // 不调 super：图片粘贴走壳层
    } else {
        super.paste(sender)     // 纯文本 → 正常 NSTextView 粘贴
    }
}
```

- `CommitTextView` 增 `var onPasteImage: (() -> Void)?`；`NodeTextEditor`/`NodeEditorOverlay` 增同参；`ContentView` 传入 `paste`（既有闭包）。
- 系统 Edit 菜单 Paste、⌘V 键绑定都经 `paste(_:)` 进入 → 两条路径统一修复。
- 回调语义 = `ContentView.paste()`：先 `commitEditing()`（本次输入成文本块）→ 内部剪贴板优先 → 否则追加图片到选中节点末尾。满足「图片排文字后」。

### 3.2 聚拢规则（`commitEditingIfNeeded` 改造）

进入编辑（`beginEditing`）：
- `draftText = node.text`（计算属性 = 合并文本块，`\n` 连接）；
- `originalBlocks = node.blocks`（Undo 基线）。

提交：
1. `newText = draftText` 去首尾空白；空 → `"未命名"`（现状语义不变）。
2. 收集 `images = originalBlocks` 中全部图片块（按原相对顺序）。
3. 重组：
   - 原序列**首个非空块是图片** → `blocks = images + [.text(newText)]`（图上文下）；
   - 否则 → `blocks = [.text(newText)] + images`（文上图下）。
4. `commandBus.execute(.setBlocks(id: editingId, old: originalBlocks, new: 重组))`。

- 纯文本节点 → 退化为 `[.text(newText)]`，与现状行为一致（原 setText 语义）。
- 全图节点（无文本块，编辑态 draft 为空）→ 提交后 `[images] + [.text("未命名")]`（文本块始终存在，保 `node.text` 非空不变量）。
- 穿插形态（文-图-文）→ 自动聚拢为 `[text] + [images]`，与「图片不穿插在文字中央」取向一致。

### 3.3 非编辑态粘贴（现状升级）

`ContentView.paste()`：内部剪贴板优先（不变）→ 否则剪贴板含图片 → `appendPastedImage`（追加末尾，替代原 `setImage` 覆盖语义）。工具栏/⌘V 同路。

## 4. 布局 / 渲染 / 选中

### 4.1 NodeFrame（`Layout/LayoutSnapshot.swift`）

```swift
struct ImageBlockFrame: Equatable {
    let blockId: UUID
    let rect: CGRect        // 节点局部坐标，top-left 原点
}

// NodeFrame：
var imageRects: [ImageBlockFrame] = []   // 取代 imageRect: CGRect?
```

- `LayoutSnapshot.imagePayloads: [UUID: ImagePayload]`：key 从节点 id 改为**块 id**（Layout 遍历 node.blocks 拷出，Render 只消费 Snapshot——ymind-layout-snapshot 不变量 1 不变）。

### 4.2 尺寸合成（`Layout/TextMeasure.swift`）

按块序叠加：

```
块高：
  .text(s)  → 行数 × lineHeight（现状多行逻辑）
  .image(i) → wImg = min(pixelWidth, 300)；hImg = wImg × pixelHeight / pixelWidth
节点宽 = max(各文本块宽, 各图片块 wImg + padX×2)
节点高 = padY×2 + Σ块内容高 + (块数-1) × imageTextGap
```

- 纯文本节点退化为现状公式（零回归）；`LayoutConstants.imageMaxDisplayWidth` / `imageTextGap` 沿用。
- 图片块之间也用 `imageTextGap` 分隔。

### 4.3 渲染与命中

- `MetalRenderer.drawImage`：遍历 `frame.imageRects` 逐个绘制；视口剔除按各块世界 rect；`ImageTextureCache` 脏键 = 块 id + 显示尺寸 + 数据指纹（内容身份，沿 §4.1 旧设计）。
- PNG 导出：走同一管线，自动含多图。
- **命中**（`Render/CanvasHitTesting.swift`）：`hitTestImageRect` 返回 `(nodeId: UUID, blockId: UUID)?`（逐个块比对，先命中最上层/遍历序）。
- **图片选中态**：`DocumentSession.selectedImageBlock: (nodeId: UUID, blockId: UUID)?`（@Published，不入命令栈，同时最多一个；取代 `selectedImageId: UUID?`）。
  - 双击命中某图片块 → 设选中；双击文字区 → 照旧进编辑；
  - ⌫：`selectedImageBlock != nil` → `removeSelectedImageBlock()`；否则删节点（现状）；
  - Esc / 点空白 / 换选节点 → 退选；
  - 渲染选中描边：以该块 world rect 绘制（沿用现 imageRect 描边路径）。
- 框选/搬枝/搜索/内部剪贴板：不理图片块（图片语义 = 节点内容，块级操作只经图片选中态）。

## 5. 导出

### 5.1 Markdown（`Model/MarkdownExporter.swift`）

```swift
struct MarkdownImage: Equatable {
    let blockId: UUID     // 取代 nodeId；文件名 assets/<blockId>.png
    let data: Data
}
```

- `walk`：遍历每节点 `blocks`，每个图片块追加 ` ![图片](assets/<blockId>.png)` 尾缀并收集 `MarkdownImage`；文本块内容 = 合并文本（`node.text`）。
- `DocumentWorkflow` 导出：`images` 非空 → 文件夹包（`N/N.md` + `N/assets/<blockId>.png`）；无图 → 单文件不变（字节级兼容保持）。
- 折叠节点带图仍导出（walk 忽略折叠，纯结构遍历，不变）。

### 5.2 搜索

`node.text` 计算属性（合并文本块）→ 搜索零改动，命中即合并后文本。

## 6. 测试计划

| 层 | 测试 |
|---|---|
| Model / Codec | v4 往返（blocks 含多图）；v3 旧格式迁移（text+image → 图上文下 blocks）；v2/v1 链迁移；非法 imagePixelSize 容错；text 计算属性（合并/多块） |
| Command | setBlocks undo/redo（old/new 精确）；appendImageBlock undo（块 id 保留）redo（同 id）；replaceImageBlock undo（旧图）；removeImageBlock undo（原块+原下标）；no-op 不入栈 |
| Session | 聚拢规则：首块文 → 文上图下；首块图 → 图上文下；纯文本退化；全图节点保文本块；粘贴追加；⌫ 删块分派 |
| Layout | 多块叠加高度；块间 gap；图/文顺序几何；imageRects 命中 |
| Render | 多图纹理（脏键按块 id）；imageRects 遍历（手测）；PNG 含多图 |
| 导出 | Markdown 多图引用（多个 ![图片]）；文件夹包多 assets；无图单文件不变 |
| 编辑态 ⌘V | CommitTextView.paste 图片分支（剪贴板含图/纯文本两路）；回调触发 commit+append（逻辑层单测，NSTextView 覆盖手测） |
| 边界 | `scripts/check-boundaries.sh` 全绿（新增 import 进白名单）；CodecTests currentVersion=4 |

手测清单（渲染/编辑交互，`docs/架构现状.md` §7.4 基础上追加）：
- 编辑态 ⌘V 贴图 → 文字提交 + 图片在节点下方；编辑态 ⌘V 纯文本 → 正常文本粘贴；
- 双击图片块 → 替换；选中图片块 ⌫ → 删块、文字保留；⌘Z 恢复；
- 先贴图后输文 / 先输文后贴图 两种顺序；多图追加；Markdown 导出多图文件夹包。

## 7. 已知风险与接受项

1. **迁移后导出文件名变化**：v3 单图节点导出从 `<nodeId>.png` 变 `<blockId>.png`。内容无损，接受。
2. **`Node.text` 计算属性**：任何「写 text」的旧路径（如遗留 `setText`）会编译期报错 → 强制收敛到块操作，无静默漂移。
3. **编辑态图片不可见**：单文本域合并设计下，图片块在编辑时不可见、位置不可调——受「图片不穿插」取向约束，接受；块级重排（拖拽/上移下移）明确不做（§8）。
4. **snapshot Equatable 含 Data**：沿 v3 设计（COW 引用比较），仅 relayout 触发，接受。
5. **全图节点**：编辑态只显示空文本域；提交自动补「未命名」文本块。罕见，接受。

## 8. 明确不做

块级重排（拖拽/上移下移）；文本块插入/删除；图片自由缩放；图片块内多图并排；Markdown 图片导入；编辑态图片可见/占位符。
