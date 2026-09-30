# Addendum：迁移闭环 — 实现侧细节（不进 PRD 主线）

**所属 PRD：** `docs/prds/prd-ymind-import-export-2026-09-30/prd.md`
**日期：** 2026-09-30
**读者：** 开发 Agent / 方案设计（specs → plans）

---

## 1. Markdown 导入语法约定（FR-I1 细则）

导出语义（`MarkdownExporter`）：先序整树 → 深度 d → `min(d,6)` 个 `#`，多行压单行，空文案「未命名」。
导入语义与其对称，另有列表支持：

- **标题行**：`^#{1,6}\s+(.*)$` → 深度 = `#` 个数（>6 收敛为 6 级子树最深点）。
- **列表行**：`^\s*[-*•]\s+(.*)$` → 视为**当前最近标题**的子节点；连续列表项互为同级。
- 首个标题 = 根；首个标题之前的碎片内容（非标题非列表）忽略。
- 任何标题层级跳变（如 `#` 直接到 `###`）不报错：按实际深度挂树（缺层即直连）。
- 行内 Markdown 语法（`**`、`[链接](…)`、`` ` ``）不做解析，原文保留为节点文案。
- 空标题 / 空列表项 → 节点文案「未命名」。

**歧义裁决**：`-` 列表项若出现在「首个标题之前」且无任何标题 → 整文件报「未识别为导图大纲」。

## 2. OPML / FreeMind 映射（FR-I2 细则）

| 源 | 节点 | 文案字段 | 容错 |
|----|------|----------|------|
| OPML | `<outline>` 嵌套 | `text`（空→「未命名」） | `_note`/其它属性忽略；空根 → 报错 |
| FreeMind | `<node>` 嵌套 | `TEXT`（空→「未命名」） | 坐标/图标/富文本属性忽略；非法 XML → 报错 |

两者共用同一个「解析 → `MindMapDocument` → 载入新文档」管线；仅解析器不同（可注册为 `DocumentImporter` 协议，XMind 后续注册进同一张表）。

## 3. PDF 导出管线（FR-E1 细则）

复用 `PNGExporter` 已验证的「复制文档 → 清空折叠 → 布局 → 离屏」流：

1. 复制当前文档，全部 `collapsed = false`（不改原文档、不入 Undo）。
2. `RadialLayout` + `TextMeasure` 出 `LayoutSnapshot`（含 `NodeFrame.fill`）。
3. 按包围盒（+padding）分页：横向 A4 物理宽度 → 每页一段宽度；高度超出则纵向续页。**默认：横向 A4，按宽度分页；「缩放单页」模式整树缩至一页。**
4. 绘制：CG PDF Context（`CGContext(consumer:mediaBox:)`）+ CoreText 画矢量文字 + 复用节点/连线绘制语义；纸色背景（`#e7e4dc`，与 PNG 一致）。
5. 范围=选中枝：先取子树子图再布局，语义同「以该节点为根的子图」。
6. 文件名：`ExportNaming.safeFilename(主题)` + `.pdf`；Save Panel。

**导出范围语义**：「全部」= 整棵逻辑树；「当前选中枝」= 选中节点的子树（多选时禁用该选项或取锚点子树——实现时定，默认：多选禁用）。

## 4. 自动保存 / 恢复约定（FR-S1/S2 细则）

- **目录**：`FileManager.default.urls(for: .applicationSupportDirectory)`/`Unsaved/<docID>.ymind` + 同名 `.meta.json`（原 URL、docID、最后保存时间、修改计数）。
- **触发**：`commandBus` 变更 → Session 记 `dirtyRevision` → 2s 防抖 → 写副本；正常保存（save/saveAs）成功后删副本。
- **启动扫描**：`DocumentWorkflow` 入口（`applicationDidFinishLaunching` 前）扫描 `Unsaved/`；有副本 → 恢复横幅。
- **恢复**：载入副本 JSON 为文档，置 `isDirty = true`；忽略 → 删副本，回到正式保存版本。
- **未命名文档**：无正式 URL 也可产生副本（docID = 内存 UUID），恢复时作为新文档打开。
- **多副本**：只提示最新一份；其余按保留策略清理（默认：仅本次会话产生的副本参与提示，历史残留由「忽略后清理全部」兜底）。

## 5. 层边界清单（FR-C1 落地）

| 新增件 | 层 | import 白名单 |
|--------|-----|---------------|
| Markdown 导入解析器 | Model | `Foundation`（现有白名单） |
| OPML/FreeMind 解析器 | Model | `Foundation` |
| `DocumentImporter` 注册表 | Model | `Foundation` |
| PDF 导出 | Render（离屏） | AppKit / CoreGraphics / MetalKit（已在白名单） |
| 自动保存 + 恢复横幅 | Session + Shell | Combine / SwiftUI / AppKit |

`scripts/check-boundaries.sh` **无需新增 import 白名单**；若实现时发现需要（如 Model 里碰 XML → XMLParser 属 Foundation，安全），先改脚本白名单再动代码（构建期校验会红，勿绕过）。