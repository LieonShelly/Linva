# 设计文档：Linva 节点内嵌图片（图 + 文共存）

- **日期：** 2026-10-01
- **状态：** 设计定稿（待实现计划）
- **PRD：** `docs/prds/prd-linva-image-node-2026-09-30/prd.md`（+ `addendum.md`）
- **流程：** Superpowers brainstorming → 本 spec → writing-plans → 实现
- **方案：** A（图片像素随 `LayoutSnapshot` 下发）+ 显存三纪律（视口剔除 / 按需降采样解码 / LRU 上限）

## 0. 与 PRD 的偏差修正（实现以此 spec 为准）

| PRD 写法 | 仓库现状 / 本 spec 定案 |
|---|---|
| FR-G5「PNG / PDF 导出含图」 | PDF 导出已移除出产品范围；**只保证 PNG 含图** |
| Markdown 导出降级（忽略图片） | 用户拍板：**Markdown 也要含图**，以文件夹包交付（见 §5） |
| FR-G6「与迁移闭环并行开发」 | 导入闭环已并入 main，无并行终端；接缝清单作废，`currentVersion` 无冲突方 |
| FR-G2「⌫ 清除图片」 | ⌫ 已占用为删除节点；改为**图片级选中态 + 选中图片时 ⌫ 清图**（见 §5.2） |
| FR-G3「折叠后图片随节点显示」保留 | 保留（折叠节点自身的图仍显示；后代不进 frames） |

用户拍板的三个决策（2026-10-01 会话）：
1. 导出 **PNG 与 Markdown 都含图**。
2. Markdown 有图 → 文件夹包；无图 → 保持单文件导出。
3. 图片是节点内可独立选中的子元素：**单击选节点（现状），双击图片区域选图片**（圆角描边高亮），选中图片时 ⌫ 只清图、节点保留。

## 1. 数据模型与 Codec v3（FR-G1）

### 1.1 Node 扩展（`Model/Node.swift`）

```swift
var image: Data?                     // 归一后的 PNG bytes；缺省 nil
var imagePixelSize: ImagePixelSize?  // 归一器写入的像素尺寸

/// Model 内自有类型：CGSize 在 `import Foundation` 下不可 Codable（实测 swiftc 报错），
/// Model 白名单又禁 CoreGraphics，故用最小自有序列化结构；Layout/Render 边界再转 CGSize。
struct ImagePixelSize: Codable, Equatable, Sendable {
    let width: Double   // > 0
    let height: Double  // > 0
}
```

- 存 `imagePixelSize` 的理由：Layout 只读尺寸，不解析 PNG 头；两字段由归一器保证一致；decode 容错后仍可布局。
- 自定义解码器（`init(from:)`）追加 `decodeIfPresent`，同 `fill` 先例：
  - `image = try c.decodeIfPresent(Data.self, forKey: .image)`
  - `imagePixelSize`：`decodeIfPresent` + 校验（宽高均 > 0，非法视为 nil）。
- **容错语义**：JSON 结构损坏 → 整体拒文件（JSON 原子性，现状）；`image` 是合法 base64 但非图片字节（decode 成功）→ 渲染侧纹理解码失败按无图显示，不崩、不拒文件。
- `Equatable`/`Sendable` 语义随值类型自动成立（Node 现状未声明 Hashable，不引入）。

### 1.2 Codec v3（`Model/MindMapDocument.swift` + `Model/LinvaCodec.swift`）

- `MindMapDocument.currentVersion = 3`。
- 迁移链追加：`if doc.version == 2 { doc.version = 3 }`（v1→v2→v3 逐段抬升，符合 linva-codec-version 技能；v1 老文件先抬 v2 再抬 v3，零拒绝）。
- `sanitize` **不动**：image 无 side 式层级约束。
- Codec **不做压缩/校验**：归一在数据入口（§2）完成，Codec 只信 Model。
- 自动保存（`AutosaveStore.write`）走同一 encode 路径，图随副本落盘，无需改动。

### 1.3 图片归一器（新文件 `App/ImageNormalizer.swift`）

```swift
enum ImageNormalizer {
    /// 输入任意图片数据 → 输出受控 PNG bytes；无法解码/超限 → nil
    static func normalize(_ data: Data) -> (data: Data, pixelSize: ImagePixelSize)?
}
```

流程：CGImageSource 解码 → gif 取首帧 → 最长边 > 1024px 等比缩 → PNG 编码 → 若 > 5MB 再降到 512px → 仍超限返回 nil（调用方状态提示，不入栈）。

- **放 App 层**：需要 ImageIO/AppKit；`Model` 只许 Foundation、`Session` 无 AppKit/ImageIO——需 `import ImageIO`（CGImageSource 属 ImageIO 而非 AppKit/CoreGraphics）；按仓库规约把 ImageIO 加入 App 白名单并同步 §5 记录。
- 产出同时带 `pixelSize`（CGImageSource 属性，不二次解码）。
- **Session 适配**（`Session/DocumentSession.swift`）：Session 白名单无 AppKit/ImageIO，归一器以**闭包注入**保持 Session 可单测——Session 声明 `var imageNormalizer: (Data) -> (data: Data, pixelSize: ImagePixelSize)?`（默认空实现返回 nil），App 层组合根（`LinvaAppApp`/`ContentView` 构建 Session 处）赋值 `ImageNormalizer.normalize`。入口 `func setPastedImage(from data: Data) -> Bool`：归一成功 → `setImage` 入栈返回 true；失败返回 false，壳层状态提示「无法读取图片」。

## 2. 命令与会话（FR-G2）

### 2.1 命令（`Commands/MindMapCommand.swift` + `Commands/CommandBus.swift` + `Model/MindMapModel.swift`）

- 单命令双用途：`case setImage(ids: [UUID], image: Data?, pixelSize: ImagePixelSize?)`，`image: nil` 即清除（pixelSize 同置 nil）。
- 仿 `setFill` 先例：
  - `MindMapModel.setImage(ids:image:pixelSize:)` 返回 `[(id: UUID, oldImage: Data?, oldPixelSize: ImagePixelSize?)]` 供 Undo；无实际变化（旧值相等）不入栈；**不改选中态**。
  - CommandBus 落 Undo/Redo 闭包对，一步撤销回上一张（或清除前状态）。

### 2.2 Session 入口（`Session/DocumentSession.swift`）

```swift
func setImage(_ image: Data?, pixelSize: ImagePixelSize?)   // nil = 清除（selectedImageId 优先级见 §5.2）
func setPastedImage(from data: Data) -> Bool                // 归一(§1.3 注入) + 入栈；失败 false 由壳层提示
```

- `setImage` 先 `commitEditingIfNeeded()`（PRD 开放问题 5 定案：编辑中先提交文字再贴图，避免 IME 冲突），再入命令栈。
- 粘贴 = 替换 = 同一 `setImage` 覆盖；⌘Z 一步回上一张。
- 图片数据入口统一走 `setPastedImage(from:)`（归一注入与失败提示见 §1.3）；⌘V 优先级见 §5.1。

## 3. 布局（FR-G3，`Layout/`）

### 3.1 尺寸合成（`Layout/TextMeasure.swift`）

`TextMeasure.size(for:isRoot:)` 读 `node.imagePixelSize`（转 `ImagePixelSize → CGSize` 只读数值，不解码 PNG；Layout 白名单含 CoreGraphics，但为防「改了图没改尺寸」漂移，尺寸**只从 `imagePixelSize` 取**，不从 Data 解析）：

```
wImg = min(pixelWidth, 300)                     // 显示宽度上限 300pt（PRD 假设值定案）
hImg = wImg × pixelHeight / pixelWidth          // 等比，不裁切
节点宽 = max(文字宽, wImg + padX × 2)
节点高 = 文字高 + 6(图文间距) + hImg
```

- `imagePixelSize == nil` → 公式退化为现状（零回归）。
- 上限 300pt 收进 `LayoutConstants.imageMaxDisplayWidth: CGFloat = 300`，图文间距 `imageTextGap: CGFloat = 6`。

### 3.2 Snapshot 契约扩展（`Layout/LayoutSnapshot.swift` + `Layout/RadialLayout.swift`）

- `NodeFrame` 增：`imageRect: CGRect?` —— 图片区在**节点局部坐标**的矩形（图在上、文字在下；宽度撑满内容区、高度 hImg）。
- `LayoutSnapshot` 增：`imagePayloads: [UUID: ImagePayload]`，`struct ImagePayload: Equatable { let pixelSize: ImagePixelSize; let data: Data }`（复用 Model 的 `ImagePixelSize`，避免第二套尺寸类型漂移）。
- `RadialLayout.layout` 为有图节点填两字段（Layout 只读 Model，合规；对齐 linva-layout-snapshot 不变量 4「渲染需要的信息先进 Snapshot」）。
- 不变量保持：折叠后代不进 `frames`（零纹理免费成立）；命中/选中/搜索仍走节点 AABB；`LayoutSnapshot.Equatable` 自动含新字段（Data 为 COW 引用比较，memcmp 成本仅 relayout 时发生）。

## 4. 渲染（FR-G4，`Render/`）

### 4.1 ImageTextureCache（新文件 `Render/ImageTextureCache.swift`）

- 脏键 = 节点 id + 显示像素尺寸（frame `imageRect` × displayScale 量化）+ scale 桶（复用 `rasterBucket` 思路）+ 数据指纹（**内容身份**：命中 O(1) baseAddress/count 比对，条目持有 Data 锁定缓冲区；miss 重建时才算 FNV-1a 全哈希并 memoize）。不用「字节数 + 首尾 8 字节」——本应用图片全为 PNG，prefix/suffix 恒为文件签名/IEND 尾，等长替换会全碰撞显示旧图；也不用 `Data.hashValue`（实测只取前缀字节）。
- **LRU 字节预算 128MB**（按 `width×height×4` 记账），超限逐最久未用条目；回屏时重建（毫秒级）。
- **解码即降采样**：`CGImageSourceCreateThumbnailAtIndex(kCGImageSourceCreateThumbnailFromImageAlways + maxPixelSize)` 按「显示尺寸 × displayScale」出图（200pt@2x = 400px 纹理，非 1024px 原图）——显存较原图路径降 4~6×。
- 解码失败（数据非法）→ 返回 nil，该节点按无图显示（降级不崩）。
- 上传复用 `TextTextureRasterizer`：同格式 CGContext 绘制 CGImage → **保留 `flipVertically` 行翻转**（linva-render-text 纪律，禁止删除）→ `makeTexture`。

### 4.2 绘制路径（`Render/MetalRenderer.swift`）

- `encodeContent` 在「节点底色之后、文字之前」插 `drawImage`：有图 frame 逐个处理。
- **视口剔除**：图片世界 rect（`frame.rect + imageRect`）与相机视口不相交 → 跳过（连纹理都不建——「屏幕外无图」）。
- 纹理 quad 走既有 `texturedPipeline`/`texturedQuad` 路径；不新增 shader。
- **PNG 导出零改动自动含图**：`PNGExporter → RadialLayout.layout → MetalRenderer.renderImage(encodeContent)`，导出视口 = 内容包围盒，图全可见全绘制。

## 5. 交互与导出（FR-G2 / FR-G5 修订版）

### 5.1 粘贴 / 拖入

- **⌘V 优先级**（`ContentView.paste` → Session）：① `session.clipboard`（内部节点剪贴板）存在 → 节点粘贴（现状）；② 否则剪贴板含图片类型（png/tiff 等 `NSPasteboard.PasteboardType`）且有选中节点 → 归一 → `setImage`；③ 都无 → 无操作。
- **拖入**（`Render/CanvasMetalView.swift` 的 `NSDraggingDestination`）：**独立分支**，不并入 `DropIntent`（图片拖入 ≠ 搬枝）；drop 点 `hitTestNode` 命中节点 → 归一 → `setImage`；空白/非图片文件忽略。注册类型 png/jpeg/gif/tiff/heic。
- gif 取首帧；拖图片到空白画布忽略（PRD 开放问题 3 定案）。

### 5.2 图片级选中（决策 #3）

- 状态：`DocumentSession.selectedImageId: UUID?`（@Published，**不入命令栈**，同选中态纪律；同时最多一个）。
- **双击命中 `frame.imageRect` → 设 `selectedImageId`；双击文字区 → 照旧进文字编辑；单击 → 永远选节点（现状）。**（见 §5.2）
- 视觉：图片圆角描边高亮（复用选中描边 pass 的绘制模式，以 `imageRect` 为矩形）。
- **⌫ 分派**（修订 FR-G2）：`selectedImageId != nil` → `setImage(nil)` 一步撤销；否则现状删除节点。清图后 `selectedImageId` 回落 nil（选中回节点）。
- 点空白 / Esc → 清 `selectedImageId`。框选、搬枝、搜索、复制剪贴板均不理图片（图片语义 = 节点属性）。

### 5.3 导出

- **PNG**：§4.2 管线自动含图。
- **Markdown 含图**（决策 #1/#2）：`MarkdownExporter` 现签名 `markdown(from:) -> String` 只能产纯文本，需扩展为产出「正文 + 逐节点图片清单」：
  - 新增返回结构：`struct MarkdownOutput: Equatable { let text: String; let images: [MarkdownImage] }`，`struct MarkdownImage: Equatable { let nodeId: UUID; let data: Data }`；保留旧 `markdown(from:) -> String` 语义为「output.text 当无图时」的便捷重载，既有调用与测试零迁移。
  - `walk` 产出正文时对有图节点在行内尾缀追加 ` ![图片](assets/<nodeId>.png)`；
  - `DocumentWorkflow` 导出时检测 `images` 非空：**有图** → NSSavePanel 输入名称 N → 文件夹包 `N/N.md` + `N/assets/<nodeId>.png`（归一 PNG bytes 直接落盘）；**无图** → 现状单文件导出路径不变（正文无尾缀，与现状字节级一致）。
  - `MarkdownExporter.walk` 本就忽略折叠（纯结构遍历），折叠节点带图也导出。
- **导入器不动**（Markdown 图片导入是 PRD 明确非目标）。

## 6. 测试计划

| 层 | 测试 |
|---|---|
| Model / Codec | v3 encode→decode 往返（含图）；v2 老文件零拒绝（无 image 字段）；v1 链式迁移；非法 `imagePixelSize` 容错 |
| 归一器 | png/jpeg/heic/tiff→PNG；gif 首帧；>1024 缩边；>5MB 二级压缩；非图片数据 → nil |
| Layout | 合成公式（有图/无图/上限 300pt）；混排不重叠；折叠后代零 frame；imageRect 几何 |
| Render | 纹理脏键命中/失效；LRU 驱逐；视口剔除（屏幕外不建纹理）；降采样尺寸正确 |
| Session / Command | setImage Undo/Redo 一步；no-op 不入栈；多目标；selectedImageId 不入栈；⌫ 分派 |
| 导出 | Markdown 有图 → 文件夹包 + 引用路径正确；无图 → 单文件不变；PNG 含图（真渲染） |
| 边界 | `scripts/check-boundaries.sh` 全绿（零新增 import）；`CodecTests` 版本用例更新 currentVersion=3 |

渲染最终效果（Retina 清晰度、图文同框视觉）按 `docs/架构现状.md` §7.4 手测清单目测验证。

## 7. 已知风险与接受项

1. **自动保存体积**：每次全量重写 JSON，图多后副本变大——2s 防抖已存在，v1 接受。
2. **snapshot Equatable 含 Data**：memcmp 仅 relayout 触发；实测劣化再引入 generation 号（预留，不实现）。
3. **显存**：三纪律（视口剔除 / 降采样 / LRU 128MB）后，典型视口 <10 张可见 ≈ 10-40MB。
4. **未命名文档图片**：随 autosave 副本落盘，与文字同待遇，无特殊处理。

## 8. 明确不做（对齐 PRD §5）

图片 URL/网络图；多图节点；标注/裁剪/滤镜（压缩上限除外）；视频/音频/附件；Markdown 图片导入；拖图新建节点；图片自由缩放拖拽；动图播放。
