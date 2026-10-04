---
title: YMind — Node 连线样式（曲线 / 大括号 / 正交折线，全局一键切换）
status: final
created: 2026-10-04
updated: 2026-10-04
skill: bmad-prd (Fast path)
inputs:
  - docs/pm/opportunities/2026-10-04-连线样式.md（机会卡片 = 需求真源，FR-E1…E5）
  - prototype/edge-style.html（交互线框：三种样式渲染 + 切换，浏览器 + vision 已实测）
  - docs/pm/research/2026-10-04-连线样式.md（竞品证据 + 架构约束）
  - docs/prds/prd-ymind-2026-09-24/prd.md（v1 主 PRD）
follow_on:
  - 连线动画/箭头端头/粗细/颜色（独立课题）；按分支/按节点设样式（本增量全局一种，后置）
---

# PRD：YMind — Node 连线样式（曲线 / 大括号 / 正交折线）

## 0. 文档目的

本文描述连线能力增量：**父-子结构连线支持三种可切换样式（正交折线 / 曲线 / 大括号），全局一种、工具栏一键切换、即时重绘、无损（选中/折叠/相机不动）、随文档持久化**。产品本人访谈确认动机 = **视觉打磨 + 语义分层两者都要**；作用域 = 全局一种。**样式随 `.ymind` 持久化、切换入命令栈（⌘Z 可撤销）**——此为产品本人拍板（原「会话态、不持久化」决策已推翻）。决策「做」（ICE 8.0，含持久化成本）。

- **上游：** [v1 PRD](../prd-ymind-2026-09-24/prd.md)
- **需求真源：** [机会卡片](../../pm/opportunities/2026-10-04-连线样式.md)（FR 编号 E1…E5 与卡片一致）
- **体验真源：** `prototype/edge-style.html`（三种样式切换器 / 语义说明 / 边界）
- **明确不在本增量：** 样式持久化 / Undo；按分支/按节点设样式；连线动画/箭头/粗细/颜色；联系线 Relationship；因样式调整布局。

文档语言：中文优先。

---

## 1. 愿景与要完成的工作

YMind 父-子连线当前是**正交折线**（`EdgeGeometry.points` 的 3 段折线：横出 → 竖落 → 横进），既非直线也非曲线。竞品（MindNode / Miro / SimpleMind / XMind / MindNoodle）的连线样式是成熟度基线——几乎全部支持、且几乎全部是**全局一种**作用域。用户想要两种价值：

- **视觉打磨**：曲线更顺滑专业，对齐成熟竞品观感，消除正交折线的生硬感。
- **语义分层**：大括号（`}`）直观表达「总分 / 从属」关系（对齐 XMind 括号图），帮读者一眼看懂结构。

核心洞察：**连线形态是「同一份数据、换一种读法」的低成本手段**——只换连线几何，不动数据、不动布局算法、不动节点排布，一键切换、即时重绘、无损。

三条主链路：
- **换样式：** 工具栏「连线样式」菜单，曲线 / 大括号 / 正交折线 一键切换，整图即时重绘。
- **无损：** 切换只影响连线形态；选中节点、折叠分支、相机视角全部保持。
- **记得住：** 样式随文档持久化（.ymind 编码），重新打开保持上次选择；切换入命令栈（⌘Z 可撤销）。

成功标准（SM 见 §6 语境）：阿哲能在工具栏一键把整图连线切成曲线或大括号，观感专业、结构语义清晰，切换过程不丢任何视图状态。

## 2. 关键用户旅程

**UJ-E1. 阿哲把一张辐射导图切成曲线观感。**

1. 打开一份头脑风暴导图（默认正交折线）；2. 工具栏 → 连线样式 → 曲线；3. 全图连线立即重排为平滑曲线；4. 选中的节点、折叠的分支、相机视角保持不动；5. 觉得还是折线清爽，一键切回。

**UJ-E2. 阿哲用大括号表达一份读书笔记的总分结构。**

1. 打开《认知觉醒》笔记（辐射布局）；2. 工具栏 → 连线样式 → 大括号；3. 根到主分支连线变为 `}` 括号，主分支到子节点为 `∪` 杯形括号，总分从属关系一目了然；4. 保存文件；5. 隔天再打开，画布直接以**上次的大括号样式**呈现（无需重切）。

**UJ-E2b. 阿哲切错了想撤回。**

1. 切到大括号后觉得不对；2. ⌘Z 撤销，回到上一样式（曲线或正交折线）；3. 选中与相机保持。

**UJ-E3. 阿哲切换样式时不想被打断。**

1. 当前选中一个深层节点、相机缩放中；2. 切换连线样式；3. 选中与相机视角原样保持，仅连线形态变化——切换不重设选中、不重置视图。

## 3. 术语表（增量）

| 术语 | 定义 |
|------|------|
| **连线样式（EdgeStyle）** | 父-子结构连线的形态。本增量三种：`elbow` 正交折线（默认）/ `curve` 曲线 / `brace` 大括号。**文档属性**，随 `.ymind` 持久化，切换入命令栈。 |
| **正交折线（elbow）** | 现状默认：父边缘横出 → 竖落 → 横进（3 段折线）。 |
| **曲线（curve）** | 父→子平滑贝塞尔弧线；水平边带垂直隆起（避免两端同高时退化成直线），垂直边沿轴向平滑过渡。 |
| **大括号（brace）** | `}` 形括号：根→主分支为朝子开口的 `}`，主分支→子节点为 `∪` 杯形括号；强表达总分/从属。 |
| **全局一种** | 样式作用于整张图所有父-子连线，不可按分支/按节点单独设。 |

## 4. 功能需求

### 4.1 样式模型与持久化

**描述：** 新增 `EdgeStyle` 枚举，作为文档字段随 `.ymind` 持久化；切换入命令栈可撤销。为切换、重绘、持久化提供基础。实现 UJ-E2 / UJ-E2b。

**功能需求：**

#### FR-E1：EdgeStyle 枚举、文档字段与 Codec 迁移

新增 `EdgeStyle`（`.elbow` / `.curve` / `.brace`）；`MindMapDocument` 增 `edgeStyle` 字段（缺省 `.elbow`），随 `.ymind` 持久化；Codec 升版本迁移（老文件缺省 `.elbow`，零拒绝）；切换入命令栈。

**Consequences（可测）：**
- `enum EdgeStyle: String, Codable, Sendable, Equatable { case elbow, curve, brace }`，缺省 `.elbow`。
- `MindMapDocument` 增 `edgeStyle: EdgeStyle`（缺省 `.elbow`）；`YMindCodec` 升**版本号**并迁移：老文件缺省 `.edgeStyle = .elbow`，零拒绝打开（同 `fill` / `layout` 先例）。
- **Codec 版本协调**：当前 main 为 v4；布局功能（PRD-L）同样计划升 v5。本增量与布局谁先合入 main 谁取下一个版本号，后到者取再下一个（或两者协调共享同一版本）。**不得与布局 PRD 撞同一版本号**（详见 §9.4 开放问题）。
- `DocumentSession` 暴露 `edgeStyle`（`@Published` 或读取 `model.document.edgeStyle`），供工具栏与渲染读取。
- 切换样式**入命令栈**（`setEdgeStyle` 命令，仿 `setFill` / `setLayout` 先例）：执行 `commitEditingIfNeeded()` → 改 `model.document.edgeStyle` → `relayout()`；Undo/Redo 均可往返。no-op（同样式）不入栈。
- `sanitize` 不变（样式是枚举标量，无节点约束）。

**Out of Scope：** 按分支/按节点设样式（全局一种）；样式级配色/粗细（独立课题）。

### 4.2 连线几何产出

**描述：** Layout 层按当前样式产出对应 `EdgeGeometry`；`EdgeGeometry` 扩样式与控制点字段。为 Render 提供几何。实现 UJ-E1 / UJ-E2。

**功能需求：**

#### FR-E2：Layout 按样式产边几何

`EdgeGeometry` 扩 `style: EdgeStyle` 与（曲线用）控制点；`RadialLayout` / `LogicLayout` 按传入样式生成折线 / 曲线 / 大括号几何；`LayoutEngine` 协议与 `LayoutPipeline` 传入样式。

**Consequences（可测）：**
- `EdgeGeometry` 增 `style: EdgeStyle`；`curve` 样式增两个贝塞尔控制点（`c1, c2: CGPoint?`），`elbow` / `brace` 以 `points` 折线表达（brace 的括号弧由 Layout 细分采样成足够密的多段点，走现有描边管线）。
- **引擎读 `document.edgeStyle`**：`edgeStyle` 是文档字段（FR-E1），`RadialLayout` / `LogicLayout` 的 `layout(document:measure:)` **直接读 `document.edgeStyle`** 按样式分支产几何——**LayoutEngine 协议 / LayoutPipeline / PNGExporter 签名不变**（都已传 `document`）。
- 边几何规则：`elbow` 沿用现状 3 段折线；`curve` 水平边带垂直隆起（`points` 存起止点 + `c1/c2`），垂直边轴向平滑；`brace` 根→主分支 `}`、主分支→子 `∪`。
- 样式切换不改布局算法与节点排布——只换 `EdgeGeometry` 产出。

**Out of Scope：** 按分支/按节点设样式（全局一种）；因样式调整布局。

### 4.3 渲染曲线细分

**描述：** Metal 层对曲线样式做细分采样后复用现有逐段描边管线；折线/大括号走原路径。Render 仍只消费 `LayoutSnapshot`。实现 UJ-E1。

**功能需求：**

#### FR-E3：曲线细分描边

`MetalRenderer.edgeVertices` 对 `.curve` 样式的边按控制点采样成线段后喂现有 `strokeVertices` 管线；`.elbow` / `.brace` 走 `points` 逐段描边。

**Consequences（可测）：**
- `.curve`：把 `(start, c1, c2, end)` 三次贝塞尔采样为 ~16–24 段折线，复用现有描边（无新 shader，Metal 改动最小）。
- `.elbow` / `.brace`：`points` 逐相邻点描边，逻辑不变。
- 曲线视觉平滑、无折角感；粗细随相机缩放一致（沿用现有 `strokeVertices` 厚度逻辑）。
- 命中测试 / 选中仍基于 `NodeFrame`，与边形态无关（边不可点选，无新命中逻辑）。

**Out of Scope：** 新 shader / GPU 曲线光栅化（CPU 细分足够，v1 不做）；连线粗细/端头/颜色定制。

### 4.4 切换器

**描述：** 工具栏「连线样式」菜单一键切换，切换入命令栈，选中/折叠/相机无损。实现 UJ-E1 / UJ-E3。

**功能需求：**

#### FR-E4：工具栏切换器与命令

`MainToolbar`（SwiftUI 壳层）增「连线样式」菜单/分段控件（曲线 / 大括号 / 正交折线），当前样式高亮；切换 → `session.setEdgeStyle(_:)` 命令 → `relayout()`。

**Consequences（可测）：**
- `DocumentSession.setEdgeStyle(_ kind:)`：`commitEditingIfNeeded()` → `commandBus.execute(.setEdgeStyle(kind: kind))`（仿 `setLayout` 先例）→ `relayout()`。
- 新增命令 `setEdgeStyle(kind:)` 入 `MindMapCommand`；apply 改 `model.document.edgeStyle` 并触发重排；undo/redo 反向重排；no-op 不入栈。
- 切换后选中节点集合、折叠分支、相机（center/scale）**全部保持**（不重设选中、不重置视图）。
- 切换器在无选中/多选/任意布局（辐射或逻辑图）下均可用（全局属性，与选中无关）。
- 可选快捷键循环（如 ⇧E），实现时定，不与现有快捷键冲突。

**Out of Scope：** 样式切换动画过渡（瞬时切换即可）。

### 4.5 导出一致

**描述：** PNG 导出按当前样式渲染，与屏幕一致。实现 UJ-E2 收尾。

**功能需求：**

#### FR-E5：导出按当前样式

PNG 导出（全展开）按当前 `edgeStyle` 离屏渲染；Markdown 结构导出不表达连线样式。

**Consequences（可测）：**
- PNG 导出复用 `MetalRenderer` 的 `LayoutSnapshot` 管线——`relayout()` 产出哪张快照渲染哪张，`document.edgeStyle` 已含在文档里，自动按当前样式渲染（零改动）。
- Markdown 导出输出树结构，与连线样式无关，零改动。
- `.ymind` 持久化 `edgeStyle`（FR-E1 迁移兜底），导出反映当前样式。

**Out of Scope：** 导出模板按样式固定（如特定曲线配固定分页）。

## 5. 非目标（明确不做）

- **按分支 / 按节点**分别设样式（作用域 = 全局一种）。
- **连线动画过渡**、**箭头端头 / 线条粗细 / 线条颜色**（独立课题，后置）。
- **联系线 Relationship**（XMind 式任意两主题自定义连线，是独立元素，非父-子结构线）。
- **因样式调整布局**——只换连线几何，布局算法与节点排布不变。

## 6. 验收要点

| # | 场景 | 期望 |
|---|------|------|
| 1 | 工具栏连线样式切换 曲线/大括号/正交折线 | 整图连线立即重排为对应形态；当前样式高亮 |
| 2 | 切换后选中/折叠/相机 | 全部保持，不重设、不重置视图 |
| 2b | 切换后 ⌘Z / ⌘⇧Z | 样式往返切换；选中、折叠、相机保持 |
| 3 | 曲线样式 | 水平边（根→主分支）可见平滑弧度（垂直隆起），区别于正交折线的直角；垂直边轴向平滑；无折角感 |
| 4 | 大括号样式 | 根→主分支为 `}` 括号；主分支→子为 `∪` 杯形；总分从属语义可辨 |
| 5 | 正交折线（默认） | 保持现状 3 段折线形态 |
| 5b | 保存并重新打开 `.ymind` | 样式保持上次选择（Codec 迁移：老文件缺省 `.elbow` 零拒绝） |
| 6 | 任意布局下切换 | 辐射 / 逻辑图布局下切换器均可用，样式在两种布局都生效 |
| 7 | 无选中/多选时切换 | 切换器可用（全局属性，与选中无关） |
| 8 | 导出 PNG | 按当前样式渲染，与屏幕一致 |
| 9 | 分层 / 格式 | `check-boundaries.sh` 绿（无新增 import）；`currentVersion` 升版本号（与布局 PRD 协调，见 §9.4） |
| 10 | 原型对照 | `prototype/edge-style.html` 三样式观感与切换交互一致（已浏览器 + vision 实测） |

对应机会卡片 §4（FR-E1…E5）。

## 7. 原型对照

| 原型（`prototype/edge-style.html`） | 需求 |
|------|------|
| 样式卡片（正交折线 / 曲线 / 大括号）点选 + 徽标/卡片/toast 三态一致 | FR-E1 / FR-E4 |
| 「循环切换样式（⇧E）」 | FR-E4 |
| 曲线（水平边垂直隆起弧线）/ 大括号（`}`+`∪`）/ 正交折线 三种边几何 | FR-E2 / FR-E3 |
| 切换即时重绘、选中/折叠/相机无损 | FR-E4 |
| 「语义」tab（曲线/大括号/折线语义） | §1 |
| 「边界与非目标」tab | §5 |

## 8. 原生实现备注

见 `addendum.md`：EdgeStyle 文档字段与 Codec 迁移、EdgeGeometry 扩字段、Layout 引擎读 `document.edgeStyle`、曲线细分描边、setEdgeStyle 命令与 relayout 单点、切换器 UI、PNGExporter、测试建议。

---

## 9. 开放问题

1. **排期**：`[待拍板]` 推荐 **紧随 1.0（迁移闭环 + 节点图片）之后**——同在 Layout/Render 接缝动，避免与 1.0 并行开发抢冲突；本课题独立、可随时插入。
2. ~~样式持久化 / Undo 是否做~~：**已解决**——产品本人拍板**持久化 + 入命令栈**（本修订）。原「会话态、不持久化」决策作废。
3. **大括号在逻辑图布局的形态**：`[ASSUMPTION]` 与辐射一致（根→主分支 `}`、主分支→子 `∪`），逻辑图总分树下 `}` 与总分语义更契合；实现时按同一规则产出。
4. **Codec 版本号**：`[已定]` 当前 main 已为 **v6**（布局功能已合入，`layout` 字段 v5 持久化 + v6 根折叠迁移）。本增量 `edgeStyle` 字段升 **v6 → v7**，无版本冲突。开发时遵循 `ymind-codec-version`（老文件缺省 `.elbow` 零拒绝）。
5. **切换快捷键**：默认绑定 ⇧E 循环？`[ASSUMPTION: 绑定 ⇧E，不与现有快捷键冲突；实现时确认]`。

## 10. 假设索引

- §0：动机 = 视觉打磨 + 语义分层两者都要、作用域 = 全局一种、成功 = 一键切换 + 无损（产品本人访谈确认；ICE 见机会卡片）。
- §2 UJ：目标用户会为「观感专业」与「总分从属语义」切换连线样式 `[ASSUMPTION]`（访谈确认方向，具体触发频度待验证）。
- §4 FR-E1：样式持久化 + 入命令栈（产品本人拍板，本修订推翻原「会话态、不持久化」）；Codec 版本与布局 PRD 协调（见 §9.4）`[ASSUMPTION]`。
- §4 FR-E2：曲线可用 Layout 产控制点 + Render 细分实现，Metal 改动最小、无需新 shader `[ASSUMPTION]`（架构：`MetalRenderer` 只消费 `LayoutSnapshot`）。
- §4 FR-E3：CPU 细分 16–24 段足以平滑，视觉无折角 `[ASSUMPTION]`（实现时按观感调段数）。
- §9.3/9.4/9.5：逻辑图括号形态、Codec 版本协调、快捷键细节 `[ASSUMPTION]`。
