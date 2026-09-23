# YMind PRD 附录（非需求正文）

本附录收纳**不宜写入 PRD 能力叙述**、但对实现与排期有用的上下文。需求真源仍是 `prd.md`。

## A. 技术方向（已讨论，待架构文档细化）

| 决策 | 内容 |
|------|------|
| 平台 | macOS 优先 |
| UI 壳 | SwiftUI（工具条、浮层编辑等） |
| 画布渲染 | Metal（`MTKView` 等）；布局在 CPU |
| 架构分层 | Model（树）→ Layout（中心辐射）→ View（Metal）+ Interaction |
| 文字编辑 | 叠 SwiftUI / AppKit 输入控件，不做 Metal IME |
| 工程形态 v1 | 单窗口；多文档后续再上 |

详见 `.agents/rules/ymind-apple-stack.md` 与 `.agents/AGENTS.md`。

## B. 原型对照

| 原型能力 | PRD |
|----------|-----|
| 工具条子主题 / 同级 / 折叠 / 删除 | FR-4–FR-8、FR-2 |
| 缩放、适应、拖拽平移 | FR-12、FR-13 |
| Tab / Enter / ⌫ | FR-14 |
| 左右侧自动分配 | FR-4、术语「侧」 |
| 预置示例树 | 仅便于演示；产品默认可为单中心主题（FR-3） |

原型路径：`prototype/`。

## C. 建议的下游文档

1. **架构说明**（Model / Layout / Metal 边界、命令与 Undo）
2. **UX 细节**（若与原型有视觉偏差时的决策记录）
3. **Epic / Story 拆分**（可对照 FR 编号）

可用后续流程：`bmad-architecture`、`bmad-create-epics-and-stories`（若已安装）。

## D. 竞争与参照（简述）

参照品类：XMind、MindNode 等 Mac 思维导图。YMind v1 **不对标功能全集**，只对标「中心辐射 + 快速建树 + 流畅画布」的核心体验，用于验证自研方向。
