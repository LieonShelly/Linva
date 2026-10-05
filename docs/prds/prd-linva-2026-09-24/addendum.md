# Linva PRD 附录（非需求正文）

本附录收纳**不宜写入 PRD 能力叙述**、但对实现与排期有用的上下文。  
需求真源：

- v1：`prd.md`（本目录）
- 整理效率增量：`../prd-linva-organize-2026-09-25/prd.md`
- 搬枝增量：`../prd-linva-move-2026-09-25/prd.md`
- 同级排序增量：`../prd-linva-reorder-2026-09-25/prd.md`
- 搜索定位增量：`../prd-linva-search-2026-09-25/prd.md`
- 手动改侧增量：`../prd-linva-side-2026-09-25/prd.md`
- 节点轻填色增量：`../prd-linva-style-2026-09-25/prd.md`
- 导出增量：`../prd-linva-export-2026-09-25/prd.md`

## A. 技术方向（已讨论，待架构文档细化）

| 决策 | 内容 |
|------|------|
| 平台 | macOS 优先 |
| UI 壳 | SwiftUI（工具条、浮层编辑等） |
| 画布渲染 | Metal（`MTKView` 等）；布局在 CPU |
| 架构分层 | Model（树）→ Layout（中心辐射）→ View（Metal）+ Interaction |
| 文字编辑 | 叠 SwiftUI / AppKit 输入控件，不做 Metal IME |
| 工程形态 v1 | 单窗口；多文档后续再上 |
| 选中模型升级 | `selectedId` → `Set` / 选中集；见整理效率 PRD 与 `docs/架构现状.md` |

详见 `.agents/rules/linva-apple-stack.md` 与 `.agents/AGENTS.md`。

## B. 原型对照

| 原型能力 | 文档 |
|----------|------|
| 工具条子主题 / 同级 / 删除 | v1 FR-4–FR-7、FR-2（修订后无折叠按钮） |
| 分叉处 ＋折叠 / −N 展开 | 整理效率 FR-O9、FR-O10 |
| ⌘ 加减选 · Shift 同父连选 · 框选 | 整理效率 FR-O1～O4 |
| 空格+拖平移 · 默认空白拖框选 | 整理效率 FR-O5 |
| 多选「已选 N」+ 严格工具条 | 整理效率 FR-O7 |
| 批量删除 | 整理效率 FR-O8 |
| 拖节点到目标成子 | 搬枝 FR-M1～M5 |
| 拖上下边插同级（分区命中） | 同级排序 FR-R1～R6 |
| ⌘F 浮层搜索 · 整树命中跳转 | 搜索定位 FR-S1～S5 |
| ⌘←/→ · 拖过中心 / 中心左右半改侧 | 手动改侧 FR-L1～L5 |
| 工具条色点轻填色（五色 + 默认） | 轻填色 FR-C1～C5 |
| 导出 PNG（全展开）/ MD（标题层级） | 导出 FR-E1～E4 |
| ⌘C / ⌘X / ⌘V 粘贴成子 | 搬枝 FR-M6～M9 |
| 缩放、适应 | v1 FR-12、FR-13 |
| Tab / Enter / ⌫ | v1 FR-14；多选时 Tab/Enter 无效（FR-O7） |
| 左右侧自动分配 | v1 FR-4、术语「侧」 |
| 预置示例树 | 仅便于演示；产品默认可为单中心主题（FR-3） |

原型路径：`prototype/`。

## C. 建议的下游文档

1. **架构说明**（选中集、分叉控件命中、命令栈批量删除 / 搬枝）— 可更新 `docs/架构现状.md`
2. **Epic / Story 拆分**（对照 FR-O*、FR-M*）
3. 原型阶段能力已含导出；后续可开「导入 MD」或原生壳打磨
4. **注意：** 原型中 ⌘F 已改为搜索；「适应」仅工具条（原生菜单可另绑快捷键）
5. 原生 UI 视觉打磨可等功能原型收齐后再做（产品决策）

可用后续流程：`bmad-architecture`、`bmad-create-epics-and-stories`（若已安装）。

## D. 竞争与参照（简述）

参照品类：XMind、MindNode 等 Mac 思维导图。Linva **不对标功能全集**。  
折叠控件极性（＋=折叠）与部分竞品相反，以整理效率 PRD 拍板为准，不对齐竞品为目的。
