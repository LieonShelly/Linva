# Addendum：节点内嵌图片 — 实现侧细节（不进 PRD 主线）

**所属 PRD：** `docs/prds/prd-ymind-image-node-2026-09-30/prd.md`
**日期：** 2026-09-30
**读者：** 开发 Agent / 方案设计（specs → plans）；**与迁移闭环并行开发，先读 §5 接缝清单。**

---

## 1. 图片归一与体积上限（FR-G1 细则）

- **格式归一**：粘贴/拖入 → `NSBitmapImageRep` / `CGImageSource` 统一转 **PNG**（heic/tiff/gif 均转；gif 取首帧）。
- **压缩上限**：最长边 > 1024px 等比缩小；编码体积 > 5MB 则进一步压（或拒绝并提示，实现时定）。目标：`.ymind` 单图 ≤ ~3MB base64，防文件/显存膨胀。
- **存储**：`Node.image: Data?`（PNG bytes，base64 进 JSON）。Codable 内建编码 Data → base64，无需自定义。
- **容错**：decode 时 `image` 数据损坏/非法 → 视为无图（`nil`），不崩、不拒文件。
- **Codec v3 迁移**：`currentVersion = 3`；decode 时 `version == 2 → 3`（仅版本号升迁；`image` 缺省 nil，Node 解码器对缺失字段天然容错——同 fill 先例）。**注意：v1 → v2 迁移已存在，v2 → v3 在其后追加。**

## 2. Layout 尺寸合成（FR-G3 细则）

`NodeSize` 计算（在现有 `TextMeasure` 量字结果上扩展）：

```
图片显示宽 wImg = min(图片原始宽, 上限 300pt)
图片显示高 hImg = wImg * (原高 / 原宽)          // 等比，不裁切
节点宽 = max(文字宽, wImg + 2×内边距)
节点高 = 文字高 + hImg + 内边距
```

- `NodeFrame` 新增：`image: NodeImageInfo?`（`{textureRef/尺寸, displaySize}`）——**Render 只消费尺寸 + 纹理引用，不懂图片数据**（延续「Render 只吃 Snapshot」纪律）。
- 折叠：有图节点折叠后后代不占空间（同现状），图片随节点本身显示。
- 命中/选中：沿用现有 AABB（节点框变高不影响命中逻辑）。

## 3. 图片纹理渲染（FR-G4 细则）

复用 `TextAtlas` 的「CPU 栅格化 → `MTLTexture` → quad 采样」模式：

- 新增图片纹理缓存（可并入 `TextAtlas` 或并列 `ImageTextureCache`）：脏键 = 节点 id + 图片字节哈希 + 显示尺寸 + scale；图片未变不重建。
- 上传：`CGImage` → bitmap（`TextTextureRasterizer.makeBitmap` 可复用或新增 RGBA 路径）→ `MTLTexture`（与文字纹理同格式）；**保留 `flipVertically` 语义**（首行=顶边，避免颠倒）。
- 绘制：节点框内图片 quad 与文字 quad 分区域（图在上、文字在下，或图占上方区域——实现时定，默认图在上、文字在下）。
- 缩放平移：相机只改 quad 世界坐标，纹理不复传；Retina 用 `displayScale`（与文字路径一致）。

## 4. 命令与交互（FR-G2 细则）

- 新命令：`setImage(ids:id, image: Data?)`（`image = nil` 即清除）——**一步 Undo、no-op 不入栈、不改选中态**（仿 `setFill` 先例，见 `MindMapCommand.swift`）。
- 粘贴：`NSPasteboard.general` 读 `png` / `tiff` 类型 → 归一 → `session.setImage(...)`。
- 拖入：`NSDraggingDestination` 命中节点（复用 `DropIntent` 或单独分支）——建议**独立分支**（图片拖入 ≠ 搬枝），避免污染 `DropIntent.resolveDropIntent`。
- 菜单：选中节点右键 / 工具条（可后置）「粘贴图片 / 清除图片」；快捷键 ⌘V（粘贴优先级：编辑态→文字，非编辑态→图片，无图可贴时忽略）。

## 5. 并行接缝清单（与迁移闭环，先读）

| 共享点 | 迁移闭环（另一终端） | 图片功能（本增量） | 接缝 |
|--------|---------------------|--------------------|------|
| `YMindCodec.currentVersion` | 保持 2（明示不加字段） | **升 3** | 版本号独占升迁；合并前两者互不改对方版本逻辑 |
| `LayoutSnapshot` / `NodeFrame` | PDF 导出复用 Snapshot | 扩展尺寸合成 + `image` 信息 | 以 Snapshot 契约为界：PDF 读 `NodeFrame` 自动含图 |
| `NodeSize` 计算 | 不动 | 扩展合成公式 | 图片功能改 `NodeSize`；PDF 布局自动继承 |
| Render `encodeContent` | 抽 `renderImage`（PDF/PNG 共用） | 加图片 quad | 图片绘制作为新增 quad 并入共用绘制体，不动既有文字路径 |
| `check-boundaries.sh` | 白名单不变 | **不新增 import** | 各自保持白名单绿；合并后一起校验 |
| 文件 | 同一 main 分支 | 独立分支基于 main | 建议以迁移闭环合并后 main 为基线开分支，避免 Layout/Render 重复改动冲突 |

**合并顺序建议**：迁移闭环先行合并 main → 图片功能 rebase 其上 → 一起过 `check-boundaries.sh` + 全量单测。

## 6. 测试建议

- Model：Codec v3 往返（含图节点）、v2 老文件打开（无图容错）、图片上限压缩逻辑。
- Layout：有图/无图混排不重叠、显示宽度上限等比、折叠/命中不受影响。
- Render：图片纹理 Retina 对齐（与文字路径同法）、脏键重建（图变才重传）。
- 交互：⌘V 粘贴、拖入归一、替换/清除、撤销。
- 导出：PNG/PDF 含图（走真 Metal / 真渲染）、MD 纯文字。
- 边界：`check-boundaries.sh` 全绿。